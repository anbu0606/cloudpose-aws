"""One-shot smoke test (stdlib only):  python load/smoke.py [base_url]"""
import base64
import glob
import json
import os
import sys
import time
import urllib.request

base = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:30006"
img = sorted(glob.glob(os.path.join(os.path.dirname(__file__), "images", "*.jpg")))[0]

print("GET /health ->", urllib.request.urlopen(f"{base}/health", timeout=5).read().decode())

body = json.dumps({"id": "smoke", "image": base64.b64encode(open(img, "rb").read()).decode()}).encode()
req = urllib.request.Request(f"{base}/pose/json", body, {"Content-Type": "application/json"})
t = time.time()
resp = json.loads(urllib.request.urlopen(req, timeout=30).read())
print(f"POST /pose/json -> {len(resp['keypoints'][0])} keypoints in {1000 * (time.time() - t):.0f} ms")
