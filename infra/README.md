# Infra do iamp (Terraform)

| Pasta | Onde roda | Status |
|---|---|---|
| [`local/`](local/) | Docker do próprio computador (Docker Desktop) | **em uso** |
| [`oracle/`](oracle/) | Oracle Cloud Always Free (1 VM ARM) | pronto, falta a conta ([README](oracle/README.md)) |

Os dois sobem a mesma aplicação do `docker-compose.yml` (PostgreSQL com pgvector + API FastAPI +
carga do RAG). A diferença está no *provider*: `kreuzwerker/docker` no local e `oracle/oci` na nuvem.

Para a apresentação, a nuvem escolhida foi o **Render + Neon** (gratuitos, sem cartão), porque a conta
da Oracle demora até duas semanas para ser liberada. Essa publicação não usa Terraform: o Render lê o
[`render.yaml`](../render.yaml) da raiz. Passo a passo no README da raiz (Passo 11).

## Local (Docker)

Pré-requisitos: Terraform ≥ 1.5 (`winget install Hashicorp.Terraform`) e o Docker Desktop aberto.

```bash
cd infra/local
cp terraform.tfvars.example terraform.tfvars   # gemini_api_key: carga do RAG (embeddings) e /eco-coach
terraform init
terraform plan        # mostra o que vai ser criado
terraform apply       # ~5-10 min na 1ª vez (build da imagem + carga do banco + RAG)
terraform output      # api_url, docs_url, banco
terraform destroy     # remove containers, rede, imagem da API e o volume do banco
```

O que é criado (prefixo `iamp_tf`, para conviver com o `docker compose`):

```
docker_network  iamp_tf_rede
docker_volume   iamp_tf_dados_postgres          (dados do banco)
docker_container iamp_tf_postgres   127.0.0.1:5435 -> 5432   (pgvector/pgvector:pg15, healthcheck)
imagem          iamp_tf_api:<hash>  (terraform_data roda "docker build"; refeita quando src/,
                                     datasets/processed, requirements.txt, Dockerfile ou kmeans.pkl mudam)
docker_container iamp_tf_api        0.0.0.0:8080 -> 8000     (espera o /saude responder)
docker_container iamp_tf_carga_rag  roda scripts/carregar_rag.py uma vez e termina
```

- App apontando para ela: `flutter run -d chrome --dart-define=API_URL=http://localhost:8080`.
- Mudou código? `terraform apply` de novo: só o que mudou é refeito (a imagem, a API e a carga do RAG).
- A senha do banco é gerada pelo Terraform (`terraform output senha_postgres`) e fica só no
  `terraform.tfstate`, que está no `.gitignore` (assim como o `terraform.tfvars`).
- Saída da carga do RAG: `docker logs iamp_tf_carga_rag`. Sem a `gemini_api_key`, a carga falha
  (os vetores vêm da API do Gemini) e o `/eco-coach` responde 503; o resto da API funciona.
