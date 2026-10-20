# Copy to terraform.tfvars (git-ignored).
image_tag   = "0.3.0"
alert_email = ""     # put your email here to receive alarm emails (then confirm the email from AWS)
github_repo = ""     # owner/repo on GitHub, e.g. "anbu/cloudpose-aws" (turns on the CD deploy role)
cd_auth     = "oidc" # or "iam_user" if your account blocks OIDC providers (new AWS sign-up)
