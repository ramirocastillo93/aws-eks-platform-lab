variable "aws_region" {
  description = "The project's selected AWS Region."
  type        = string

  validation {
    condition     = var.aws_region == "us-east-2"
    error_message = "This lab is configured for the project's selected Region, us-east-2."
  }
}
