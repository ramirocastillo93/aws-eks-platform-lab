variable "aws_region" {
  description = "The project's selected AWS Region."
  type        = string

  validation {
    condition     = var.aws_region == "us-east-2"
    error_message = "This lab is configured for the project's selected Region, us-east-2."
  }
}

variable "eks_api_allowed_cidrs" {
  description = "Public IPv4 CIDRs allowed to reach the EKS Kubernetes API endpoint. Supply as a JSON list through TF_VAR_eks_api_allowed_cidrs."
  type        = list(string)

  validation {
    condition     = length(var.eks_api_allowed_cidrs) > 0 && length(var.eks_api_allowed_cidrs) <= 40 && alltrue([for cidr in var.eks_api_allowed_cidrs : can(cidrnetmask(cidr))]) && !contains(var.eks_api_allowed_cidrs, "0.0.0.0/0")
    error_message = "Provide between 1 and 40 valid IPv4 CIDRs for EKS API access, excluding 0.0.0.0/0."
  }
}

variable "eks_admin_role_name" {
  description = "Existing AWS project role granted Kubernetes cluster-admin access."
  type        = string
  default     = "AccountFullAccessRole"
}
