"""Demo HTTP service that the SLOs in this repository are defined against."""

import asyncio
import hmac
import os
import random
import time
from contextlib import asynccontextmanager
from typing import Awaitable, Callable, Optional

from fastapi import FastAPI, Header, HTTPException, Request, Response
from fastapi.responses import JSONResponse
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    CollectorRegistry,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
)
from pydantic import BaseModel, Field

VERSION = "0.1.0"

# 0.3 must stay a bucket boundary: the latency SLI reads the le="0.3" bucket directly.
LATENCY_BUCKETS = (0.025, 0.05, 0.1, 0.2, 0.3, 0.5, 1.0, 2.5, 5.0)

SleepFn = Callable[[float], Awaitable[None]]


class FaultConfig(BaseModel):
    error_rate: float = Field(0.0, ge=0.0, le=1.0)
    latency_ms: int = Field(0, ge=0, le=10_000)


class Metrics:
    def __init__(self, registry: CollectorRegistry):
        self.requests = Counter(
            "http_requests_total",
            "HTTP requests handled, by route template, method and status code.",
            ["route", "method", "code"],
            registry=registry,
        )
        self.duration = Histogram(
            "http_request_duration_seconds",
            "HTTP request duration in seconds, by route template and method.",
            ["route", "method"],
            buckets=LATENCY_BUCKETS,
            registry=registry,
        )
        self.fault_error_rate = Gauge(
            "demo_app_fault_error_rate",
            "Currently injected probability of returning HTTP 500 on /work.",
            registry=registry,
        )
        self.fault_latency = Gauge(
            "demo_app_fault_added_latency_seconds",
            "Currently injected extra latency on /work.",
            registry=registry,
        )
        info = Gauge(
            "demo_app_build_info",
            "Constant 1, labelled with the running version.",
            ["version"],
            registry=registry,
        )
        info.labels(version=VERSION).set(1)

    def set_fault(self, fault: FaultConfig) -> None:
        self.fault_error_rate.set(fault.error_rate)
        self.fault_latency.set(fault.latency_ms / 1000)


def create_app(
    admin_token: Optional[str] = None,
    rng: Optional[random.Random] = None,
    sleep: SleepFn = asyncio.sleep,
    base_latency: tuple[float, float] = (0.010, 0.060),
) -> FastAPI:
    rng = rng or random.Random()
    registry = CollectorRegistry()
    metrics = Metrics(registry)
    state = {"ready": False, "fault": FaultConfig()}

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        state["ready"] = True
        yield
        state["ready"] = False

    app = FastAPI(title="slo-lab demo service", version=VERSION, lifespan=lifespan)

    @app.middleware("http")
    async def record_metrics(request: Request, call_next):
        if request.url.path == "/metrics":
            return await call_next(request)
        start = time.perf_counter()
        code = 500
        try:
            response = await call_next(request)
            code = response.status_code
            return response
        finally:
            # Label by route template, never the raw path, so unknown URLs
            # cannot create unbounded label values.
            route = request.scope.get("route")
            route_label = route.path if route is not None else "unmatched"
            metrics.requests.labels(route_label, request.method, str(code)).inc()
            metrics.duration.labels(route_label, request.method).observe(
                time.perf_counter() - start
            )

    def require_admin(authorization: Optional[str]) -> None:
        if not admin_token:
            raise HTTPException(status_code=503, detail="admin endpoint disabled")
        expected = f"Bearer {admin_token}"
        if authorization is None or not hmac.compare_digest(
            authorization.encode(), expected.encode()
        ):
            raise HTTPException(status_code=401, detail="unauthorized")

    @app.get("/work")
    async def work():
        fault: FaultConfig = state["fault"]
        await sleep(rng.uniform(*base_latency) + fault.latency_ms / 1000)
        if fault.error_rate > 0 and rng.random() < fault.error_rate:
            return JSONResponse({"error": "injected failure"}, status_code=500)
        return {"result": "ok"}

    @app.get("/healthz")
    async def healthz():
        return {"status": "ok"}

    @app.get("/readyz")
    async def readyz():
        if not state["ready"]:
            return JSONResponse({"status": "starting"}, status_code=503)
        return {"status": "ready"}

    @app.get("/metrics")
    async def metrics_endpoint():
        return Response(generate_latest(registry), media_type=CONTENT_TYPE_LATEST)

    @app.get("/admin/fault")
    async def get_fault(authorization: Optional[str] = Header(None)):
        require_admin(authorization)
        return state["fault"]

    @app.put("/admin/fault")
    async def set_fault(fault: FaultConfig, authorization: Optional[str] = Header(None)):
        require_admin(authorization)
        state["fault"] = fault
        metrics.set_fault(fault)
        return fault

    @app.delete("/admin/fault")
    async def clear_fault(authorization: Optional[str] = Header(None)):
        require_admin(authorization)
        state["fault"] = FaultConfig()
        metrics.set_fault(state["fault"])
        return state["fault"]

    return app


app = create_app(admin_token=os.environ.get("ADMIN_TOKEN"))
