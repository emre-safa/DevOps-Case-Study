module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = "${local.name}-eks"
  cluster_version = var.kubernetes_version

  # Public endpoint for kubectl + OIDC for IRSA. Lock public access down
  # in real environments via cluster_endpoint_public_access_cidrs.
  cluster_endpoint_public_access = true
  enable_irsa                    = true

  # Stream control-plane logs to CloudWatch (api/audit/auth/etc.).
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Required cluster add-ons. CoreDNS and kube-proxy ship by default; we
  # also ask EKS to manage the VPC CNI and EBS CSI (the latter is needed
  # for MongoDB's PVC).
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets    # workers in private subnets

  eks_managed_node_group_defaults = {
    ami_type       = "AL2_x86_64"
    instance_types = var.node_instance_types
  }

  eks_managed_node_groups = {
    default = {
      desired_size   = var.node_desired_size
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"
      labels = {
        "workload" = "general"
      }
    }
  }

  # The IAM identity that runs Terraform is auto-mapped to system:masters
  # so `aws eks update-kubeconfig` works straight after apply.
  enable_cluster_creator_admin_permissions = true

  tags = local.tags
}

# IRSA role for the EBS CSI driver — needed because the MongoDB StatefulSet
# requests a PersistentVolumeClaim backed by gp3.
module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"

  role_name             = "${local.name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}

# IRSA role for the AWS Load Balancer Controller — manages the ALB
# created by the Ingress resource.
module "alb_controller_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"

  role_name                              = "${local.name}-alb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = local.tags
}

# IRSA role for Fluent Bit — ships container logs to CloudWatch.
module "fluentbit_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"

  role_name = "${local.name}-fluentbit"

  role_policy_arns = {
    cw = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["amazon-cloudwatch:fluent-bit"]
    }
  }

  tags = local.tags
}
