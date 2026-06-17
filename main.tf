# VPC
# resource "aws_vpc" "main" {
#   cidr_block = "10.0.0.0/16"

#   tags = {
#     Name = "dorin-vpc"
#   }
# }

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "dorin-vpc"
  cidr = "10.0.0.0/16"

  azs            = ["us-east-1a", "us-east-1b"]
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24"]

  enable_nat_gateway = false
  enable_vpn_gateway = false

  tags = {
    Name = "dorin-vpc"
  }
}

# Subnet public
# resource "aws_subnet" "public" {
#   vpc_id            = module.vpc.vpc_id
#   cidr_block        = "10.0.1.0/24"
#   availability_zone = "${var.region}a"

#   tags = {
#     Name = "dorin-public-subnet"
#   }
# }

# Gateway
# resource "aws_internet_gateway" "main" {
#   vpc_id = module.vpc.vpc_id

#   tags = {
#     Name = "dorin-igw"
#   }
# }

# Route Table
# resource "aws_route_table" "public" {
#   vpc_id = module.vpc.vpc_id

#   route {
#     cidr_block = "0.0.0.0/0"
#     gateway_id = aws_internet_gateway.main.id
#   }

#   tags = {
#     Name = "dorin-public-rt"
#   }
# }

# # Asociere Route Table cu Subnet
# resource "aws_route_table_association" "public" {
#   subnet_id      = module.vpc.public_subnets[0]
#   route_table_id = aws_route_table.public.id
# }

# Security Group
resource "aws_security_group" "ec2" {
  name        = "dorin-ec2-sg"
  description = "Security group for EC2 web server"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from github"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Ghostfolio App"
    from_port   = 3333
    to_port     = 3333
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "dorin-ec2-sg"
  }
}

# Key
resource "aws_key_pair" "main" {
  key_name   = "dorin-key"
  public_key = var.ec2_public_key
}

# EC2
resource "aws_instance" "main" {
  ami                         = "ami-091138d0f0d41ff90"
  instance_type               = "t2.micro"
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  key_name                    = aws_key_pair.main.key_name
  user_data_replace_on_change = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name

  user_data = templatefile("install.sh", {
    redis_host     = aws_elasticache_replication_group.redis.primary_endpoint_address
    redis_password = var.redis_password
    db_host        = aws_db_instance.postgres.address
    db_password    = var.db_password
  })

  tags = {
    Name = "dorin-ec2"
  }
}

# elastic IP
resource "aws_eip" "main" {
  instance = aws_instance.main.id
  domain   = "vpc"

  tags = {
    Name = "dorin-eip"
  }
}

data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# Route 53
resource "aws_route53_record" "ec2" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${var.subdomain}.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [aws_eip.main.public_ip]
}

resource "aws_ecr_repository" "ghostfolio" {
  name                 = "ghostfolio"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "ghostfolio"
  }
}

#  Role pentru EC2
resource "aws_iam_role" "ec2_ecr_role" {
  name = "ec2-ecr-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "ec2-ecr-role"
  }
}

# Atasare policy ECR la role
resource "aws_iam_role_policy_attachment" "ec2_ecr_policy" {
  role       = aws_iam_role.ec2_ecr_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Instance Profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-ecr-profile"
  role = aws_iam_role.ec2_ecr_role.name

}

# Task 3.2.6 Connecting EC2 with S3

# S3 Bucket pentru backup-uri
resource "aws_s3_bucket" "db_backups" {
  bucket = "dorin-db-backups"

  tags = {
    Name = "dorin-db-backups"
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "db_backups" {
  bucket = aws_s3_bucket.db_backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle Policy
resource "aws_s3_bucket_lifecycle_configuration" "db_backups" {
  bucket = aws_s3_bucket.db_backups.id

  rule {
    id     = "backup-lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 7
      storage_class = "GLACIER"
    }

    expiration {
      days = 30
    }
  }
}

# IAM Policy pentru S3 backup
resource "aws_iam_policy" "db_backup_policy" {
  name        = "dorin-db-backup-policy"
  description = "Policy pentru acces S3 backup"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.db_backups.arn,
          "${aws_s3_bucket.db_backups.arn}/*"
        ]
      }
    ]
  })
}

# Atașează policy-ul la IAM Role
resource "aws_iam_role_policy_attachment" "ec2_s3_backup_policy" {
  role       = aws_iam_role.ec2_ecr_role.name
  policy_arn = aws_iam_policy.db_backup_policy.arn
}

## Task 3.2.7 Getting cache out of EC2

resource "aws_security_group" "elasticache" {
  name        = "dorin-elasticache-sg"
  description = "Security group ElastiCache redis"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Redis"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "dorin-elasticache-sg"
  }
}

resource "aws_elasticache_subnet_group" "main" {
  name       = "dorin-elasticache-subnet-group"
  subnet_ids = module.vpc.public_subnets

  tags = {
    Name = "dorin-elasticache-subnet-group"
  }
}


