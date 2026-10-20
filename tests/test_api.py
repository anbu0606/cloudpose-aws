"""API tests. Run from the repo root:  python -m pytest -q"""
import base64
import os
import sys
from pathlib import Path

import pytest

APP_DIR = Path(__file__).resolve().parents[1] / "app"
sys.path.insert(0, str(APP_DIR))
os.environ.setdefault("MODEL_PATH", str(APP_DIR / "movenet-full-256.tflite"))

from fastapi.testclient import TestClient  # noqa: E402
import main  # noqa: E402

client = TestClient(main.app)
import cv2  # noqa: E402
import numpy as np  # noqa: E402

def _make_sample() -> bytes:
    """A synthetic stick figure, so the repo ships no third-party photos."""
    img = np.full((256, 256, 3), 255, np.uint8)
    cv2.circle(img, (128, 50), 20, (0, 0, 0), 3)                     # head
    for a, b in [((128, 70), (128, 160)), ((128, 90), (80, 130)), ((128, 90), (176, 130)),
                 ((128, 160), (95, 230)), ((128, 160), (161, 230))]:   # body, arms, legs
        cv2.line(img, a, b, (0, 0, 0), 4)
    return cv2.imencode(".jpg", img)[1].tobytes()

SAMPLE_BYTES = _make_sample()

def _payload():
    return {"id": "test-1", "image": base64.b64encode(SAMPLE.read_bytes()).decode()}


def test_health_ok():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_bad_base64_returns_400():
    r = client.post("/pose/json", json={"id": "x", "image": "not-an-image"})
    assert r.status_code == 400


def test_pose_json_returns_17_keypoints():
    r = client.post("/pose/json", json=_payload())
    assert r.status_code == 200
    body = r.json()
    assert body["id"] == "test-1"
    assert len(body["keypoints"][0]) == 17
    assert all(len(kp) == 3 for kp in body["keypoints"][0])


def test_pose_image_returns_jpeg():
    r = client.post("/pose/image", json=_payload())
    assert r.status_code == 200
    jpg = base64.b64decode(r.json()["annotated_image"])
    assert jpg[:2] == b"\xff\xd8"  # JPEG magic bytes


def test_metrics_exposed():
    client.get("/health")
    r = client.get("/metrics")
    assert r.status_code == 200
    assert "cloudpose_http_requests_total" in r.text
    assert 'handler="/health"' in r.text


def test_model_loaded_once_and_reused():
    first = main.MODEL
    client.post("/pose/json", json=_payload())
    client.post("/pose/json", json=_payload())
    assert main.MODEL is first  # same object: no per-request model loading


def test_parallel_requests_all_succeed():
    from concurrent.futures import ThreadPoolExecutor

    with ThreadPoolExecutor(max_workers=16) as pool:
        codes = list(pool.map(lambda _: client.post("/pose/json", json=_payload()).status_code, range(32)))
    assert codes == [200] * 32
