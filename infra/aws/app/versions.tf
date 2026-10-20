terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Remote state in the bootstrap bucket. Backend blocks can't use variables,
  # so the bucket name is passed at init time ("partial configuration"):
  #   terraform init -backend-config="bucket=cloudpose-tfstate-<account-id>"
  # use_lockfile = S3-native state locking (Terraform 1.10+): a .tflock object
  # stops two applies running at once. (Older setups used a DynamoDB table.)
  backend "s3" {
    key          = "cloudpose/aws/terraform.tfstate"
    region       = "ap-southeast-2"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "cloudpose"
      ManagedBy = "terraform"
      Owner     = "anbu"
    }
  }
}
