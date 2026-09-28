"""PulseLoom encrypted-message relay. TLS terminates at the included Caddy service.
The server never receives the end-to-end key. Capability tokens stay out of URLs/logs.
Run a single worker; rooms are deliberately ephemeral and memory-only.
"""
from __future__ import annotations

import asyncio
import base64
import hashlib
import hmac
import json
import os
import secrets
import time
from collections import defaultdict, deque
from contextlib import asynccontextmanager, suppress
from dataclasses import dataclass, field
from typing import Callable

from fastapi import FastAPI, HTTPException, Request, WebSocket, WebSocketDisconnect

MAX_FRAME = 65_536
MAX_PAYLOAD = 32_768
MAX_ROOMS = 1000
ROOM_TTL = 3600
AUTH_TIMEOUT = 5
MESSAGES_PER_SECOND = 30


@dataclass
class Room:
    name: str
    tokens: dict[str, bytes]
    created: float
    peers: dict[str, WebSocket] = field(default_factory=dict)


class Registry:
    def __init__(self, now: Callable[[], float] = time.monotonic):
        self.now = now
        self.rooms: dict[str, Room] = {}
        self.creation: dict[str, deque[float]] = defaultdict(deque)
        self.pending_auth = 0
        self.lock = asyncio.Lock()

    def create(self, ip: str) -> dict[str, str]:
        current = self.now()
        # A bounded IP map prevents unbounded memory through distributed requests.
        if len(self.creation) > 5000:
            self.creation = defaultdict(deque, {k: q for k, q in self.creation.items() if q and current - q[-1] < 60})
        if ip not in self.creation and len(self.creation) >= 5000:
            raise HTTPException(503, "Relay is busy")
        q = self.creation[ip]
        while q and current - q[0] >= 60:
            q.popleft()
        if len(q) >= 6:
            raise HTTPException(429, "Room creation limit reached", headers={"Retry-After": "60"})
        if len(self.rooms) >= MAX_ROOMS:
            raise HTTPException(503, "Relay is full")
        q.append(current)
        name = secrets.token_urlsafe(18)
        sender, receiver = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
        self.rooms[name] = Room(name, {"sender": self.digest(sender), "receiver": self.digest(receiver)}, current)
        return {"room": name, "sender_token": sender, "receiver_token": receiver}

    @staticmethod
    def digest(token: str) -> bytes:
        return hashlib.sha256(token.encode("utf-8")).digest()

    async def sweep(self) -> None:
        stale = [key for key, value in self.rooms.items() if self.now() - value.created > ROOM_TTL]
        for key in stale:
            room = self.rooms.pop(key, None)
            if room:
                for socket in list(room.peers.values()):
                    with suppress(Exception):
                        await socket.close(code=4008, reason="Room expired")


