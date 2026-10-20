# Copy to terraform.tfvars (git-ignored) and fill in.
# The Grafana password is NOT here: set it as an env var instead:
#   PowerShell:  $env:TF_VAR_grafana_admin_password = "<pick one>"
kps_chart_version = "<from: helm search repo prometheus-community/kube-prometheus-stack>"
# max_replicas    = 5   # uncomment if your laptop has < 16 GB RAM
