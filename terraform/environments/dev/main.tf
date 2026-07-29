terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend S3 — state partagé entre local et CI/CD
  # Le bucket est versionné pour permettre la récupération en cas de corruption
  backend "s3" {
    bucket = "smart-assembly-tfstate-169237360990"
    key    = "environments/dev/terraform.tfstate"
    region = "eu-west-3"
  }
}


provider "aws" {
  region = "eu-west-3"
}