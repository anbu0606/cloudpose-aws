"""Locust load test for CloudPose.

Headless run (from the repo root):
  locust -f load/locustfile.py --host http://localhost:30006 --headless \
         -u 100 -r 2 -t 8m --html evidence/locust_100u.html --csv evidence/locust_100u
"""
import base64
import glob
import json
import os
import uuid

from locust import HttpUser, between, task

IMAGE_FOLDER = os.getenv("CLOUDPOSE_IMAGES", os.path.join(os.path.dirname(__file__), "images"))
IMAGES = sorted(glob.glob(os.path.join(IMAGE_FOLDER, "*.jpg")))
if not IMAGES:
    raise FileNotFoundError(f"No .jpg images found in {IMAGE_FOLDER}")

# Encode once at start-up so the load generator spends CPU on sending, not base64.
PAYLOADS = [base64.b64encode(open(p, "rb").read()).decode() for p in IMAGES]
HEADERS = {"Content-Type": "application/json"}


class PoseEstimationUser(HttpUser):
    wait_time = between(1, 8)  # same think-time as the original load test

    def on_start(self):
        self.i = 0

    def _body(self):
        img = PAYLOADS[self.i]
        self.i = (self.i + 1) % len(PAYLOADS)
        return json.dumps({"id": str(uuid.uuid4()), "image": img})

    @task
    def pose_json(self):
        self.client.post("/pose/json", data=self._body(), headers=HEADERS)

    @task
    def pose_image(self):
        self.client.post("/pose/image", data=self._body(), headers=HEADERS)
