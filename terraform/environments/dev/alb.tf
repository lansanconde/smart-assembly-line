# ──────────────────────────────────────────────
# Security Group — ALB
# Autorise le trafic HTTP/HTTPS entrant depuis internet
# ──────────────────────────────────────────────

resource "aws_security_group" "alb" {
  name        = "smart-assembly-alb-sg"
  description = "ALB security group - HTTP/HTTPS inbound"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Outbound to backend instances"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "smart-assembly-alb-sg"
    Project     = "smart-assembly-line"
    Environment = "dev"
  }
}

# ──────────────────────────────────────────────
# ALB — Application Load Balancer
# ──────────────────────────────────────────────

resource "aws_lb" "main" {
  name               = "smart-assembly-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public.id, aws_subnet.public_b.id]

  tags = {
    Name        = "smart-assembly-alb"
    Project     = "smart-assembly-line"
    Environment = "dev"
  }
}

# ──────────────────────────────────────────────
# Target Group — ECS Fargate (supervision-api)
# target_type = "ip" obligatoire pour Fargate (awsvpc)
# ──────────────────────────────────────────────

resource "aws_lb_target_group" "backend" {
  name        = "smart-assembly-supervision-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip" # Fargate utilise des IPs, pas des instance IDs

  health_check {
    path                = "/actuator/health" # Spring Boot Actuator
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }

  tags = {
    Name        = "smart-assembly-supervision-tg"
    Project     = "smart-assembly-line"
    Environment = "dev"
  }
}

# ──────────────────────────────────────────────
# Listener — port 80 → forward vers Target Group
# ──────────────────────────────────────────────

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}
