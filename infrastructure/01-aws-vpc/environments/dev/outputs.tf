#--------------------------------------------------------------
# 1. The Public Application URL (The most important output!)
#--------------------------------------------------------------
output "ritual_roast_public_url" {
  description = "The DNS Name of the Public ALB to access the Next.js frontend."
  value       = "http://${module.alb.public_alb_dns_name}"
}