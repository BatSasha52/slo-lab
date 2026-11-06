import random

import pytest
from fastapi.testclient import TestClient

from slo_app.main import create_app

TOKEN = "test-token"
AUTH = {"Authorization": f"Bearer {TOKEN}"}


class RecordingSleep:
    def __init__(self):
        self.calls = []

    async def __call__(self, seconds):
        self.calls.append(seconds)


@pytest.fixture
def sleeper():
    return RecordingSleep()


@pytest.fixture
def client(sleeper):
    app = create_app(
        admin_token=TOKEN, rng=random.Random(42), sleep=sleeper, base_latency=(0.0, 0.0)
    )
    with TestClient(app) as c:
        yield c


def metric_value(client, line_prefix):
    body = client.get("/metrics").text
    for line in body.splitlines():
        if line.startswith(line_prefix):
            return float(line.rsplit(" ", 1)[1])
    return None


def test_work_ok(client):
    resp = client.get("/work")
    assert resp.status_code == 200
    assert resp.json() == {"result": "ok"}


def test_health_and_ready(client):
    assert client.get("/healthz").status_code == 200
    assert client.get("/readyz").json() == {"status": "ready"}


def test_not_ready_before_startup():
    app = create_app(admin_token=TOKEN)
    # Without the context manager the lifespan never runs.
    resp = TestClient(app).get("/readyz")
    assert resp.status_code == 503


def test_request_counter_labels(client):
    client.get("/work")
    client.get("/work")
    value = metric_value(
        client, 'http_requests_total{code="200",method="GET",route="/work"}'
    )
    assert value == 2.0


def test_latency_histogram_has_slo_bucket(client):
    client.get("/work")
    value = metric_value(
        client, 'http_request_duration_seconds_bucket{le="0.3",method="GET",route="/work"}'
    )
    assert value == 1.0


def test_unknown_paths_share_one_label(client):
    client.get("/does-not-exist-1")
    client.get("/does-not-exist-2")
    value = metric_value(
        client, 'http_requests_total{code="404",method="GET",route="unmatched"}'
    )
    assert value == 2.0


def test_metrics_endpoint_not_counted(client):
    client.get("/metrics")
    client.get("/metrics")
    assert 'route="/metrics"' not in client.get("/metrics").text


def test_admin_requires_token(client):
    assert client.get("/admin/fault").status_code == 401
    bad = {"Authorization": "Bearer wrong"}
    assert client.put("/admin/fault", json={"error_rate": 1}, headers=bad).status_code == 401
    assert client.get("/admin/fault", headers=AUTH).status_code == 200


def test_admin_disabled_without_token():
    app = create_app(admin_token=None)
    with TestClient(app) as c:
        assert c.get("/admin/fault", headers=AUTH).status_code == 503


def test_admin_validates_input(client):
    resp = client.put("/admin/fault", json={"error_rate": 1.5}, headers=AUTH)
    assert resp.status_code == 422
    resp = client.put("/admin/fault", json={"latency_ms": -1}, headers=AUTH)
    assert resp.status_code == 422


def test_error_injection(client):
    client.put("/admin/fault", json={"error_rate": 1.0}, headers=AUTH)
    codes = {client.get("/work").status_code for _ in range(20)}
    assert codes == {500}
    assert metric_value(client, "demo_app_fault_error_rate ") == 1.0
    assert (
        metric_value(client, 'http_requests_total{code="500",method="GET",route="/work"}')
        == 20.0
    )


def test_partial_error_injection(client):
    client.put("/admin/fault", json={"error_rate": 0.5}, headers=AUTH)
    codes = [client.get("/work").status_code for _ in range(400)]
    failures = codes.count(500)
    assert 140 < failures < 260


def test_latency_injection(client, sleeper):
    client.put("/admin/fault", json={"latency_ms": 400}, headers=AUTH)
    client.get("/work")
    assert sleeper.calls[-1] == pytest.approx(0.4)
    assert metric_value(client, "demo_app_fault_added_latency_seconds ") == 0.4


def test_clear_fault(client):
    client.put("/admin/fault", json={"error_rate": 1.0, "latency_ms": 100}, headers=AUTH)
    resp = client.delete("/admin/fault", headers=AUTH)
    assert resp.json() == {"error_rate": 0.0, "latency_ms": 0}
    assert client.get("/work").status_code == 200
    assert metric_value(client, "demo_app_fault_error_rate ") == 0.0
