/*
 * AWS settings
 */
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.4.0"
    }
  }
  required_version = ">= 1.1.6"
  cloud {
    organization = "akaritakai"
    workspaces {
      name = "github-terraform"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}