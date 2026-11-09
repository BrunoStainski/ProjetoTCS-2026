variable "docker_host" {
  description = "Endereco do Docker. Em branco = padrao da maquina. Ex. Windows: npipe:////./pipe/dockerDesktopLinuxEngine"
  type        = string
  default     = null
}

variable "prefixo" {
  description = "Prefixo dos nomes (containers, rede, volume). Diferente do docker-compose para os dois conviverem."
  type        = string
  default     = "iamp_tf"
}

variable "porta_api" {
  description = "Porta da API no computador (o docker-compose usa 8000)."
  type        = number
  default     = 8080
}

variable "porta_postgres" {
  description = "Porta do PostgreSQL no computador, so em 127.0.0.1 (o docker-compose usa 5434)."
  type        = number
  default     = 5435
}

variable "gemini_api_key" {
  description = "Chave do Google AI Studio para o Eco-Coach. Em branco = /eco-coach responde 503."
  type        = string
  default     = ""
  sensitive   = true
}

variable "gemini_modelos" {
  description = "Modelos do Gemini em ordem de preferencia (o mesmo GEMINI_MODELOS do .env)."
  type        = string
  default     = "gemini-3.5-flash,gemini-3.5-flash-lite"
}

variable "carregar_rag" {
  description = "Rodar scripts/carregar_rag.py (base vetorial do Eco-Coach) depois de subir a API."
  type        = bool
  default     = true
}
