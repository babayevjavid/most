import asyncio
import uuid
from collections import deque
from pathlib import Path
from typing import Deque, Dict, Optional, Set

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse

app = FastAPI(title="most")

QUEUE_SIZES = (2, 4)
waiting_pools: Dict[int, Deque[WebSocket]] = {size: deque() for size in QUEUE_SIZES}
socket_to_queue_size: Dict[WebSocket, int] = {}
rooms: Dict[str, Set[WebSocket]] = {}
room_to_size: Dict[str, int] = {}
socket_to_room: Dict[WebSocket, str] = {}
state_lock = asyncio.Lock()

BASE_DIR = Path(__file__).resolve().parent
INDEX_FILE = BASE_DIR / "static" / "index.html"


@app.get("/")
async def read_index() -> FileResponse:
    return FileResponse(INDEX_FILE)


async def send_json_safe(ws: WebSocket, payload: dict) -> None:
    try:
        await ws.send_json(payload)
    except Exception:
        pass


async def broadcast_waiting_status(size: int) -> None:
    pool = waiting_pools[size]
    count = len(pool)
    payload = {
        "type": "queue_status",
        "size": size,
        "current": count,
        "target": size,
        "message": f"Waiting for players... {count}/{size} joined",
    }
    for member in list(pool):
        await send_json_safe(member, payload)


def remove_from_queue_locked(ws: WebSocket) -> Optional[int]:
    queue_size = socket_to_queue_size.pop(ws, None)
    if queue_size is None:
        return None
    try:
        waiting_pools[queue_size].remove(ws)
    except ValueError:
        pass
    return queue_size


async def leave_room_locked(ws: WebSocket, disconnected: bool = False) -> Optional[str]:
    room_id = socket_to_room.pop(ws, None)
    if room_id is None or room_id not in rooms:
        return None

    rooms[room_id].discard(ws)
    payload = {
        "type": "user_disconnected" if disconnected else "user_left_room",
        "message": "A user disconnected." if disconnected else "A user left the chat.",
    }
    for member in rooms[room_id].copy():
        await send_json_safe(member, payload)

    if not rooms[room_id]:
        del rooms[room_id]
        room_to_size.pop(room_id, None)
    return room_id


async def try_matchmake_locked(size: int) -> None:
    pool = waiting_pools[size]
    while len(pool) >= size:
        group = [pool.popleft() for _ in range(size)]
        room_id = str(uuid.uuid4())[:8]
        rooms[room_id] = set(group)
        room_to_size[room_id] = size

        for member in group:
            socket_to_room[member] = room_id
            socket_to_queue_size.pop(member, None)

        for member in group:
            await send_json_safe(
                member,
                {
                    "type": "matched",
                    "room_id": room_id,
                    "size": size,
                    "message": f"You are matched in a {size}-player room: {room_id}",
                },
            )


async def cleanup_socket(ws: WebSocket) -> None:
    async with state_lock:
        queue_size = remove_from_queue_locked(ws)
        if queue_size is not None:
            await broadcast_waiting_status(queue_size)
        await leave_room_locked(ws, disconnected=True)


@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket) -> None:
    await ws.accept()
    await send_json_safe(
        ws,
        {
            "type": "connected",
            "message": "Connected. Choose 2-player or 4-player queue to start.",
        },
    )

    try:
        while True:
            data = await ws.receive_json()
            message_type = data.get("type")

            if message_type == "join_queue":
                requested_size = int(data.get("size", 0))
                if requested_size not in QUEUE_SIZES:
                    await send_json_safe(
                        ws,
                        {"type": "error", "message": "Queue size must be 2 or 4."},
                    )
                    continue

                async with state_lock:
                    remove_from_queue_locked(ws)
                    await leave_room_locked(ws)

                    waiting_pools[requested_size].append(ws)
                    socket_to_queue_size[ws] = requested_size
                    await broadcast_waiting_status(requested_size)
                    await try_matchmake_locked(requested_size)
                    await broadcast_waiting_status(requested_size)
                continue

            if message_type == "leave_queue":
                async with state_lock:
                    queue_size = remove_from_queue_locked(ws)
                    if queue_size is not None:
                        await broadcast_waiting_status(queue_size)
                await send_json_safe(
                    ws, {"type": "queue_left", "message": "You left the queue."}
                )
                continue

            if message_type == "leave_room":
                async with state_lock:
                    await leave_room_locked(ws)
                await send_json_safe(
                    ws, {"type": "room_left", "message": "You left the chat room."}
                )
                continue

            if message_type == "chat":
                text = (data.get("text") or "").strip()
                if not text:
                    continue

                room_id = socket_to_room.get(ws)
                if not room_id or room_id not in rooms:
                    continue

                for member in rooms[room_id].copy():
                    if member is ws:
                        continue
                    await send_json_safe(
                        member,
                        {"type": "chat", "room_id": room_id, "text": text},
                    )
                continue
    except WebSocketDisconnect:
        await cleanup_socket(ws)
    except Exception:
        await cleanup_socket(ws)
