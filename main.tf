terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.59.0"
    }
  }
}
variable "aws_region" {
  type = string
}
variable "tag_name" {
  type = string
}
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Name = var.tag_name
    }
  }
}
