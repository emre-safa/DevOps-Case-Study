# GitHub Actions OIDC integration. Creates the OIDC provider in this AWS
# account, plus a role that the deploy workflow assumes via web identity.
# Trust is locked to one repo so a different repo cannot assume the role
# even if it learns the ARN.
#
# If the OIDC provider already exists in this account (only one per
# account is allowed for `token.actions.githubusercontent.com`), import
# it before the next apply:
#   terraform import aws_iam_openid_connect_provider.github \
#     arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com

# Fetch the live thumbprint at plan time — more resilient than hardcoding.
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
  tags            = local.tags
}

# Role assumed by the Deploy workflow.
resource "aws_iam_role" "github_deploy" {
  name = "${local.name}-github-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        # Locks the role to a single repo. To restrict further to one
        # branch, use "repo:OWNER/REPO:ref:refs/heads/main" instead.
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
        }
      }
    }]
  })

  tags = local.tags
}

# Permission 1: push/pull images to ECR.
resource "aws_iam_role_policy_attachment" "github_ecr" {
  role       = aws_iam_role.github_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

# Permission 2: minimum EKS read needed for `aws eks update-kubeconfig`.
resource "aws_iam_policy" "github_eks_describe" {
  name = "${local.name}-github-eks-describe"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["eks:DescribeCluster", "eks:ListClusters"]
      Resource = "*"
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "github_eks_describe" {
  role       = aws_iam_role.github_deploy.name
  policy_arn = aws_iam_policy.github_eks_describe.arn
}

# Permission 3: cluster-admin via the EKS Access Entries API (the modern
# replacement for the aws-auth ConfigMap). The cluster was created with
# `enable_cluster_creator_admin_permissions = true`, which selects this
# auth mode — so we use the same mechanism here.
resource "aws_eks_access_entry" "github_deploy" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.github_deploy.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "github_deploy_admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.github_deploy.arn
  # NB: EKS Access Policies are a separate namespace from IAM policies.
  # Correct ARN prefix is `arn:aws:eks::aws:cluster-access-policy/...`,
  # NOT `arn:aws:iam::aws:policy/...`.
  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.github_deploy]
}
