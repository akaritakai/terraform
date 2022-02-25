terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.2.0"
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