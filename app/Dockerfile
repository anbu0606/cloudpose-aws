# Python 3.11 (TF 2.13 supports 3.8-3.11). "bookworm" pins the Debian release
# so a base-image refresh can't silently change system packages under us.
FROM python:3.11-slim-bookworm

# No .pyc files, unbuffered logs (so `kubectl logs` shows output immediately)
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    MODEL_PATH=/app/movenet-full-256.tflite

WORKDIR /app

# OpenCV headless only needs glib. (libgl was only needed by the non-headless build.)
RUN apt-get update \
 && apt-get install -y --no-install-recommends libglib2.0-0 \
 && rm -rf /var/lib/apt/lists/*

# Dependencies first: this layer is cached and only rebuilds when requirements change,
# not every time main.py changes.
COPY requirements.txt .
RUN pip install -r requirements.txt

# Non-root user: if the app is ever compromised, the attacker isn't root in the container.
RUN useradd --create-home --uid 10001 appuser

# Model + code last (they change most often). Owned by root, read-only to appuser.
COPY movenet-full-256.tflite model.py main.py ./

USER 10001
EXPOSE 60007

# Docker-level health check (Kubernetes ignores this and uses its own probes).
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:60007/health',timeout=2).status==200 else 1)"

ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "60007"]
