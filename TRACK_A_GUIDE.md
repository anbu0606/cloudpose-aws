# Track A guide: local Kubernetes + Terraform + Helm + Prometheus/Grafana

Run every command in **PowerShell** from the repo root unless a step says otherwise:
```powershell
cd "C:\Users\anbua\Downloads\Job search antigravity\cloudpose-aws"
```
In PowerShell use `curl.exe` (plain `curl` is an alias for Invoke-WebRequest).
After each step, paste the output back into the chat, and tick off the **Explain** list out loud.

Time budget: A0 30 min, A1 20 min, A2 30 min (image build is slow), A3 30 min, A4 30 min, A5 60 min.

---

## A0. Tool checks
```powershell
docker version
docker info --format "{{.NCPU}} CPUs / {{.MemTotal}} bytes RAM for Docker"
kind version
kubectl version --client
helm version
terraform version
python --version
```
Missing anything? Install with winget, then **open a new PowerShell window** so PATH refreshes:
```powershell
winget install -e --id Docker.DockerDesktop     # then start Docker Desktop, WSL2 backend
winget install -e --id Kubernetes.kind
winget install -e --id Kubernetes.kubectl
winget install -e --id Helm.Helm
winget install -e --id Hashicorp.Terraform      # want >= 1.10 (Track B uses S3 native locking)
python -m pip install locust                    # load generator, any Python 3.9+
```
Docker needs **at least 8 GB RAM** for this track (3 nodes + up to 8 TensorFlow pods at ~420 MB + monitoring). If `docker info` shows less, either raise it (WSL2: `%UserProfile%\.wslconfig`, `memory=10GB`, then `wsl --shutdown`) or set `max_replicas = 5`.

**Explain:** Docker Desktop runs Linux containers inside a WSL2 VM. kind = Kubernetes nodes as Docker containers. kubectl = the K8s API client. Helm = package manager for K8s (charts = templated YAML + values). Terraform = declarative IaC with a plan/apply cycle and a state file.

---

## A1. Create the 3-node cluster + metrics-server (Helm CLI)
```powershell
kind create cluster --config k8s/kind-config.yaml
kubectl config current-context            # expect: kind-cloudpose
kubectl get nodes -o wide | Tee-Object evidence\a1_nodes.txt
docker ps --format "table {{.Names}}\t{{.Ports}}"   # the 3 "nodes" are just containers

helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install metrics-server metrics-server/metrics-server -n kube-system --set "args={--kubelet-insecure-tls}"
kubectl -n kube-system rollout status deploy/metrics-server
kubectl top nodes                         # may take ~60 s before numbers appear
helm list -A
```
Why `--kubelet-insecure-tls`: kind's kubelets use self-signed certs, so metrics-server can't verify them. Fine locally, **never in production**.

**Explain:**
- Control plane (API server, etcd, scheduler, controller-manager) vs worker nodes (kubelet, kube-proxy, container runtime).
- metrics-server collects CPU/memory from each kubelet; the HPA and `kubectl top` read it. No metrics-server = HPA shows `<unknown>` and never scales.
- `helm upgrade --install` is idempotent: installs if missing, upgrades if present (same idea as `terraform apply`).
- `--set` overrides a chart value; `helm get values metrics-server -n kube-system` shows what you overrode.

---

## A2. Build, test and load the image
```powershell
# the model and test images are already in the repo
docker build -t cloudpose:0.2.0 --build-arg APP_VERSION=0.2.0 app
docker images cloudpose | Tee-Object evidence\a2_docker_images.txt

# run it locally once
docker run -d --name cp -p 60007:60007 cloudpose:0.2.0
Start-Sleep 10; curl.exe http://localhost:60007/health
docker exec cp whoami                     # expect: appuser (non-root)
docker inspect --format "{{.State.Health.Status}}" cp   # healthy after ~30 s

# run the PyTest suite inside the image (no local TensorFlow install needed)
docker run --rm -v "${PWD}:/src" -w /src cloudpose:0.2.0 sh -c "pip install -q --user pytest==8.3.3 httpx==0.27.2 && python -m pytest -q" | Tee-Object evidence\a2_pytest.txt
docker rm -f cp

# copy the image into every kind node (kind nodes can't see Docker Desktop's images)
kind load docker-image cloudpose:0.2.0 --name cloudpose
docker exec cloudpose-worker crictl images | findstr cloudpose
```
**Explain:**
- Layer caching: requirements are copied and installed *before* code, so editing `main.py` rebuilds in seconds.
- Non-root user (uid 10001): limits damage if the app is compromised; K8s also enforces `run_as_non_root`.
- Pinned versions: reproducible builds. TF 2.13 forces numpy < 1.25 and Pydantic 1.x.
- Tag `0.2.0`, not `latest`: you know exactly what's running and can roll back. (`latest` also makes K8s default to `imagePullPolicy: Always`, which would fail here.)
- **The `async def` -> `def` fix**: inference blocks the CPU. Inside `async def` it froze the event loop, so `/health` couldn't answer during a request: under load that makes liveness probes fail and pods restart. A plausible cause of the "pod restarts under load" in the original report.

---

