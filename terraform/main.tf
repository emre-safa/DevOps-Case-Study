locals {
  name = "${var.project}-${var.environment}"

  # Pick the first 3 AZs in the region. Three subnets each (public/private)
  # is the standard EKS layout and gives the LB controller room to place ENIs.
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}
