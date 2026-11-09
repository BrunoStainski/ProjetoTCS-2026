output "ip_publico" {
  description = "IP publico da VM (muda se a VM for recriada)."
  value       = oci_core_instance.api.public_ip
}

output "api_url" {
  description = "Endereco da API. No app: flutter run --dart-define=API_URL=<este endereco>"
  value       = "http://${oci_core_instance.api.public_ip}:${local.porta_api}"
}

output "docs_url" {
  value = "http://${oci_core_instance.api.public_ip}:${local.porta_api}/docs"
}

output "ssh" {
  value = "ssh -i ${var.ssh_chave_privada} ubuntu@${oci_core_instance.api.public_ip}"
}

output "senha_postgres" {
  description = "Ver com: terraform output senha_postgres"
  value       = random_password.postgres.result
  sensitive   = true
}
