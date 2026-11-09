output "api_url" {
  description = "No app: flutter run -d chrome --dart-define=API_URL=<este endereco>"
  value       = "http://localhost:${var.porta_api}"
}

output "docs_url" {
  value = "http://localhost:${var.porta_api}/docs"
}

output "banco" {
  description = "Para criar_banco.py/pytest do PC: POSTGRES_PORT e a senha (terraform output senha_postgres)."
  value       = "localhost:${var.porta_postgres} (usuario admin, banco banco_projeto)"
}

output "senha_postgres" {
  description = "Ver com: terraform output senha_postgres"
  value       = random_password.postgres.result
  sensitive   = true
}