## A3. Terraform: Deployment + Service + HPA (first real apply)
```powershell
cd infra\k8s
helm search repo prometheus-community/kube-prometheus-stack    # note CHART VERSION
Copy-Item example.tfvars terraform.tfvars                       # edit: put that version in
$env:TF_VAR_grafana_admin_password = "<pick a password>"        # env var, never in a file

terraform init                   # downloads kubernetes + helm providers, writes .terraform.lock.hcl
terraform fmt -recursive          # auto-formats; lists any file it changed
terraform validate
terraform plan                    # read it: what will be created?

# Stage 1: only the app (monitoring comes in A4)
terraform apply -target="kubernetes_deployment.cloudpose" -target="kubernetes_service.cloudpose" -target="kubernetes_horizontal_pod_autoscaler_v2.cloudpose_hpa" | Tee-Object ..\..\evidence\a3_apply.txt
cd ..\..

kubectl get deploy,pods,svc,hpa -o wide
kubectl get pods -o wide          # pods spread across cloudpose-worker and cloudpose-worker2?
python load/smoke.py              # /health + one real pose request through the NodePort

# Prove the lifecycle rule: change replicas behind Terraform's back
kubectl scale deploy cloudpose-deployment --replicas=4
cd infra\k8s; terraform plan      # expect: no changes to replicas
cd ..\..
```
`-target` is for staged rollouts and emergencies only; normal practice is a plain `apply` of the whole config. We use it to learn one layer at a time.

**Explain:**
- `init` / `plan` / `apply`; the state file (`terraform.tfstate`) maps code to real objects. Why it's git-ignored (can hold secrets) and why Track B moves it to S3 with locking.
- Providers pinned (`~> 2.30`) + lock file = same provider build everywhere.
- `requests` vs `limits`; HPA % is measured against **requests** (70% of 500m = 350m per pod).
- Readiness vs liveness probes (traffic removal vs restart).
- `ignore_changes = [spec[0].replicas]`: Terraform owns the spec, HPA owns the count. Without it each apply fights the autoscaler.
- NodePort path: localhost:30006 -> kind port mapping -> node -> kube-proxy -> pod :60007.

---

## A4. Prometheus + Grafana + Alertmanager via Terraform's Helm provider
```powershell
cd infra\k8s
terraform plan                    # expect: helm_release + config map to add
terraform apply | Tee-Object ..\..\evidence\a4_apply.txt
cd ..\..
kubectl get pods -n monitoring
helm list -A                      # the release Terraform created shows up in Helm too
kubectl get prometheusrules -n monitoring
```
Open the UIs (each port-forward in its **own** PowerShell window; it runs until Ctrl+C):
```powershell
kubectl -n monitoring port-forward svc/kps-grafana 3000:80          # http://localhost:3000  admin / your password
kubectl -n monitoring port-forward svc/kps-prometheus 9090:9090     # http://localhost:9090
kubectl -n monitoring port-forward svc/kps-alertmanager 9093:9093   # http://localhost:9093
```
Check: Prometheus **Status -> Targets**: job `cloudpose` has your pods UP. **Alerts** tab: 4 CloudPose rules (green/inactive). Grafana **Dashboards -> CloudPose - load & autoscaling**.

**Explain:**
- Pull model: Prometheus *scrapes* `/metrics` every 15 s. Counter vs histogram; why p95 comes from `histogram_quantile` over buckets.
- Where each panel's data comes from: CPU/memory = cAdvisor (kubelet), replicas = kube-state-metrics, requests/latency = your app's `/metrics`.
- Prometheus Operator + CRDs (Prometheus, PrometheusRule, ServiceMonitor). We used `additionalScrapeConfigs` because a ServiceMonitor can't be planned before its CRD exists in the same apply (chicken-and-egg).
- Alert lifecycle: inactive -> pending (condition true, waiting out `for`) -> firing -> Alertmanager (grouping, routing, silences).
- Dashboards as code: a ConfigMap with label `grafana_dashboard=1`, picked up by Grafana's sidecar.
- Why Helm via Terraform: one tool, one state, one `destroy`; versions pinned in code.

---

## A5. Load test, watch the HPA, capture evidence
Window 1 (HPA watch):
```powershell
kubectl get hpa cloudpose-hpa -w | Tee-Object evidence\a5_hpa_watch.txt
```
Window 2: Grafana port-forward (A4). Window 3 (load):
```powershell
locust -f load/locustfile.py --host http://localhost:30006 --headless -u 100 -r 2 -t 8m --html evidence/locust_100u.html --csv evidence/locust_100u
```
While it runs: `kubectl top pods`, `kubectl get pods -o wide`, `kubectl describe hpa cloudpose-hpa` (Events show each rescale and why).
Screenshots into `evidence/`: Grafana dashboard at peak; Prometheus Alerts (pending/firing); Alertmanager. After load stops, keep watching ~6 min to see the 300 s scale-down window.
Then fill the **Measured results** table in `PROGRESS.md` from `locust_100u.html` (requests, failure %, p50, p95) and the HPA watch (min to max replicas, time to scale out).
Optional second run with `-u 200` to find where failures start.

**Explain:**
- Why scale-up is fast (0 s window, +100%/15 s) but scale-down slow (300 s window): avoid flapping.
- Little's law intuition: users ÷ think-time ≈ request rate; each pod handles roughly X req/s at 1 CPU.
- Failure % is the honest replacement for ">99% uptime".
- What you'd tune next (CPU request size, model loaded once instead of per request, more workers).

---

## End of session
```powershell
cd infra\k8s; terraform destroy; cd ..\..   # practise destroy (removes app + monitoring)
kind delete cluster --name cloudpose         # removes the whole cluster (free; it's local)
```
Locally there's no cost, so you can also keep the cluster between afternoons and just quit Docker Desktop.

## Interview one-liners (only once each step is done)
- "I stood up a 3-node kind cluster and deployed CloudPose with Terraform: Deployment, NodePort Service and an autoscaling/v2 HPA, using `ignore_changes` on replicas so applies don't fight the autoscaler."
- "I installed kube-prometheus-stack through Terraform's Helm provider, scraped the app's own Prometheus metrics, and shipped a Grafana dashboard and alert rules as code."
- "Under a Locust load of N users the HPA scaled from 2 to M pods in ~T s with F% failed requests and p95 of P ms." (real numbers only)
