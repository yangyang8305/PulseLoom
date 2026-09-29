import asyncio
from collections import deque
from fastapi import HTTPException
from Server.app import Registry


def test_aud21_capacity_recovers_after_creation_window_expires():
    clock = [0.0]
    registry = Registry(lambda: clock[0])
    registry.creation.update({f"ip-{i}": deque([0.0]) for i in range(5000)})
    clock[0] = 61.0
    response = registry.create("new-ip")
    assert response["room"] in registry.rooms
    assert len(registry.creation) == 1


def test_aud21_periodic_sweep_removes_idle_ip_metadata():
    clock = [0.0]
    registry = Registry(lambda: clock[0])
    registry.creation["cold-ip"] = deque([0.0])
    clock[0] = 61.0
    asyncio.run(registry.sweep())
    assert "cold-ip" not in registry.creation


def test_aud21_active_limiter_is_not_evicted_at_capacity():
    import pytest
    registry = Registry(lambda: 30.0)
    registry.creation.update({f"ip-{i}": deque([0.0] * 6) for i in range(5000)})
    with pytest.raises(HTTPException) as full:
        registry.create("new-ip")
    assert full.value.status_code == 503
    with pytest.raises(HTTPException) as limited:
        registry.create("ip-1")
    assert limited.value.status_code == 429
    assert len(registry.creation) == 5000


def test_aud21_sweep_keeps_recent_requests_and_expires_boundary():
    clock = [60.0]
    registry = Registry(lambda: clock[0])
    registry.creation["active"] = deque([0.0, 59.0])
    registry.creation["expired"] = deque([0.0])
    asyncio.run(registry.sweep())
    assert registry.creation == {"active": deque([59.0])}
