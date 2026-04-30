import asyncio
import time
import uuid
from collections import deque
from pathlib import Path
from typing import Deque, Dict, Optional, Set

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse, JSONResponse

app = FastAPI(title="most")

QUEUE_SIZES = (2, 4)
RECONNECT_GRACE_SECONDS = 45
MAX_MSG_WINDOW_SECONDS = 10
MAX_MSG_PER_WINDOW = 8
BLOCKED_WORDS = {"spamword", "badword"}

BASE_DIR = Path(__file__).resolve().parent
INDEX_FILE = BASE_DIR / "static" / "index.html"

state_lock = asyncio.Lock()
waiting_pools: Dict[int, Deque[str]] = {size: deque() for size in QUEUE_SIZES}
socket_to_client: Dict[WebSocket, str] = {}

clients: Dict[str, dict] = {}
rooms: Dict[str, dict] = {}
stats = {
    "matches_created": 0,
    "messages_sent": 0,
    "reactions_used": 0,
    "reconnect_success": 0,
}


@app.get("/")
async def read_index() -> FileResponse:
    return FileResponse(INDEX_FILE)


@app.get("/health")
async def health() -> JSONResponse:
    return JSONResponse({"ok": True})


@app.get("/stats")
async def service_stats() -> JSONResponse:
    active_rooms = len(rooms)
    connected_clients = sum(1 for data in clients.values() if data.get("connected"))
    queued_clients = sum(len(pool) for pool in waiting_pools.values())
    return JSONResponse(
        {
            "active_rooms": active_rooms,
            "connected_clients": connected_clients,
            "queued_clients": queued_clients,
            **stats,
        }
    )


def member_payload(client_id: str) -> dict:
    client = clients.get(client_id, {})
    return {
        "client_id": client_id,
        "nickname": client.get("nickname", "Guest"),
        "color": client.get("color", "#6d7bff"),
    }


async def send_to_client(client_id: str, payload: dict) -> None:
    client = clients.get(client_id)
    if not client:
        return
    ws = client.get("ws")
    if not ws:
        return
    try:
        await ws.send_json(payload)
    except Exception:
        pass


async def broadcast_room(room_id: str, payload: dict) -> None:
    room = rooms.get(room_id)
    if not room:
        return
    for client_id in list(room["members"]):
        await send_to_client(client_id, payload)


async def broadcast_waiting_status(size: int) -> None:
    count = len(waiting_pools[size])
    payload = {
        "type": "queue_status",
        "size": size,
        "current": count,
        "target": size,
        "message": f"Waiting for players... {count}/{size} joined",
    }
    for client_id in list(waiting_pools[size]):
        await send_to_client(client_id, payload)


def remove_from_queue_locked(client_id: str) -> Optional[int]:
    client = clients.get(client_id)
    if not client:
        return None
    queue_size = client.get("queue_size")
    if queue_size is None:
        return None
    try:
        waiting_pools[queue_size].remove(client_id)
    except ValueError:
        pass
    client["queue_size"] = None
    return queue_size


def pick_room_theme(member_ids: list[str]) -> str:
    counts: Dict[str, int] = {}
    for member_id in member_ids:
        theme = clients.get(member_id, {}).get("theme", "nebula")
        counts[theme] = counts.get(theme, 0) + 1
    return max(counts, key=counts.get) if counts else "nebula"


async def finalize_member_disconnect(client_id: str, room_id: str) -> None:
    await asyncio.sleep(RECONNECT_GRACE_SECONDS)
    async with state_lock:
        client = clients.get(client_id)
        room = rooms.get(room_id)
        if not client or not room:
            return
        if client.get("connected"):
            return
        if client.get("room_id") != room_id:
            return

        room["members"].discard(client_id)
        client["room_id"] = None
        client["disconnected_at"] = None

        await broadcast_room(
            room_id,
            {
                "type": "user_removed",
                "message": f"{client.get('nickname', 'A user')} did not reconnect in time.",
            },
        )
        if not room["members"]:
            del rooms[room_id]


