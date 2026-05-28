output "ritual_roast_public_url" {
  description = "The public URL to access the Ritual Roast Application"
  # Pulling the DNS name directly from the Layer 1 Gateway data fetch!

  value = "http://${data.aws_lb.gateway_alb.dns_name}"
}