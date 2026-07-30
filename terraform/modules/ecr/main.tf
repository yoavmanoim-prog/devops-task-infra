# Single account-level ECR repository for the app image. Shared across all
# three environments (dev/staging/prod all pull from the same repo, just
# different tags) per the "build once, promote the same artifact" flow -
# a separate repo per env would let dev and prod drift to different digests
# for what's supposed to be the identical, already-tested image.
resource "aws_ecr_repository" "app" {
  name                 = var.repository_name
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = "KMS"
  }

  tags = var.tags
}

# Untagged images (left behind when a digest is superseded under the same
# tag is impossible here since tags are IMMUTABLE, but re-pushing a retagged
# manifest can still orphan the old untagged manifest) get swept on a timer;
# tagged sha-*/v* images are kept up to a count instead of a time window,
# since a demo repo's push cadence during a review period is unpredictable.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.untagged_image_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_image_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the most recent ${var.tagged_image_keep_count} tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["sha-*", "v*"]
          countType      = "imageCountMoreThan"
          countNumber    = var.tagged_image_keep_count
        }
        action = { type = "expire" }
      }
    ]
  })
}