async def leave_room_locked(client_id: str, disconnected: bool = False) -> Optional[str]:
    client = clients.get(client_id)
    if not client:
        return None
    room_id = client.get("room_id")
    if not room_id:
        return None
    room = rooms.get(room_id)
    if not room:
        client["room_id"] = None
        return None

    if disconnected:
        client["connected"] = False
        client["ws"] = None
        client["disconnected_at"] = time.time()
        await broadcast_room(
            room_id,
            {
                "type": "user_disconnected",
                "client_id": client_id,
                "message": f"{client.get('nickname', 'A user')} disconnected. Waiting for reconnect...",
            },
        )
        asyncio.create_task(finalize_member_disconnect(client_id, room_id))
        return room_id

    room["members"].discard(client_id)
    client["room_id"] = None
    client["disconnected_at"] = None
    await broadcast_room(
        room_id,
        {
            "type": "user_left_room",
            "client_id": client_id,
            "message": f"{client.get('nickname', 'A user')} left the chat.",
        },
    )
    if not room["members"]:
        del rooms[room_id]
    return room_id


def sanitize_text(value: str) -> str:
    return value.strip()[:350]


def message_allowed(client: dict) -> bool:
    now = time.time()
    message_times: Deque[float] = client["message_times"]
    while message_times and now - message_times[0] > MAX_MSG_WINDOW_SECONDS:
        message_times.popleft()
    if len(message_times) >= MAX_MSG_PER_WINDOW:
        return False
    message_times.append(now)
    return True


def contains_blocked_words(text: str) -> bool:
    lowered = f" {text.lower()} "
    return any(f" {word} " in lowered for word in BLOCKED_WORDS)


async def send_room_snapshot(client_id: str, room_id: str, reconnect: bool = False) -> None:
    room = rooms.get(room_id)
    client = clients.get(client_id)
    if not room or not client:
        return
    payload = {
        "type": "reconnected" if reconnect else "matched",
        "room_id": room_id,
        "size": room["size"],
        "theme": room["theme"],
        "members": [member_payload(member_id) for member_id in room["members"]],
        "messages": room["messages"][-40:],
    }
    await send_to_client(client_id, payload)


async def try_matchmake_locked(size: int) -> None:
    pool = waiting_pools[size]
    while len(pool) >= size:
        member_ids = [pool.popleft() for _ in range(size)]
        room_id = str(uuid.uuid4())[:8]
        room = {
            "id": room_id,
            "size": size,
            "theme": pick_room_theme(member_ids),
            "members": set(member_ids),
            "messages": [],
        }
        rooms[room_id] = room
        stats["matches_created"] += 1

        for member_id in member_ids:
            client = clients[member_id]
            client["queue_size"] = None
            client["room_id"] = room_id
            client["disconnected_at"] = None

        for member_id in member_ids:
            await send_room_snapshot(member_id, room_id, reconnect=False)


async def cleanup_socket(ws: WebSocket) -> None:
    async with state_lock:
        client_id = socket_to_client.pop(ws, None)
        if not client_id:
            return
        client = clients.get(client_id)
        if not client:
            return
        client["connected"] = False
        client["ws"] = None
        queue_size = remove_from_queue_locked(client_id)
        if queue_size is not None:
            await broadcast_waiting_status(queue_size)
        await leave_room_locked(client_id, disconnected=True)


