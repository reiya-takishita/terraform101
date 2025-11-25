terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}












provider "aws" {
  region = var.aws_region
}

# IAM Role for Amplify
resource "aws_iam_role" "amplify" {
  name = "${var.project_name}-${var.environment}-amplify-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = ["amplify.${var.aws_region}.amazonaws.com", "amplify.amazonaws.com"]
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-amplify-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

# IAM Policy for Amplify (最小権限)
resource "aws_iam_role_policy" "amplify" {
  name = "${var.project_name}-${var.environment}-amplify-policy"
  role = aws_iam_role.amplify.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach managed policy for Amplify Backend
resource "aws_iam_role_policy_attachment" "amplify_backend" {
  role       = aws_iam_role.amplify.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess-Amplify"
}

# Attach AWSAmplifyServiceRolePolicy for build permissions
resource "aws_iam_role_policy_attachment" "amplify_service" {
  role       = aws_iam_role.amplify.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmplifyBackendDeployFullAccess"
}

# VPC、サブネット、NATゲートウェイ、インターネットゲートウェイをプロビジョニング
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0" # モジュールバージョンは適宜最新の安定版を使用してください

  name = "${var.project_name}-${var.environment}-vpc"
  cidr = var.vpc_cidr
  azs  = var.azs

  public_subnets = var.public_subnets_cidr
  private_subnets = var.private_subnets_cidr
  elasticache_subnets = var.elasticache_subnets_cidr

  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-vpc"
    Environment = var.environment
    Project     = var.project_name
  }
}

# ElastiCache for Redisが使用する専用のサブネットグループを作成
resource "aws_elasticache_subnet_group" "redis" {
  name        = "${var.project_name}-${var.environment}-redis-subnet-group"
  subnet_ids  = module.vpc.elasticache_subnets
  description = "ElastiCache subnet group for ${var.project_name}-${var.environment}"

  tags = {
    Name        = "${var.project_name}-${var.environment}-redis-subnet-group"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Amplify App
resource "aws_amplify_app" "main" {
  name       = "${var.project_name}-${var.environment}"
  repository = var.repository_url
  # GitHub access token (required for GitHub repositories)
  access_token = var.github_access_token

  iam_service_role_arn = aws_iam_role.amplify.arn

  # Build spec (null = auto-detection)
  build_spec = var.build_spec
  # Platform (WEB_COMPUTE for SSR support)
  platform = var.platform

  # Environment variables
  environment_variables = var.environment_variables

  # Custom rules
  dynamic "custom_rule" {
    for_each = length(var.custom_rules) > 0 ? var.custom_rules : [
      {
        source    = "/<*>"
        target    = "/index.html"
        status    = "404-200"
        condition = null
      }
    ]
    content {
      source    = custom_rule.value.source
      target    = custom_rule.value.target
      status    = custom_rule.value.status
      condition = custom_rule.value.condition
    }
  }

  # Auto branch creation
  dynamic "auto_branch_creation_config" {
    for_each = var.enable_auto_branch_creation ? [1] : []
    content {
      enable_auto_build             = true
      enable_basic_auth             = var.enable_basic_auth
      basic_auth_credentials        = var.enable_basic_auth ? base64encode("${var.basic_auth_username}:${var.basic_auth_password}") : null
      enable_pull_request_preview   = true
      pull_request_environment_name = "pr"
      framework                     = var.framework
      stage                         = var.stage
    }
  }

  auto_branch_creation_patterns = var.enable_auto_branch_creation ? var.auto_branch_creation_patterns : null

  # Enable auto branch deletion
  enable_branch_auto_deletion = true

  tags = {
    Name        = "${var.project_name}-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Amplify Branch
resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.repository_branch

  framework = var.framework
  stage     = var.stage

  enable_auto_build = true

  # Basic authentication
  enable_basic_auth = var.enable_basic_auth
  basic_auth_credentials = var.enable_basic_auth ? base64encode("${var.basic_auth_username}:${var.basic_auth_password}") : null

  # Environment variables (branch-specific)
  environment_variables = var.environment_variables

  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.repository_branch}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Amplify Domain Association (custom domain)
resource "aws_amplify_domain_association" "main" {
  count       = var.domain_name != "" ? 1 : 0
  app_id      = aws_amplify_app.main.id
  domain_name = var.domain_name

  # Main branch
  sub_domain {
    branch_name = aws_amplify_branch.main.branch_name
    prefix      = ""
  }

  # www subdomain
  sub_domain {
    branch_name = aws_amplify_branch.main.branch_name
    prefix      = "www"
  }
}

# Amplify Webhook (for manual triggers)
resource "aws_amplify_webhook" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = aws_amplify_branch.main.branch_name
  description = "Webhook for ${var.project_name} ${var.environment}"
}

# SNS Topic for notifications
resource "aws_sns_topic" "amplify_notifications" {
  count = var.enable_notifications ? 1 : 0
  name  = "${var.project_name}-${var.environment}-amplify-notifications"

  tags = {
    Name        = "${var.project_name}-${var.environment}-amplify-notifications"
    Environment = var.environment
    Project     = var.project_name
  }
}

# SNS Topic Subscription
resource "aws_sns_topic_subscription" "amplify_notifications" {
  count     = var.enable_notifications && var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.amplify_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# SNS Topic Policy (EventBridgeからの発行を許可)
resource "aws_sns_topic_policy" "amplify_notifications" {
  count  = var.enable_notifications ? 1 : 0
  arn    = aws_sns_topic.amplify_notifications[0].arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.amplify_notifications[0].arn
      }
    ]
  })
}