def create_app(registry: Registry | None = None) -> FastAPI:
    registry = registry or Registry()

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        async def expire():
            while True:
                await asyncio.sleep(15)
                await registry.sweep()
        task = asyncio.create_task(expire())
        try:
            yield
        finally:
            task.cancel()
            with suppress(asyncio.CancelledError):
                await task
            for room in list(registry.rooms.values()):
                for socket in list(room.peers.values()):
                    with suppress(Exception):
                        await socket.close(code=1012, reason="Relay stopping")
            registry.rooms.clear()

    app = FastAPI(title="PulseLoom Relay", docs_url=None, redoc_url=None, lifespan=lifespan)
    app.state.registry = registry

    @app.get("/health")
    async def health():
        return {"status": "ok", "protocol": 1}

    @app.post("/v1/rooms", status_code=201)
    async def create_room(request: Request):
        # Uvicorn trusts proxy headers ONLY from the private Caddy address/network.
        ip = request.client.host if request.client else "unknown"
        await registry.sweep()
        async with registry.lock:
            return registry.create(ip)

    @app.websocket("/v1/rooms/{room_id}/ws")
    async def socket_endpoint(socket: WebSocket, room_id: str):
        room: Room | None = None
        role: str | None = None
        registered = False
        accepted = False
        auth_slot = False
        try:
            if len(room_id) > 64 or registry.pending_auth >= 100:
                await socket.close(code=1008)
                return
            registry.pending_auth += 1
            auth_slot = True
            await socket.accept()
            accepted = True
            message = await asyncio.wait_for(socket.receive(), AUTH_TIMEOUT)
            data = message.get("bytes") or message.get("text", "").encode("utf-8")
            if not data or len(data) > 2048:
                await socket.close(code=4001, reason="Authentication required")
                return
            auth = json.loads(data)
            if not isinstance(auth, dict) or auth.get("type") != "auth":
                await socket.close(code=4001, reason="Authentication required")
                return
            role, token = auth.get("role"), auth.get("token")
            room = registry.rooms.get(room_id)
            if (not room or registry.now() - room.created > ROOM_TTL or role not in ("sender", "receiver")
                    or not isinstance(token, str) or len(token) > 128
                    or not hmac.compare_digest(room.tokens[role], registry.digest(token))):
                await socket.close(code=4001, reason="Invalid credentials")
                return
            async with registry.lock:
                if role in room.peers:
                    await socket.close(code=4009, reason="Role already connected")
                    return
                room.peers[role] = socket
                registered = True
            registry.pending_auth -= 1
            auth_slot = False
            await socket.send_json({"type": "ready"})
            other_role = "receiver" if role == "sender" else "sender"
            other = room.peers.get(other_role)
            if other:
                await other.send_json({"type": "peer_joined"})
                await socket.send_json({"type": "peer_joined"})
            sent: deque[float] = deque()
            while True:
                # Native clients send a heartbeat every three seconds. Abandoned sockets expire.
                msg = await asyncio.wait_for(socket.receive(), 15)
                if msg["type"] == "websocket.disconnect":
                    break
                raw = msg.get("bytes") or msg.get("text", "").encode("utf-8")
                if not raw or len(raw) > MAX_FRAME:
                    await socket.close(code=1009, reason="Frame limit exceeded")
                    break
                envelope = json.loads(raw)
                if not isinstance(envelope, dict) or set(envelope) != {"type", "payload"} or envelope["type"] != "data":
                    await socket.close(code=1008, reason="Invalid envelope")
                    break
                payload = envelope["payload"]
                if not isinstance(payload, str) or len(payload) > MAX_PAYLOAD:
                    await socket.close(code=1009, reason="Payload limit exceeded")
                    break
                decoded = base64.b64decode(payload, validate=True)
                if not 28 <= len(decoded) <= MAX_PAYLOAD:
                    await socket.close(code=1008, reason="Invalid encrypted payload")
                    break
                now = registry.now()
                if now - room.created > ROOM_TTL:
                    await socket.close(code=4008, reason="Room expired")
                    break
                while sent and now - sent[0] > 1:
                    sent.popleft()
                if len(sent) >= MESSAGES_PER_SECOND:
                    await socket.close(code=4029, reason="Message rate exceeded")
                    break
                sent.append(now)
                if other := room.peers.get(other_role):
                    await asyncio.wait_for(other.send_json({"type": "data", "payload": payload}), 3)
        except (WebSocketDisconnect, asyncio.TimeoutError):
            if accepted:
                with suppress(Exception):
                    await socket.close(code=4008, reason="Connection timed out")
        except (ValueError, KeyError, TypeError, UnicodeError):
            with suppress(Exception):
                await socket.close(code=1008, reason="Invalid protocol data")
        except Exception:
            # No payloads, bearer tokens, invitation links or audio content in exception logs.
            with suppress(Exception):
                await socket.close(code=1011, reason="Connection error")
        finally:
            if auth_slot:
                registry.pending_auth -= 1
            if registered and room and role and room.peers.get(role) is socket:
                room.peers.pop(role, None)
                other = room.peers.get("receiver" if role == "sender" else "sender")
                if other:
                    with suppress(Exception):
                        await other.send_json({"type": "peer_left"})

    return app


app = create_app()