@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket) -> None:
    await ws.accept()
    await ws.send_json({"type": "connected", "message": "Connected to most."})

    try:
        while True:
            data = await ws.receive_json()
            message_type = data.get("type")

            if message_type == "hello":
                client_id = str(data.get("client_id") or "").strip() or str(uuid.uuid4())
                nickname = str(data.get("nickname") or "Guest").strip()[:24] or "Guest"
                color = str(data.get("color") or "#6d7bff").strip()[:16]
                theme = str(data.get("theme") or "nebula").strip()[:24]

                async with state_lock:
                    old_client = clients.get(client_id)
                    if old_client and old_client.get("ws") and old_client["ws"] is not ws:
                        socket_to_client.pop(old_client["ws"], None)
                        old_client["ws"] = None
                        old_client["connected"] = False

                    client = clients.setdefault(
                        client_id,
                        {
                            "nickname": nickname,
                            "color": color,
                            "theme": theme,
                            "ws": None,
                            "connected": False,
                            "queue_size": None,
                            "room_id": None,
                            "disconnected_at": None,
                            "message_times": deque(),
                        },
                    )
                    client["nickname"] = nickname
                    client["color"] = color
                    client["theme"] = theme
                    client["ws"] = ws
                    client["connected"] = True
                    client["disconnected_at"] = None
                    socket_to_client[ws] = client_id

                    await send_to_client(
                        client_id,
                        {
                            "type": "hello_ack",
                            "client_id": client_id,
                            "nickname": nickname,
                            "color": color,
                            "theme": theme,
                        },
                    )

                    room_id = client.get("room_id")
                    if room_id and room_id in rooms:
                        stats["reconnect_success"] += 1
                        await send_room_snapshot(client_id, room_id, reconnect=True)
                        await broadcast_room(
                            room_id,
                            {
                                "type": "user_reconnected",
                                "client_id": client_id,
                                "message": f"{nickname} reconnected.",
                            },
                        )
                continue

            client_id = socket_to_client.get(ws)
            if not client_id:
                await ws.send_json(
                    {"type": "error", "message": "Send hello first to initialize profile."}
                )
                continue

            if message_type == "profile_update":
                nickname = str(data.get("nickname") or "").strip()[:24] or "Guest"
                color = str(data.get("color") or "#6d7bff").strip()[:16]
                theme = str(data.get("theme") or "nebula").strip()[:24]
                async with state_lock:
                    client = clients[client_id]
                    client["nickname"] = nickname
                    client["color"] = color
                    client["theme"] = theme
                await send_to_client(
                    client_id,
                    {"type": "profile_saved", "nickname": nickname, "color": color, "theme": theme},
                )
                continue

            if message_type == "join_queue":
                requested_size = int(data.get("size", 0))
                if requested_size not in QUEUE_SIZES:
                    await send_to_client(
                        client_id, {"type": "error", "message": "Queue size must be 2 or 4."}
                    )
                    continue
                async with state_lock:
                    remove_size = remove_from_queue_locked(client_id)
                    if remove_size is not None:
                        await broadcast_waiting_status(remove_size)
                    await leave_room_locked(client_id)
                    waiting_pools[requested_size].append(client_id)
                    clients[client_id]["queue_size"] = requested_size
                    await broadcast_waiting_status(requested_size)
                    await try_matchmake_locked(requested_size)
                    await broadcast_waiting_status(requested_size)
                continue

            if message_type == "leave_queue":
                async with state_lock:
                    queue_size = remove_from_queue_locked(client_id)
                    if queue_size is not None:
                        await broadcast_waiting_status(queue_size)
                await send_to_client(client_id, {"type": "queue_left", "message": "You left queue."})
                continue

            if message_type == "leave_room":
                async with state_lock:
                    await leave_room_locked(client_id)
                await send_to_client(client_id, {"type": "room_left", "message": "You left room."})
                continue

            if message_type == "chat":
                text = sanitize_text(str(data.get("text") or ""))
                if not text:
                    continue
                async with state_lock:
                    client = clients.get(client_id)
                    if not client:
                        continue
                    room_id = client.get("room_id")
                    if not room_id or room_id not in rooms:
                        continue
                    if not message_allowed(client):
                        await send_to_client(
                            client_id,
                            {
                                "type": "error",
                                "message": "Rate limit reached. Please wait before sending again.",
                            },
                        )
                        continue
                    if contains_blocked_words(text):
                        await send_to_client(
                            client_id,
                            {"type": "error", "message": "Message blocked by moderation filter."},
                        )
                        continue

                    message = {
                        "id": str(uuid.uuid4())[:10],
                        "sender": member_payload(client_id),
                        "text": text,
                        "reactions": {},
                        "ts": int(time.time()),
                    }
                    rooms[room_id]["messages"].append(message)
                    stats["messages_sent"] += 1
                    await broadcast_room(room_id, {"type": "chat", "room_id": room_id, "message": message})
                continue

            if message_type == "react":
                message_id = str(data.get("message_id") or "").strip()
                emoji = str(data.get("emoji") or "").strip()[:4]
                if not message_id or not emoji:
                    continue
                async with state_lock:
                    client = clients.get(client_id)
                    if not client:
                        continue
                    room_id = client.get("room_id")
                    room = rooms.get(room_id or "")
                    if not room:
                        continue
                    target = next((msg for msg in room["messages"] if msg["id"] == message_id), None)
                    if not target:
                        continue
                    current = target["reactions"].get(emoji, [])
                    if client_id in current:
                        current.remove(client_id)
                    else:
                        current.append(client_id)
                    target["reactions"][emoji] = current
                    stats["reactions_used"] += 1
                    await broadcast_room(
                        room_id,
                        {
                            "type": "reaction_update",
                            "message_id": message_id,
                            "reactions": target["reactions"],
                        },
                    )
                continue
    except WebSocketDisconnect:
        await cleanup_socket(ws)
    except Exception:
        await cleanup_socket(ws)
