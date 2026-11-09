# Conta Oracle ------------------------------------------------------------------------------

variable "tenancy_ocid" {
  description = "OCID da tenancy (console: Perfil -> Tenancy). Tambem esta no ~/.oci/config."
  type        = string
}

variable "compartment_ocid" {
  description = "Compartimento onde os recursos sao criados. Em branco = raiz da tenancy."
  type        = string
  default     = null
}

variable "regiao" {
  description = "Regiao da Oracle Cloud (a home region da conta; o Always Free so vale nela)."
  type        = string
  default     = "sa-saopaulo-1"
}

variable "oci_perfil" {
  description = "Perfil do ~/.oci/config com a API key."
  type        = string
  default     = "DEFAULT"
}

# Maquina (limites do Always Free: 4 OCPUs, 24 GB de RAM e 200 GB de disco no total) ---------

variable "ocpus" {
  description = "OCPUs da VM ARM (A1.Flex)."
  type        = number
  default     = 2
}

variable "memoria_gb" {
  description = "RAM da VM em GB."
  type        = number
  default     = 12
}

variable "disco_gb" {
  description = "Disco de boot em GB (minimo 50)."
  type        = number
  default     = 50
}

variable "indice_ad" {
  description = "Availability domain (0, 1 ou 2). Se der 'Out of host capacity', tente outro."
  type        = number
  default     = 0
}

# Acesso -------------------------------------------------------------------------------------

variable "ssh_chave_publica" {
  description = "Caminho da chave publica SSH colocada na VM."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_chave_privada" {
  description = "Caminho da chave privada SSH (o Terraform usa para enviar o codigo)."
  type        = string
  default     = "~/.ssh/id_ed25519"
}

variable "ssh_origem_permitida" {
  description = "Faixa de IP que pode entrar por SSH. Recomendado: o seu IP com /32."
  type        = string
  default     = "0.0.0.0/0"
}

# Aplicacao ----------------------------------------------------------------------------------

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
  description = "Recarregar a base vetorial do Eco-Coach (scripts/carregar_rag.py) a cada deploy."
  type        = bool
  default     = true
}
