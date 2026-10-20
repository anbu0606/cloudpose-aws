# Private image registry (AWS's own Docker Hub).
resource "aws_ecr_repository" "app" {
  name                 = var.app_name
  image_tag_mutability = "IMMUTABLE" # a tag like 0.3.0 can never be overwritten
  force_delete         = true        # lets terraform destroy remove it even with images inside

  image_scanning_configuration {
    scan_on_push = true # basic CVE scan of every pushed image
  }
}

# Keep only the 5 newest images to keep storage cost tiny.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}
