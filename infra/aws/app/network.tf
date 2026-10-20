# Use the default VPC every AWS account has in each region: fastest to start.
# Production would use a custom VPC with private subnets + NAT gateway, but a
# NAT gateway costs money every hour, so for a learning project the tasks run in
# public subnets and the security groups only let the load balancer reach them.
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Firewall for the load balancer: the world may reach port 80.
resource "aws_security_group" "alb" {
  name        = "${var.app_name}-alb"
  description = "Public HTTP into the load balancer"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from anywhere"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# Firewall for the tasks: ONLY the load balancer's security group may reach the app port.
resource "aws_security_group" "tasks" {
  name        = "${var.app_name}-tasks"
  description = "App port only from the load balancer"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_vpc_security_group_ingress_rule" "tasks_from_alb" {
  security_group_id            = aws_security_group.tasks.id
  description                  = "App port from the ALB only"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  referenced_security_group_id = aws_security_group.alb.id
}

# Outbound: needed to pull the image from ECR and send logs to CloudWatch.
resource "aws_vpc_security_group_egress_rule" "tasks_all" {
  security_group_id = aws_security_group.tasks.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
