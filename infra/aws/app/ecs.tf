resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.app_name}"
  retention_in_days = 7 # keep logs a week: enough for debugging, cheap
}

# With Fargate the cluster is just a named group: there are no servers in it to manage.
resource "aws_ecs_cluster" "main" {
  name = "${var.app_name}-cluster"
}

# The recipe for one task (like a pod spec): image, size, port, logs.
resource "aws_ecs_task_definition" "app" {
  family                   = var.app_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc" # each task gets its own network interface + IP
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = var.app_name
    image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
    essential = true
    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]
    environment = [{ name = "APP_VERSION", value = var.image_tag }]
    logConfiguration = {
      logDriver = "awslogs" # container stdout/stderr -> CloudWatch Logs
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "app"
      }
    }
  }])
}

# The service keeps N tasks running and registers them with the load balancer
# (like a Kubernetes Deployment + Service together).
resource "aws_ecs_service" "app" {
  name            = var.app_name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.min_tasks
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = true # needed to reach ECR without a NAT gateway (see network.tf)
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = var.app_name
    container_port   = var.container_port
  }

  # Give TensorFlow time to load before the ALB health checks count.
  health_check_grace_period_seconds = 90

  # Rolling deployment: start new tasks first (up to 200%), never drop below 100% healthy.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # If a new version never becomes healthy, stop and roll back to the last good one.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Same lesson as Track A: autoscaling owns the count, Terraform must not reset it.
  # CD owns which task definition revision (= which image) is live: the pipeline
  # registers a new revision per commit, and Terraform must not roll it back.
  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }

  depends_on = [aws_lb_listener.http, aws_iam_role_policy_attachment.execution]
}
