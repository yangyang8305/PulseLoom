import base64
import json
import pytest
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from starlette.testclient import TestClient
from starlette.websockets import WebSocketDisconnect
from Server.app import create_app, Registry

@pytest.fixture
def client():
    with TestClient(create_app()) as c:
        yield c

def auth(ws, room, role):
    ws.send_json({"type": "auth", "role": role, "token": room[f"{role}_token"]})
    assert ws.receive_json() == {"type": "ready"}

def room(client):
    r=client.post("/v1/rooms")
    assert r.status_code == 201
    return r.json()

def test_health(client):
    assert client.get("/health").json()["protocol"] == 1

def test_tokens_distinct_and_hashed(client):
    r=room(client)
    assert r["sender_token"] != r["receiver_token"]
    stored=client.app.state.registry.rooms[r["room"]]
    assert r["sender_token"].encode() != stored.tokens["sender"]
    assert len(stored.tokens["sender"]) == 32

def test_unauthorized(client):
    r=room(client)
    with client.websocket_connect(f'/v1/rooms/{r["room"]}/ws') as ws:
        ws.send_json({"type":"auth","role":"sender","token":"wrong"})
        with pytest.raises(WebSocketDisconnect) as e: ws.receive_json()
        assert e.value.code == 4001

def test_unknown_room(client):
    with client.websocket_connect('/v1/rooms/unknown/ws') as ws:
        ws.send_json({"type":"auth","role":"sender","token":"wrong"})
        with pytest.raises(WebSocketDisconnect): ws.receive_json()

def test_binary_auth_and_encrypted_round_trip(client):
    r=room(client); path=f'/v1/rooms/{r["room"]}/ws'
    key=AESGCM.generate_key(bit_length=256);aes=AESGCM(key);nonce=b'123456789012'
    plain=json.dumps({"sequence":1,"action":"start","gain":0.4,"patternID":"p02"}).encode()
    payload=base64.b64encode(nonce+aes.encrypt(nonce,plain,r["room"].encode())).decode()
    with client.websocket_connect(path) as sender:
        sender.send_bytes(json.dumps({"type":"auth","role":"sender","token":r["sender_token"]}).encode())
        assert sender.receive_json()["type"] == "ready"
        with client.websocket_connect(path) as receiver:
            auth(receiver,r,"receiver")
            assert sender.receive_json()["type"] == "peer_joined"
            assert receiver.receive_json()["type"] == "peer_joined"
            sender.send_bytes(json.dumps({"type":"data","payload":payload}).encode())
            relayed=receiver.receive_json()
            combined=base64.b64decode(relayed["payload"])
            assert aes.decrypt(combined[:12],combined[12:],r["room"].encode()) == plain
            # Tampering and wrong AAD are rejected by the end-to-end layer.
            with pytest.raises(Exception): aes.decrypt(combined[:12],combined[12:-1]+b'!',r["room"].encode())
            with pytest.raises(Exception): aes.decrypt(combined[:12],combined[12:],b'other-room')
        assert sender.receive_json()["type"] == "peer_left"

def test_duplicate_role_does_not_displace(client):
    r=room(client);path=f'/v1/rooms/{r["room"]}/ws'
    with client.websocket_connect(path) as a:
        auth(a,r,"sender")
        with client.websocket_connect(path) as b:
            b.send_json({"type":"auth","role":"sender","token":r["sender_token"]})
            with pytest.raises(WebSocketDisconnect) as e:b.receive_json()
            assert e.value.code==4009
        assert "sender" in client.app.state.registry.rooms[r["room"]].peers

@pytest.mark.parametrize("envelope",[
    {"type":"data","payload":"invalid-base64"},
    {"type":"data","payload":base64.b64encode(b'x').decode()},
    {"type":"data","payload":"a"*40000},
    {"type":"start","gain":0.9},
    ["not","a","dictionary"],
])
def test_rejects_invalid_payload(client,envelope):
    r=room(client)
    with client.websocket_connect(f'/v1/rooms/{r["room"]}/ws') as ws:
        auth(ws,r,"sender");ws.send_json(envelope)
        with pytest.raises(WebSocketDisconnect):ws.receive_json()

def test_creation_rate_limit(client):
    for _ in range(6):room(client)
    assert client.post('/v1/rooms').status_code==429

def test_expired_room_cannot_authenticate():
    now=[0.0];registry=Registry(lambda:now[0])
    with TestClient(create_app(registry)) as c:
        r=room(c);now[0]=4000
        with c.websocket_connect(f'/v1/rooms/{r["room"]}/ws') as ws:
            ws.send_json({"type":"auth","role":"sender","token":r["sender_token"]})
            with pytest.raises(WebSocketDisconnect):ws.receive_json()

def test_plaintext_command_never_relayed(client):
    r=room(client)
    with client.websocket_connect(f'/v1/rooms/{r["room"]}/ws') as ws:
        auth(ws,r,"sender");ws.send_json({"type":"data","payload":"plaintext","action":"start"})
        with pytest.raises(WebSocketDisconnect):ws.receive_json()

def test_message_rate_limit(client):
    r=room(client);payload=base64.b64encode(b'x'*32).decode()
    with client.websocket_connect(f'/v1/rooms/{r["room"]}/ws') as ws:
        auth(ws,r,"sender")
        for _ in range(31):ws.send_json({"type":"data","payload":payload})
        with pytest.raises(WebSocketDisconnect) as e:ws.receive_json()
        assert e.value.code==4029
