import asyncio
import uuid
from collections import deque
from pathlib import Path
from typing import Deque, Dict, Optional, Set

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse

app = FastAPI(title="Realtime 4-Player Matchmaking Chat")

QUEUE_TARGET = 4
waiting_pool: Deque[WebSocket] = deque()
rooms: Dict[str, Set[WebSocket]] = {}
socket_to_room: Dict[WebSocket, str] = {}
state_lock = asyncio.Lock()


@app.get("/")
async def read_index() -> FileResponse:
    return FileResponse(Path("static/index.html"))


async def send_json_safe(ws: WebSocket, payload: dict) -> None:
    try:
        await ws.send_json(payload)
    except Exception:
        # Broken sockets are cleaned up during disconnect handling.
        pass


async def broadcast_waiting_status() -> None:
    count = len(waiting_pool)
    payload = {
        "type": "queue_status",
        "current": count,
        "target": QUEUE_TARGET,
        "message": f"Waiting for players... {count}/{QUEUE_TARGET} joined",
    }
    for ws in list(waiting_pool):
        await send_json_safe(ws, payload)


async def try_matchmake_locked() -> None:
    while len(waiting_pool) >= QUEUE_TARGET:
        group = [waiting_pool.popleft() for _ in range(QUEUE_TARGET)]
        room_id = str(uuid.uuid4())[:8]
        rooms[room_id] = set(group)

        for ws in group:
            socket_to_room[ws] = room_id

        for ws in group:
            await send_json_safe(
                ws,
                {
                    "type": "matched",
                    "room_id": room_id,
                    "message": f"You are matched in room {room_id}",
                },
            )


async def broadcast_room(
    room_id: str, payload: dict, exclude: Optional[WebSocket] = None
) -> None:
    for ws in rooms.get(room_id, set()).copy():
        if exclude is not None and ws is exclude:
            continue
        await send_json_safe(ws, payload)


def remove_from_waiting_locked(ws: WebSocket) -> None:
    try:
        waiting_pool.remove(ws)
    except ValueError:
        pass


async def cleanup_socket(ws: WebSocket) -> None:
    async with state_lock:
        if ws in waiting_pool:
            remove_from_waiting_locked(ws)
            await broadcast_waiting_status()

        room_id = socket_to_room.pop(ws, None)
        if room_id is not None and room_id in rooms:
            rooms[room_id].discard(ws)

            await broadcast_room(
                room_id,
                {"type": "user_disconnected", "message": "A user disconnected."},
                exclude=ws,
            )

            if not rooms[room_id]:
                del rooms[room_id]


@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket) -> None:
    await ws.accept()

    async with state_lock:
        waiting_pool.append(ws)
        await broadcast_waiting_status()
        await try_matchmake_locked()
        await broadcast_waiting_status()

    try:
        while True:
            data = await ws.receive_json()
            if data.get("type") != "chat":
                continue

            text = (data.get("text") or "").strip()
            if not text:
                continue

            room_id = socket_to_room.get(ws)
            if not room_id:
                continue

            await broadcast_room(
                room_id,
                {"type": "chat", "room_id": room_id, "text": text},
                exclude=ws,
            )
    except WebSocketDisconnect:
        await cleanup_socket(ws)
    except Exception:
        await cleanup_socket(ws)
