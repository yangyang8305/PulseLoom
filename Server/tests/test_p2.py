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
