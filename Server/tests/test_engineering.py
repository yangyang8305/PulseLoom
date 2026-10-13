"""Integration/system checks use the real ASGI app and real WebSockets, never an external deployment."""
import asyncio
import base64
import random
from collections import defaultdict

import pytest
from fastapi import HTTPException
from starlette.testclient import TestClient
from Server.app import Registry, create_app


def test_randomized_registry_creation_limiter_matches_independent_window_model():
    for seed in range(12):
        rng = random.Random(seed)
        now = [0.0]
        registry = Registry(lambda: now[0])
        accepted = defaultdict(list)
        for step in range(300):
            now[0] += rng.choice([0, 0.1, 1, 10, 60])
            ip = f"model-ip-{rng.randrange(4)}"
            recent = [t for t in accepted[ip] if now[0] - t < 60]
            allowed = len(recent) < 6
            try:
                result = registry.create(ip)
                assert allowed, (seed, step, "accepted rate limited operation")
                accepted[ip].append(now[0])
                assert result["sender_token"] != result["receiver_token"]
                assert result["room"] in registry.rooms
            except HTTPException as exc:
                assert not allowed and exc.status_code == 429, (seed, step, exc)
            assert registry.pending_auth == 0
        now[0] += 4000
        asyncio.run(registry.sweep())
        assert not registry.rooms
        assert not registry.creation


@pytest.mark.parametrize("direction", ["sender", "receiver"])
def test_bidirectional_socket_system_preserves_payload_order_and_cleans_peers(direction):
    with TestClient(create_app()) as client:
        r = client.post("/v1/rooms").json()
        path = f'/v1/rooms/{r["room"]}/ws'
        with client.websocket_connect(path) as sender:
            sender.send_json({"type": "auth", "role": "sender", "token": r["sender_token"]})
            assert sender.receive_json() == {"type": "ready"}
            with client.websocket_connect(path) as receiver:
                receiver.send_json({"type": "auth", "role": "receiver", "token": r["receiver_token"]})
                assert receiver.receive_json() == {"type": "ready"}
                assert sender.receive_json()["type"] == "peer_joined"
                assert receiver.receive_json()["type"] == "peer_joined"
                origin, destination = (sender, receiver) if direction == "sender" else (receiver, sender)
                for step in range(20):
                    # Opaque authenticated-encryption-sized frames; relay must not interpret cleartext commands.
                    payload = base64.b64encode(bytes([step]) * 64).decode()
                    origin.send_json({"type": "data", "payload": payload})
                    message = destination.receive_json()
                    assert message["type"] == "data"
                    assert message["payload"] == payload, step
            assert sender.receive_json()["type"] == "peer_left"
        room = client.app.state.registry.rooms[r["room"]]
        assert room.peers == {}
        assert client.app.state.registry.pending_auth == 0


def test_real_tcp_process_health_and_room_authentication():
    """Cross-process system test: uvicorn on an OS-assigned loopback port, real HTTP + WebSockets."""
    import json
    from pathlib import Path
    import socket
    import subprocess
    import sys
    import tempfile
    import time
    from urllib.request import Request, urlopen
    from websockets.sync.client import connect

    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen()
    port = listener.getsockname()[1]
    root = Path(__file__).resolve().parents[2]
    with tempfile.TemporaryFile() as log:
        process = subprocess.Popen([sys.executable, "-m", "uvicorn", "Server.app:create_app", "--factory",
                                    "--fd", str(listener.fileno()), "--log-level", "warning"],
                                   cwd=root, pass_fds=(listener.fileno(),), stdout=log, stderr=log)
        listener.close()
        try:
            deadline = time.monotonic() + 10
            base = f"http://127.0.0.1:{port}"
            while True:
                try:
                    with urlopen(base + "/health", timeout=0.5) as response:
                        assert json.load(response)["protocol"] == 1
                    break
                except OSError:
                    if process.poll() is not None or time.monotonic() >= deadline:
                        log.seek(0)
                        pytest.fail("Relay failed startup: " + log.read().decode())
                    time.sleep(0.05)
            with urlopen(Request(base + "/v1/rooms", data=b"", method="POST"), timeout=2) as response:
                assert response.status == 201
                room = json.load(response)
            url = f'ws://127.0.0.1:{port}/v1/rooms/{room["room"]}/ws'
            with connect(url, open_timeout=2) as sender, connect(url, open_timeout=2) as receiver:
                sender.send(json.dumps({"type": "auth", "role": "sender", "token": room["sender_token"]}))
                assert json.loads(sender.recv(timeout=2))["type"] == "ready"
                receiver.send(json.dumps({"type": "auth", "role": "receiver", "token": room["receiver_token"]}))
                assert json.loads(receiver.recv(timeout=2))["type"] == "ready"
                assert json.loads(sender.recv(timeout=2))["type"] == "peer_joined"
                assert json.loads(receiver.recv(timeout=2))["type"] == "peer_joined"
                payload = base64.b64encode(b"encrypted-opaque-payload" * 3).decode()
                sender.send(json.dumps({"type": "data", "payload": payload}))
                assert json.loads(receiver.recv(timeout=2))["payload"] == payload
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
