# Infraestrutura do iamp na Oracle Cloud (Always Free)
#
# 1 VM ARM (VM.Standard.A1.Flex) com Docker rodando o mesmo docker-compose.yml do projeto:
# postgres_iamp (pgvector) + api_iamp (FastAPI). O PostgreSQL gerenciado da Oracle nao e gratuito,
# por isso o banco fica num container, com os dados num volume do Docker.
#
# Rede: VCN propria, sub-rede publica e lista de seguranca liberando so SSH (22) e a API (8000).
# A porta do PostgreSQL nao e liberada: o banco so e acessivel de dentro da VM.

locals {
  compartimento = coalesce(var.compartment_ocid, var.tenancy_ocid)
  nome          = "iamp"
  porta_api     = 8000
  pasta_app     = "/opt/iamp/app" # o nome da pasta nao pode mudar: o volume do banco depende dele
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# Ubuntu 24.04 mais recente compativel com o shape (ARM)
data "oci_core_images" "ubuntu" {
  compartment_id           = local.compartimento
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# Rede ---------------------------------------------------------------------------------------

resource "oci_core_vcn" "rede" {
  compartment_id = local.compartimento
  display_name   = "${local.nome}-vcn"
  cidr_blocks    = ["10.0.0.0/16"]
  dns_label      = local.nome
}

resource "oci_core_internet_gateway" "internet" {
  compartment_id = local.compartimento
  vcn_id         = oci_core_vcn.rede.id
  display_name   = "${local.nome}-igw"
  enabled        = true
}

resource "oci_core_route_table" "publica" {
  compartment_id = local.compartimento
  vcn_id         = oci_core_vcn.rede.id
  display_name   = "${local.nome}-rotas"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.internet.id
  }
}

resource "oci_core_security_list" "publica" {
  compartment_id = local.compartimento
  vcn_id         = oci_core_vcn.rede.id
  display_name   = "${local.nome}-firewall"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # SSH (deploy e manutencao)
  ingress_security_rules {
    source   = var.ssh_origem_permitida
    protocol = "6" # TCP
    tcp_options {
      min = 22
      max = 22
    }
  }

  # API FastAPI (o app Flutter usa esta porta)
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"
    tcp_options {
      min = local.porta_api
      max = local.porta_api
    }
  }

  # ICMP "fragmentation needed": necessario para o TCP funcionar bem pela internet
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "1"
    icmp_options {
      type = 3
      code = 4
    }
  }
}

resource "oci_core_subnet" "publica" {
  compartment_id    = local.compartimento
  vcn_id            = oci_core_vcn.rede.id
  display_name      = "${local.nome}-subrede"
  cidr_block        = "10.0.1.0/24"
  dns_label         = "publica"
  route_table_id    = oci_core_route_table.publica.id
  security_list_ids = [oci_core_security_list.publica.id]
}

# Maquina ------------------------------------------------------------------------------------

resource "oci_core_instance" "api" {
  compartment_id      = local.compartimento
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[var.indice_ad].name
  display_name        = "${local.nome}-api"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memoria_gb
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu.images[0].id
    boot_volume_size_in_gbs = var.disco_gb
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.publica.id
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = file(pathexpand(var.ssh_chave_publica))
    # so instala o Docker; nenhum segredo vai nos metadados da VM
    user_data = base64encode(file("${path.module}/cloud-init.yaml"))
  }

  lifecycle {
    # a Oracle publica imagens novas do Ubuntu com frequencia: nao recriar a VM por isso
    ignore_changes = [source_details[0].source_id]
  }
}

# Aplicacao ----------------------------------------------------------------------------------

resource "random_password" "postgres" {
  length  = 24
  special = false # a senha entra na URL de conexao (config.py) sem escape
}

locals {
  # mesmo formato do .env.example; POSTGRES_HOST/PORT da API sao trocados pelo docker-compose
  arquivo_env = <<-EOT
    POSTGRES_USER=admin
    POSTGRES_PASSWORD=${random_password.postgres.result}
    POSTGRES_DB=banco_projeto
    POSTGRES_HOST=localhost
    POSTGRES_PORT=5434
    GEMINI_API_KEY=${var.gemini_api_key}
    GEMINI_MODELOS=${var.gemini_modelos}
  EOT
}

# Codigo do projeto, so o que a API e o carregar_rag.py usam (mesma ideia do .dockerignore)
data "archive_file" "codigo" {
  type        = "zip"
  source_dir  = "${path.module}/../.."
  output_path = "${path.module}/.build/iamp.zip"
  excludes = [
    ".git/**", ".venv/**", ".env", ".claude/**", ".vscode/**", ".pytest_cache/**", "**/__pycache__/**",
    "app_gerenciamento_energetico/**", "notebooks/**", "docs/**", "infra/**", "prompts/**", "tests/**",
    "models/ctgan.pkl", "models/fastembed/**", "datasets/raw/*.csv",
  ]
}

# Deploy: refeito quando a VM, o codigo ou o .env mudam (terraform apply = publicar versao nova)
resource "terraform_data" "deploy" {
  triggers_replace = [
    oci_core_instance.api.id,
    data.archive_file.codigo.output_sha256,
    sha256(local.arquivo_env),
    var.carregar_rag,
  ]

  connection {
    type        = "ssh"
    host        = oci_core_instance.api.public_ip
    user        = "ubuntu"
    private_key = file(pathexpand(var.ssh_chave_privada))
    timeout     = "10m"
  }

  provisioner "file" {
    source      = data.archive_file.codigo.output_path
    destination = "/tmp/iamp.zip"
  }

  provisioner "file" {
    content     = local.arquivo_env
    destination = "/tmp/iamp.env"
  }

  provisioner "remote-exec" {
    inline = concat([
      "set -e",
      "cloud-init status --wait > /dev/null || true", # espera o Docker ser instalado (1a subida)
      "sudo rm -rf ${local.pasta_app} && sudo mkdir -p ${local.pasta_app}",
      "sudo unzip -q /tmp/iamp.zip -d ${local.pasta_app}",
      "sudo install -m 600 /tmp/iamp.env ${local.pasta_app}/.env && rm -f /tmp/iamp.env /tmp/iamp.zip",
      "cd ${local.pasta_app}",
      # a 1a subida da API carrega os CSVs no banco (pode levar alguns minutos)
      "sudo docker compose up -d --build --wait --wait-timeout 900",
      "sudo docker image prune -f > /dev/null",
      ], var.carregar_rag ? [
      # roda dentro da imagem da API (que ja tem o modelo de embeddings), com os scripts e os documentos montados
      "sudo docker compose run --rm -v ${local.pasta_app}/scripts:/app/scripts:ro -v ${local.pasta_app}/datasets/raw/rag:/app/datasets/raw/rag:ro -w /app api python scripts/carregar_rag.py",
    ] : [])
  }
}
