terraform {
  required_version = ">= 1.5"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
    # gera a senha do PostgreSQL (fica so no state, que nao vai para o git)
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    # compacta o codigo do projeto para enviar a VM (repo privado: a VM nao faz git clone)
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Credenciais: le o ~/.oci/config (perfil var.oci_perfil), criado ao adicionar a API key no
# console da Oracle (Perfil -> API keys -> Add API key -> copiar o "Configuration file preview").
provider "oci" {
  region              = var.regiao
  config_file_profile = var.oci_perfil
}
