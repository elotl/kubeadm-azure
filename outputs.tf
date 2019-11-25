output "master_ip" {
  value = azurerm_public_ip.master-ip.ip_address
}

output "milpa_worker_ips" {
  value = azurerm_public_ip.worker-ip.ip_address
}
