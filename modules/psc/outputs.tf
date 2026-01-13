# =============================================================================
# PSC Module - Outputs
# =============================================================================

output "psc_subnet_name" {
  description = "The name of the PSC subnet"
  value       = local.psc_subnet_name
}

output "psc_endpoint_ip" {
  description = "The IP address of the PSC Google APIs endpoint"
  value       = var.enabled ? google_compute_global_address.psc_google_apis[0].address : null
}

output "psc_forwarding_rule" {
  description = "The PSC forwarding rule for Google APIs"
  value       = var.enabled ? google_compute_global_forwarding_rule.psc_google_apis[0] : null
}

output "googleapis_dns_zone" {
  description = "The private DNS zone for googleapis.com"
  value       = var.enabled ? google_dns_managed_zone.googleapis[0] : null
}

output "gcr_dns_zone" {
  description = "The private DNS zone for gcr.io"
  value       = var.enabled ? google_dns_managed_zone.gcr[0] : null
}
