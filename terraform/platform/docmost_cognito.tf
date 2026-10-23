# Adopt the Cognito user pool, app client, and domain created in the AWS console.
# The domain prefix is derived from the pool ID, so no project identifier is
# hard-coded in this public repository.
resource "aws_cognito_user_pool" "docmost_access" {
  name                     = "User pool - s7wwcs"
  deletion_protection      = "ACTIVE"
  user_pool_tier           = "ESSENTIALS"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  mfa_configuration        = "OFF"

  username_configuration {
    case_sensitive = false
  }

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  password_policy {
    minimum_length                   = 8
    require_uppercase                = true
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  sign_in_policy {
    allowed_first_auth_factors = ["PASSWORD"]
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }

    recovery_mechanism {
      name     = "verified_phone_number"
      priority = 2
    }
  }
}

resource "aws_cognito_user_pool_client" "docmost_access" {
  name         = "docmost"
  user_pool_id = aws_cognito_user_pool.docmost_access.id

  generate_secret                      = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid", "phone"]
  callback_urls                        = ["https://${local.docmost_hostname}/oauth2/idpresponse"]
  supported_identity_providers         = ["COGNITO"]

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_AUTH",
    "ALLOW_USER_SRP_AUTH",
  ]

  auth_session_validity         = 3
  refresh_token_validity        = 5
  access_token_validity         = 60
  id_token_validity             = 60
  enable_token_revocation       = true
  prevent_user_existence_errors = "ENABLED"

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  # The provider does not infer generate_secret from an imported app client.
  # Preserve the existing client ID and secret while retaining this setting
  # for any deliberate future recreation.
  lifecycle {
    ignore_changes = [generate_secret]
  }
}

resource "aws_cognito_user_pool_domain" "docmost_access" {
  domain                = replace(lower(aws_cognito_user_pool.docmost_access.id), "_", "")
  user_pool_id          = aws_cognito_user_pool.docmost_access.id
  managed_login_version = 2
}
