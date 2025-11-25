# VPCのCIDRブロック
vpc_cidr = "10.0.0.0/16"

# 利用可能なアベイラビリティゾーン (例: ap-northeast-1リージョンの場合)
azs = ["ap-northeast-1a", "ap-northeast-1c"]

# パブリックサブネットのCIDRブロックリスト
public_subnets_cidr = ["10.0.1.0/24", "10.0.2.0/24"]

# プライベートサブネットのCIDRブロックリスト
private_subnets_cidr = ["10.0.11.0/24", "10.0.12.0/24"]

# ElastiCacheサブネットのCIDRブロックリスト
elasticache_subnets_cidr = ["10.0.21.0/24", "10.0.22.0/24"]

# NATゲートウェイを有効にするか
enable_nat_gateway = true

# シングルNATゲートウェイを使用するか
single_nat_gateway = true
aws_region = "ap-northeast-1"
project_name = "amplify-hosting"
environment = "dev"
repository_url = "your-repository-url"
repository_branch = "main"
github_access_token = "your-github-access-token"
build_spec = <<-EOT
version: 1
applications:
  - frontend:
      phases:
        preBuild:
          commands:
            - export NODE_OPTIONS=--openssl-legacy-provider
            - yarn install --frozen-lockfile || yarn install
        build:
          commands:
            - yarn build
      artifacts:
        baseDirectory: .next
        files:
          - '**/*'
      cache:
        paths:
          - .next/cache/**/*
          - node_modules/**/*
EOT
framework = null
domain_name = ""
enable_auto_branch_creation = false
auto_branch_creation_patterns = ["feature/*", "dev"]
platform = "WEB_COMPUTE"
stage = "DEVELOPMENT"
enable_basic_auth = false
basic_auth_username = ""
basic_auth_password = ""
environment_variables = {environment = "development"}
enable_notifications = true
notification_email = "your-email@example.com"
custom_rules = []
