# CloudPose: progress log

Every DONE row links to its evidence in `evidence/`.

| Date | Track / step | Status | Evidence |
|---|---|---|---|
| 2026-10-13 | Repo scaffold: `/health`, `/metrics`, sync handlers, pinned deps, non-root Dockerfile, 5 PyTest tests | Code written; tests pass in a Linux sandbox (5 passed). Run on laptop: pending | |
| 2026-10-16 | A0 Tool checks | DONE: Docker Desktop 4.95 (16 CPUs, ~8 GB), kind 0.33, kubectl 1.36, Helm 4.3, Terraform 1.16.5, Python 3.12 | `evidence/a0_tools.txt` |
| 2026-10-16 | A1 3-node kind cluster + metrics-server (Helm CLI) | DONE: 3 nodes Ready, Kubernetes 1.37 | `evidence/a1_nodes.txt` |
| 2026-10-16 | A2 Image built + loaded into kind | DONE: `cloudpose:0.2.0` (456 MB compressed), 5/5 PyTest passed inside image | `evidence/a2_docker_images.txt`, `a2_pytest.txt` |
| 2026-10-16 | A3 `terraform apply` (Deployment, NodePort Service, HPA) | DONE: 3 added (kubernetes provider 2.38.0) | `evidence/a3_apply.txt` |
| 2026-10-16 | A4 kube-prometheus-stack via Terraform `helm_release` + dashboard + alert rules | DONE: 2 added (chart 92.9.0, helm provider 2.17.0); 8/8 cloudpose targets UP; 4 rules loaded | `evidence/a4_apply.txt`, Screenshots |
| 2026-10-17 | A5 Locust load test, HPA scaling, alert firing | DONE: see results below; CloudPoseHPAAtMax fired | `evidence/locust_100u*`, `a5_hpa_watch.txt`, Screenshots |
| 2026-10-17 | A5b Memory fix v0.3.0 (model loaded once + lock), rolling update via Terraform, same test rerun | DONE: 7/7 tests; 0.02% failed (2/8,168), 0 restarts, memory flat ~250-360 MiB, peak 6 pods | `evidence/fix_local_benchmark.txt`, `a5b_*`, `locust_100u_v030*`, Screenshots/v030 |
| 2026-10-18 | B1 S3 state bucket (bootstrap stack) | DONE: 5 added; versioned, encrypted, public access blocked, HTTPS-only | `evidence/b1_bootstrap_apply.txt` |
| 2026-10-18 | B2 ECR repo + image push | DONE: `0.3.0` pushed (immutable tags); scan 7 HIGH / 4 MEDIUM / 2 LOW | `evidence/b2_ecr_images.txt`, `b2_ecr_scan.txt` |
| 2026-10-19 | B3 ECS Fargate + ALB + autoscaling + CloudWatch alarms/dashboard | DONE: 24 added; `/health` ok, 17 keypoints in 139 ms via the ALB | `evidence/b3_apply.txt`, `b3_smoke.txt` |
| 2026-10-19 | B4 Locust through the ALB, 100 users / 8 min | DONE: 9,194 requests, 0 failures, median 430 ms, p95 980 ms; ECS 1 to 3 tasks | `evidence/locust_aws_100u*`, `b4_task_count.txt`, `Screenshots/aws/` |
| 2026-10-19 | B5 GitHub Actions CI/CD to ECS | DONE: run #3 green in 7m14s; live `/health` version = commit SHA | `Screenshots/aws/` (492-498) |
| 2026-10-19 | C1 Pulumi (TypeScript): ECR + secure S3 per env | DONE: 12 resources up, then destroyed | `evidence/c1_pulumi_*.txt`, `Screenshots/pulumi/` |
| 2026-10-19 | C2 AWS CDK (TypeScript): same stack | DONE: synthesised to 11 CloudFormation resources, deployed | `evidence/c2_cdk_template.yaml` |

## Measured results (fill in from real runs only)

| Users | Duration | Requests | Failure % | p50 ms | p95 ms | Replicas min to max | Time to scale out |
|---|---|---|---|---|---|---|---|
| 100 (spawn 2/s) | 8 min | 7,238 (~17 req/s) | 4.3% overall; 31% in first 2 min (296/951); 0.2% after 8 pods ready (14/6,287) | server 189 (Grafana, steady) / Locust 630 overall | server 500 (Grafana, steady) / Locust 7,700 overall | 2 to 8, back to 2 ~6 min after load stopped | ~2 min (2>3>5>8) |
| v0.3.0: 100 (spawn 2/s) | 8 min | 8,168 (~17 req/s) | 0.02% (2), 0 pod restarts | server ~110 (Grafana) / Locust 240 | server ~250 (Grafana) / Locust 2,300 (client-side ~2 s Windows delay in both runs) | 2 to 6 (never hit max) | ~1 min (2>3>5, later 6) |

## Notes / issues hit (great interview stories)
- Failures were connection drops (`RemoteDisconnected`), not 5xx (5xx panel: no data). Pod memory hit the 1 GiB limit at 00:45-00:47 and pods restarted: likely OOMKilled. Cause: `pose_detection.predict` builds a new TFLite interpreter per request and sync handlers run up to 40 requests concurrently per pod. Confirmation pending (`a5_restarts.txt`).
- Trade-off: `async def` -> `def` kept `/health` responsive but raised per-pod concurrency, making memory the next bottleneck.
- Fix backlog: load model once at startup (+lock), cap concurrency per pod (uvicorn `--limit-concurrency`), `min_replicas = 3`; rerun same test for before/after.
- Locust p95 (7.7 s) includes queueing during warm-up; Grafana p95 (0.5 s) is in-app, steady state.

- v0.3.0 fix confirmed: local benchmark (40 concurrent) peak RSS 1,675 MB -> 502 MB, 10.6 -> 20.9 req/s; cluster rerun 4.3% -> 0.02% failures, 0 restarts, 8 -> 6 peak pods.
