# CD = Continuous Deployment: GitHub Actions deploys to AWS after the tests pass.
#
# Problem: GitHub's machines need permission to push to ECR and update ECS.
# Old way: create an IAM user and paste its access keys into GitHub secrets.
#          Those keys never expire; if they leak, anyone can use your account.
# Our way: OIDC (OpenID Connect). For each run, GitHub hands the job a signed
#          "ID card" (a token) saying "I am repo X, branch main". AWS checks the
#          signature, then gives back temporary credentials that expire in about an hour.
#          No long-lived keys are stored anywhere.
#
# Set var.github_repo ("owner/repo") to turn this on. Empty = nothing is created.
#
# var.cd_auth picks HOW GitHub logs in:
#   "oidc"     = the best practice above (needs permission to create an OIDC provider)
#   "iam_user" = fallback for accounts where an AWS-managed SCP blocks OIDC providers
#                (e.g. the new AWS sign-up "project" accounts). A dedicated IAM user
#                with the SAME least-privilege policy; you create its access key
#                yourself and store it only in GitHub Secrets (never in Terraform).

locals {
  cd_enabled = var.github_repo != ""
  cd_oidc    = local.cd_enabled && var.cd_auth == "oidc"
  cd_user    = local.cd_enabled && var.cd_auth == "iam_user"
}

# 1) Tell AWS to trust ID tokens signed by GitHub Actions (one per account).
resource "aws_iam_openid_connect_provider" "github" {
  count          = local.cd_oidc ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"] # the "audience" the token must be issued for
}

# 2) Trust policy: WHO may assume the deploy role.
#    Only tokens from THIS repo's main branch. A fork, another repo, a pull
#    request or another branch is refused even though it also comes from GitHub.
data "aws_iam_policy_document" "github_assume" {
  count = local.cd_oidc ? 1 : 0
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  count                = local.cd_oidc ? 1 : 0
  name                 = "${var.app_name}-github-deploy"
  assume_role_policy   = data.aws_iam_policy_document.github_assume[0].json
  max_session_duration = 3600 # credentials die after 1 hour
}

# 3) Permissions: WHAT the deploy role may do. Only what the pipeline needs.
data "aws_iam_policy_document" "github_deploy" {
  count = local.cd_enabled ? 1 : 0

  # docker login to ECR (this API has no per-repo resource)
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # push images to THIS repository only
  statement {
    sid = "EcrPushThisRepo"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages", # lets a re-run see "this commit's image is already pushed"
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  # read the current task definition and register a new revision
  # (these two ECS APIs do not support per-resource permissions)
  statement {
    sid       = "EcsTaskDefinitions"
    actions   = ["ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"]
    resources = ["*"]
  }

  # roll out the new revision to THIS service only, and watch it
  statement {
    sid       = "EcsDeployThisService"
    actions   = ["ecs:UpdateService", "ecs:DescribeServices"]
    resources = [aws_ecs_service.app.id] # the service ARN
  }

  # a new task definition names the execution + task roles; ECS needs
  # permission to "hand" them over, and only to ECS tasks
  statement {
    sid       = "PassOnlyOurTaskRoles"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.execution.arn, aws_iam_role.task.arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  count  = local.cd_oidc ? 1 : 0
  name   = "deploy-cloudpose"
  role   = aws_iam_role.github_deploy[0].id
  policy = data.aws_iam_policy_document.github_deploy[0].json
}

# ---- Fallback: IAM user (only when var.cd_auth = "iam_user") ----
# Same permissions as the role. No access key here on purpose: a key created by
# Terraform would be saved in the state file. Create it with the CLI instead and
# paste it straight into GitHub Secrets. Rotate or delete it when you're done.
resource "aws_iam_user" "github_deploy" {
  count         = local.cd_user ? 1 : 0
  name          = "${var.app_name}-github-deploy"
  force_destroy = false # destroy also deletes the access key made with the CLI
}

resource "aws_iam_user_policy" "github_deploy" {
  count  = local.cd_user ? 1 : 0
  name   = "deploy-cloudpose"
  user   = aws_iam_user.github_deploy[0].name
  policy = data.aws_iam_policy_document.github_deploy[0].json
}
