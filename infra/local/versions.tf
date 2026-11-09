terraform {
  required_version = ">= 1.5"

  required_providers {
    # controla o Docker da maquina (Docker Desktop no Windows/Mac, dockerd no Linux)
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    # gera a senha do PostgreSQL (fica so no state, que nao vai para o git)
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Sem host = usa o padrao da maquina (DOCKER_HOST ou o socket/pipe do Docker Desktop)
provider "docker" {
  host = var.docker_host
}
