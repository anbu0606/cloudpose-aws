# Bootstrap: the S3 bucket that will hold Terraform's state for the AWS stack.
# Chicken-and-egg: this bucket can't store its OWN state before it exists,
# so this small stack keeps a local state file (git-ignored). Create once, rarely touch.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  # Every resource gets these tags: easy to find, and to see cost per project.
  default_tags {
    tags = {
      Project   = "cloudpose"
      ManagedBy = "terraform"
      Owner     = "anbu"
    }
  }
}

variable "region" {
  type    = string
  default = "ap-southeast-2"
}

# Who am I? Gives the 12-digit account ID, used to make a globally unique bucket name.
data "aws_caller_identity" "me" {}

resource "aws_s3_bucket" "tfstate" {
  bucket = "cloudpose-tfstate-${data.aws_caller_identity.me.account_id}"
}

# Versioning: every state change is kept, so a bad apply can be rolled back.
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Encryption at rest (state files can contain secrets).
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Nobody on the internet can ever read it, even by mistake.
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Refuse any request that isn't over HTTPS (encryption in transit).
resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.tfstate.arn, "${aws_s3_bucket.tfstate.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.tfstate]
}

output "state_bucket" {
  value       = aws_s3_bucket.tfstate.bucket
  description = "Use with: terraform init -backend-config=\"bucket=<this>\""
}
