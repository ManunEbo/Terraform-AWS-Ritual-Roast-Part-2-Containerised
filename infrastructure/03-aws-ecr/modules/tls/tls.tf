# Fetch GitHub's Secure Certificate Thumbprint
data "tls_certificate" "rr_github" {
  url = "https://token.actions.githubusercontent.com"
}

# Tell AWS to trust GitHub as an Identity Provider
resource "aws_iam_openid_connect_provider" "rr_github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.rr_github.certificates[0].sha1_fingerprint]
}
