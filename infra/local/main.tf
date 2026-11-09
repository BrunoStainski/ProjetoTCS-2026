# Infraestrutura do iamp no Docker local, gerenciada pelo Terraform
#
# Faz o mesmo que o docker-compose.yml, mas como infraestrutura como codigo (estado, plan, destroy):
#   rede + volume -> PostgreSQL 15 com pgvector -> imagem da API (build do Dockerfile)
#   -> container da API (1a subida carrega os CSVs no banco) -> carga do RAG (container de uma vez so)
# Nomes e portas sao diferentes do compose (prefixo iamp_tf, portas 8080/5435): os dois podem rodar juntos.

locals {
  raiz          = abspath("${path.module}/../..")
  host_postgres = "${var.prefixo}_postgres" # nome do container = nome na rede interna
  postgres_env = [
    "POSTGRES_USER=admin",
    "POSTGRES_PASSWORD=${random_password.postgres.result}",
    "POSTGRES_DB=banco_projeto",
  ]

  # arquivos que entram na imagem da API: se algum mudar, a imagem e refeita
  arquivos_imagem = concat(
    ["Dockerfile", "requirements.txt", "models/kmeans.pkl"],
    [for f in fileset(local.raiz, "src/**/*.py") : f],
    [for f in fileset(local.raiz, "datasets/processed/*") : f],
  )
  hash_imagem = sha1(join(",", [for f in local.arquivos_imagem : filesha1("${local.raiz}/${f}")]))
}

resource "random_password" "postgres" {
  length  = 24
  special = false # a senha entra na URL de conexao (config.py) sem escape
}

# Rede e disco -------------------------------------------------------------------------------

resource "docker_network" "rede" {
  name = "${var.prefixo}_rede"
}

# dados do banco; sobrevivem a recriar os containers (so somem no terraform destroy)
resource "docker_volume" "dados" {
  name = "${var.prefixo}_dados_postgres"
}

# Banco --------------------------------------------------------------------------------------

resource "docker_image" "postgres" {
  name         = "pgvector/pgvector:pg15"
  keep_locally = true # nao apaga a imagem no destroy (o docker-compose usa a mesma)
}

resource "docker_container" "postgres" {
  name    = local.host_postgres
  image   = docker_image.postgres.image_id
  restart = "unless-stopped"
  env     = local.postgres_env

  networks_advanced {
    name = docker_network.rede.id
  }

  # so no 127.0.0.1: da para usar o criar_banco.py/pytest do PC, mas nao fica aberto na rede
  ports {
    internal = 5432
    external = var.porta_postgres
    ip       = "127.0.0.1"
  }

  volumes {
    volume_name    = docker_volume.dados.name
    container_path = "/var/lib/postgresql/data"
  }

  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U admin -d banco_projeto"]
    interval = "5s"
    timeout  = "5s"
    retries  = 12
  }

  wait         = true # so segue (cria a API) quando o banco estiver healthy
  wait_timeout = 120
}

# API ----------------------------------------------------------------------------------------

# Build pelo "docker build" da maquina, e nao pelo bloco build do provider: no Docker Desktop
# (Windows) o build do provider trava em "load remote build context". O docker build normal usa o
# cache e leva ~2 min. A tag leva o hash dos arquivos: mudou o codigo -> imagem nova -> API recriada.
resource "terraform_data" "imagem_api" {
  input            = "${var.prefixo}_api:${substr(local.hash_imagem, 0, 12)}"
  triggers_replace = [local.hash_imagem]

  provisioner "local-exec" {
    command     = "docker build -t ${self.input} ."
    working_dir = local.raiz # sem aspas no comando: o cmd do Windows as repassa ao docker
  }

  # destroy (ou imagem nova): apaga a tag antiga
  provisioner "local-exec" {
    when       = destroy
    command    = "docker rmi ${self.input}"
    on_failure = continue
  }
}

resource "docker_container" "api" {
  name    = "${var.prefixo}_api"
  image   = terraform_data.imagem_api.output
  restart = "unless-stopped"

  env = concat(local.postgres_env, [
    "POSTGRES_HOST=${local.host_postgres}",
    "POSTGRES_PORT=5432",
    "GEMINI_API_KEY=${var.gemini_api_key}",
    "GEMINI_MODELOS=${var.gemini_modelos}",
  ])

  networks_advanced {
    name = docker_network.rede.id
  }

  ports {
    internal = 8000
    external = var.porta_api
  }

  healthcheck {
    test         = ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/saude')"]
    interval     = "10s"
    timeout      = "5s"
    retries      = 12
    start_period = "1m30s"
  }

  wait         = true # a 1a subida carrega os CSVs no banco (pode levar alguns minutos)
  wait_timeout = 900

  depends_on = [docker_container.postgres]
}

# Carga do RAG -------------------------------------------------------------------------------
# Container de uma vez so com a imagem da API (que ja tem o modelo de embeddings). O script e os
# documentos nao estao na imagem (.dockerignore), entao sao copiados para dentro antes de rodar.
# Roda de novo quando a imagem, o script ou os documentos mudam.

resource "docker_container" "carga_rag" {
  count = var.carregar_rag ? 1 : 0

  name        = "${var.prefixo}_carga_rag"
  image       = terraform_data.imagem_api.output
  env         = docker_container.api.env
  working_dir = "/app"
  command     = ["python", "scripts/carregar_rag.py"]
  must_run    = false # termina sozinho
  attach      = true  # o terraform espera terminar (e falha se o script der erro)
  logs        = true  # saida do script em container_logs (terraform state show)

  networks_advanced {
    name = docker_network.rede.id
  }

  upload {
    file        = "/app/scripts/carregar_rag.py"
    source      = "${local.raiz}/scripts/carregar_rag.py"
    source_hash = filesha1("${local.raiz}/scripts/carregar_rag.py")
  }

  dynamic "upload" {
    for_each = fileset("${local.raiz}/datasets/raw/rag", "*")
    content {
      file        = "/app/datasets/raw/rag/${upload.value}"
      source      = "${local.raiz}/datasets/raw/rag/${upload.value}"
      source_hash = filesha1("${local.raiz}/datasets/raw/rag/${upload.value}")
    }
  }

  depends_on = [docker_container.api] # a API cria as tabelas (cargas) antes
}