# EventBridge Rule for Amplify build notifications
resource "aws_cloudwatch_event_rule" "amplify_build" {
  count       = var.enable_notifications ? 1 : 0
  name        = "${var.project_name}-${var.environment}-amplify-build-events"
  description = "Capture Amplify build state changes (start/success/failure only)"

  event_pattern = jsonencode({
    source      = ["aws.amplify"]
    detail-type = ["Amplify Deployment Status Change"]
    detail = {
      appId     = [aws_amplify_app.main.id]
      jobStatus = ["STARTED", "SUCCEED", "FAILED"]
    }
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-amplify-build-events"
    Environment = var.environment
    Project     = var.project_name
  }
}

# EventBridge Target (SNS)
resource "aws_cloudwatch_event_target" "amplify_build_sns" {
  count     = var.enable_notifications ? 1 : 0
  rule      = aws_cloudwatch_event_rule.amplify_build[0].name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.amplify_notifications[0].arn

  input_transformer {
    input_paths = {
      appId      = "$.detail.appId"
      branchName = "$.detail.branchName"
      jobId      = "$.detail.jobId"
      jobStatus  = "$.detail.jobStatus"
    }
    input_template = "\"【Amplify ビルド通知】 ブランチ: <branchName> | ステータス: <jobStatus> | ジョブID: <jobId>\""
  }
}

output "amplify_app_id" {
  description = "Amplify App ID"
  value       = aws_amplify_app.main.id
}

output "amplify_app_arn" {
  description = "Amplify App ARN"
  value       = aws_amplify_app.main.arn
}

output "amplify_default_domain" {
  description = "Amplify default domain"
  value       = aws_amplify_app.main.default_domain
}

output "amplify_branch_url" {
  description = "Amplify branch URL"
  value       = "https://${var.repository_branch}.${aws_amplify_app.main.default_domain}"
}

output "website_url" {
  description = "Website URL"
  value       = var.domain_name != "" ? "https://${var.domain_name}" : "https://${var.repository_branch}.${aws_amplify_app.main.default_domain}"
}

output "amplify_webhook_url" {
  description = "Webhook URL for manual deployments"
  value       = aws_amplify_webhook.main.url
  sensitive   = true
}

output "amplify_console_url" {
  description = "Amplify Console URL"
  value       = "https://console.aws.amazon.com/amplify/home?region=${var.aws_region}#/${aws_amplify_app.main.id}"
}

output "domain_association_status" {
  description = "Domain association status"
  value       = var.domain_name != "" ? aws_amplify_domain_association.main[0].certificate_verification_dns_record : null
}
