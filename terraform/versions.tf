terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Recommended for any team usage. Replace bucket/table with yours, then
  # `terraform init -migrate-state`. Left commented so a fresh run works
  # without external state infrastructure.
  #
  # backend "s3" {
  #   bucket         = "mern-devops-tfstate"
  #   key            = "case/terraform.tfstate"
  #   region         = "eu-central-1"
  #   dynamodb_table = "mern-devops-tflock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
