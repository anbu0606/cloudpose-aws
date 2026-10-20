"""CloudPose API: MoveNet pose estimation behind FastAPI.

Changes from the original version of this service:
- GET /health for Kubernetes liveness/readiness probes (and later the AWS ALB).
- GET /metrics in Prometheus format (request count + latency histogram).
- Pose endpoints are plain `def`, not `async def`. Inference is CPU-bound and
  blocking; inside `async def` it froze the event loop, so even /health could
  not answer while a request was being processed. With `def`, FastAPI runs the
  handler in a worker thread and the event loop stays free.
- v0.3.0: the model is loaded ONCE at startup (app/model.py) instead of once
  per request. Inference runs straight from memory (no temp files), one at a
  time per pod. /health is async so it never waits behind queued inferences.
"""
import base64
import os
import time

import cv2
import numpy as np
from fastapi import FastAPI, HTTPException, Request
from prometheus_client import Counter, Histogram, make_asgi_app
from pydantic import BaseModel

from model import PoseModel  # same maths as the original reference implementation

MODEL_PATH = os.getenv("MODEL_PATH", "movenet-full-256.tflite")
APP_VERSION = os.getenv("APP_VERSION", "dev")

app = FastAPI(title="CloudPose", version=APP_VERSION)
MODEL = PoseModel(MODEL_PATH)  # loaded once per process, shared by all requests

# ---------------------------------------------------------------- metrics
REQUESTS = Counter(
    "cloudpose_http_requests_total",
    "HTTP requests handled",
    ["method", "handler", "status"],
)
LATENCY = Histogram(
    "cloudpose_http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "handler"],
    buckets=(0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10),
)
app.mount("/metrics", make_asgi_app())


@app.middleware("http")
async def record_metrics(request: Request, call_next):
    if request.url.path.startswith("/metrics"):
        return await call_next(request)
    start = time.perf_counter()
    status = 500
    try:
        response = await call_next(request)
        status = response.status_code
        return response
    finally:
        # Use the route template (e.g. /pose/json), never the raw URL,
        # so a scanner hitting random paths can't explode label cardinality.
        route = request.scope.get("route")
        handler = getattr(route, "path", "unmatched")
        LATENCY.labels(request.method, handler).observe(time.perf_counter() - start)
        REQUESTS.labels(request.method, handler, str(status)).inc()


# ---------------------------------------------------------------- API
class ImageReq(BaseModel):
    id: str     # unique request id
    image: str  # base64-encoded image


@app.get("/health")
async def health():
    """Cheap liveness/readiness check: process is up and the model file exists."""
    if not os.path.exists(MODEL_PATH):
        raise HTTPException(status_code=503, detail="model file missing")
    return {"status": "ok", "version": APP_VERSION}


def _decode(b64: str):
    try:
        img = cv2.imdecode(np.frombuffer(base64.b64decode(b64), np.uint8), cv2.IMREAD_COLOR)
    except Exception:
        img = None
    if img is None:
        raise HTTPException(status_code=400, detail="Image decoding failed.")
    return img


def _run_model(img):
    """Run MoveNet from memory and return (keypoints, annotated jpg bytes)."""
    keypoints = MODEL.infer(img)
    ok, jpg = cv2.imencode(".jpg", PoseModel.annotate(img, keypoints))
    if not ok:
        raise RuntimeError("could not encode annotated image")
    return keypoints, jpg.tobytes()


@app.post("/pose/json")
def pose_estimation_json(req: ImageReq):
    t0 = time.time()
    img = _decode(req.image)
    t1 = time.time()
    try:
        keypoints, _ = _run_model(img)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    t2 = time.time()

    h, w = img.shape[:2]
    keypoints_out = [[int(x * w), int(y * h), round(float(c), 3)] for y, x, c in keypoints[0]]
    return {
        "id": req.id,
        "count": 1,
        "boxes": [{"x": 0, "y": 0, "width": w, "height": h, "probability": 1.0}],
        "keypoints": [keypoints_out],
        "speed_preprocess": round(t1 - t0, 4),
        "speed_inference": round(t2 - t1, 4),
        "speed_postprocess": 0.0,
    }


@app.post("/pose/image")
def pose_estimation_image(req: ImageReq):
    img = _decode(req.image)
    try:
        _, annotated = _run_model(img)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    return {"id": req.id, "annotated_image": base64.b64encode(annotated).decode("utf-8")}
