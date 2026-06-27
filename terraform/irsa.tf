locals {
  oidc_provider_url = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
}

# ALB Ingress Controller

resource "aws_iam_policy" "alb_controller" {
  name   = "project-bedrock-alb-controller-policy"
  policy = file("${path.module}/../kubernetes/alb-controller/iam_policy.json")
}

resource "aws_iam_role" "alb_controller" {
  name = "project-bedrock-alb-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = module.eks.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_url}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  policy_arn = aws_iam_policy.alb_controller.arn
  role       = aws_iam_role.alb_controller.name
}

# External Secrets Operator

resource "aws_iam_policy" "external_secrets" {
  name   = "project-bedrock-external-secrets-policy"
  policy = file("${path.module}/../kubernetes/manifests/secrets/external-secrets-policy.json")
}

resource "aws_iam_role" "external_secrets" {
  name = "project-bedrock-external-secrets-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = module.eks.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_url}:sub" = "system:serviceaccount:retail-app:external-secrets-sa"
          "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "external_secrets" {
  policy_arn = aws_iam_policy.external_secrets.arn
  role       = aws_iam_role.external_secrets.name
}

# Carts (DynamoDB access)

resource "aws_iam_policy" "carts_dynamodb" {
  name = "project-bedrock-carts-dynamodb-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query",
        "dynamodb:Scan"
      ]
      Resource = aws_dynamodb_table.products.arn
    }]
  })
}

resource "aws_iam_role" "carts" {
  name = "project-bedrock-carts-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = module.eks.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_url}:sub" = "system:serviceaccount:retail-app:carts-sa"
          "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "carts" {
  policy_arn = aws_iam_policy.carts_dynamodb.arn
  role       = aws_iam_role.carts.name
}