#resource "aws_elasticache_cluster" "redis" {
# cluster_id           = "dorin-redis"
# engine               = "redis"
# node_type            = "cache.t3.micro"
#  num_cache_nodes      = 1
#  parameter_group_name = "default.redis7"
#  engine_version       = "7.1"
#  port                 = 6379
#  subnet_group_name    = aws_elasticache_subnet_group.main.name
#  security_group_ids   = [aws_security_group.elasticache.id]

#  tags = {
#    Name = "dorin-redis"
#  }
#}


resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = "dorin-redis"
  description                = "Redis for Ghostfolio"
  node_type                  = "cache.t3.micro"
  num_cache_clusters         = 1
  parameter_group_name       = "default.redis7"
  engine_version             = "7.1"
  port                       = 6379
  subnet_group_name          = aws_elasticache_subnet_group.main.name
  security_group_ids         = [aws_security_group.elasticache.id]
  auth_token                 = var.redis_password
  transit_encryption_enabled = true

  tags = {
    Name = "dorin-redis"
  }
}


# CloudWatch

resource "aws_iam_role_policy_attachment" "ec2_cloudwatch_policy" {
  role       = aws_iam_role.ec2_ecr_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

#Security Group for RDS
resource "aws_security_group" "rds" {
  name        = "dorin-rds-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "PostgreSQL from EC2"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "dorin-rds-sg"
  }
}

# RDS subnet
resource "aws_db_subnet_group" "main" {
  name       = "dorin-rds-subnet-group"
  subnet_ids = module.vpc.public_subnets

  tags = {
    Name = "dorin-rds-subnet-group"
  }
}

# RDS PostgreSQL Instance
resource "aws_db_instance" "postgres" {
  identifier        = "dorin-rds"
  engine            = "postgres"
  engine_version    = "17.5"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = "ghostfolio_db"
  username = "ghostfolio"
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  backup_retention_period = 7
  skip_final_snapshot     = true
  deletion_protection     = false

  tags = {
    Name = "dorin-rds"
  }
}


# Bastion Host  dev
resource "aws_instance" "bastion" {
  count = var.env == "dev" ? 1 : 0

  ami                    = "ami-091138d0f0d41ff90"
  instance_type          = "t2.micro"
  subnet_id              = module.vpc.public_subnets[0]
  vpc_security_group_ids = [aws_security_group.bastion[0].id]
  key_name               = aws_key_pair.main.key_name

  tags = {
    Name = "dorin-bastion"
  }
}

# Security Group for Bastion
resource "aws_security_group" "bastion" {
  count = var.env == "dev" ? 1 : 0

  name        = "dorin-bastion-sg"
  description = "Security group for Bastion Host"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "dorin-bastion-sg"
  }
}

# Elastic IP for Bastion
resource "aws_eip" "bastion" {
  count    = var.env == "dev" ? 1 : 0
  instance = aws_instance.bastion[0].id
  domain   = "vpc"

  tags = {
    Name = "dorin-bastion-eip"
  }
}

# Route 53 record for Bastion
resource "aws_route53_record" "bastion" {
  count   = var.env == "dev" ? 1 : 0
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "bastion.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [aws_eip.bastion[0].public_ip]
}

resource "aws_security_group_rule" "rds_from_bastion" {
  count = var.env == "dev" ? 1 : 0

  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = aws_security_group.bastion[0].id
  description              = "PostgreSQL from Bastion"
}


# ACM Certificate pentru ALB
module "acm_alb" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 4.0"

  domain_name = var.domain_name
  zone_id     = data.aws_route53_zone.main.zone_id

  subject_alternative_names = [
    "*.${var.domain_name}"
  ]

  wait_for_validation = true
}

# Security Group pentru ALB
resource "aws_security_group" "alb" {
  name        = "dorin-alb-sg"
  description = "Security group for ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "dorin-alb-sg"
  }
}

# Target Group
resource "aws_lb_target_group" "main" {
  name     = "dorin-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    path                = "/api/v1/health"
    protocol            = "HTTP"
    healthy_threshold   = 5
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
  }

  tags = {
    Name = "dorin-tg"
  }
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "dorin-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets

  tags = {
    Name = "dorin-alb"
  }
}

# ALB Listener HTTP - redirect to HTTPS
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ALB Listener HTTPS
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = module.acm_alb.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

resource "aws_launch_template" "main" {
  name        = "dorin-lt"
  description = "Launch template for Ghostfolio ASG"

  image_id      = "ami-0fe07a92137c82231"
  instance_type = "t2.micro"
  key_name      = aws_key_pair.main.key_name

  vpc_security_group_ids = [aws_security_group.ec2.id]

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "dorin-asg-instance"
    }
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "main" {
  name                = "dorin-asg"
  desired_capacity    = 1
  min_size            = 1
  max_size            = 3
  vpc_zone_identifier = module.vpc.public_subnets
  target_group_arns   = [aws_lb_target_group.main.arn]

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "dorin-asg-instance"
    propagate_at_launch = true
  }
}

# Auto Scaling Policy - CPU 70%
resource "aws_autoscaling_policy" "cpu" {
  name                   = "dorin-cpu-policy"
  autoscaling_group_name = aws_autoscaling_group.main.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
  }
}