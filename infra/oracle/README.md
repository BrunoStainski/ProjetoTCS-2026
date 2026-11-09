# Infra do iamp: Oracle Cloud (Always Free) com Terraform

Cria **1 VM ARM** (`VM.Standard.A1.Flex`, 2 OCPUs e 12 GB por padrão) com rede própria e
publica a API rodando o mesmo `docker-compose.yml` do projeto (PostgreSQL com pgvector e FastAPI).

```
terraform apply
  -> VCN + sub-rede pública + internet gateway + firewall (só portas 22 e 8000)
  -> VM Ubuntu 24.04 ARM (cloud-init instala o Docker)
  -> envia o código por SSH (zip do projeto, sem .env/.venv/app) e um .env gerado
  -> docker compose up --build  (a API carrega os CSVs no banco na 1ª subida)
  -> scripts/carregar_rag.py    (base vetorial do Eco-Coach)
```

O PostgreSQL gerenciado da Oracle não entra no plano gratuito, por isso o banco roda num
container na própria VM. A porta dele não é liberada no firewall.

## Pré-requisitos (uma vez)

1. **Terraform** ≥ 1.5 (`winget install Hashicorp.Terraform`).
2. **Conta Oracle Cloud** no Always Free. O gratuito só vale na *home region* da conta.
3. **API key da Oracle**: no console, Perfil → *API keys* → *Add API key* → baixe a chave privada.
   Depois copie o *Configuration file preview* para `~/.oci/config`, ajustando `key_file` para o
   caminho da chave baixada.
4. **Chave SSH**: `ssh-keygen -t ed25519` (gera `~/.ssh/id_ed25519` e `.pub`).

## Subir

```bash
cd infra/oracle
cp terraform.tfvars.example terraform.tfvars   # preencha tenancy_ocid, região e gemini_api_key
terraform init
terraform plan
terraform apply          # ~10-15 min na 1ª vez (instala o Docker, build da imagem ARM, carga do banco)
terraform output         # api_url, docs_url, ssh
```

App Flutter apontando para a nuvem:
`flutter run -d chrome --dart-define=API_URL=<api_url>`.

**Publicar código novo:** rode `terraform apply` de novo. O deploy refaz o envio quando o código
ou o `.env` mudam. A VM continua a mesma e os dados do banco ficam no volume do Docker.

**Derrubar tudo:** `terraform destroy`.

## Problemas comuns

- **`Out of host capacity`**: a Oracle está sem máquina ARM gratuita naquele datacenter. Tente
  `indice_ad = 1` ou `2` (se a região tiver) ou tente de novo mais tarde.
- **SSH com timeout no deploy**: confira se `ssh_origem_permitida` inclui o seu IP atual.
- **Logs da API**: `ssh ubuntu@<ip>` e depois `cd /opt/iamp/app && sudo docker compose logs api`.

## Segurança e limitações

- Segredos (senha do banco, gerada aleatoriamente, e chave do Gemini) ficam no `terraform.tfstate`
  e no `.env` da VM (permissão 600), **nunca** nos metadados da VM nem no git. O state e o
  `terraform.tfvars` estão no `.gitignore`. Quem tiver o state tem as senhas.
- O state é **local**: só quem rodou o `apply` consegue alterar a infra. Para o grupo todo, o
  próximo passo seria um backend remoto (ex.: bucket do Object Storage da Oracle).
- A API é exposta em **HTTP**, sem HTTPS e sem autenticação (projeto de demonstração). Para
  produção: domínio + proxy com TLS (Caddy/Nginx) e restringir `CORS_ORIGINS`.
- O IP público muda se a VM for recriada.
