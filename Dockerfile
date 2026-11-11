FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src ./src
COPY datasets/processed ./datasets/processed
# so o K-Means (numeros puros, sem scikit-learn); o ctgan.pkl precisaria do torch
COPY models/kmeans.pkl ./models/kmeans.pkl
COPY models/refrigerador.pkl ./models/refrigerador.pkl
# documentos do Eco-Coach + carga: com a base vazia (banco novo, ex.: Neon), a API carrega sozinha ao subir
COPY datasets/raw/rag ./datasets/raw/rag
COPY scripts/carregar_rag.py ./scripts/carregar_rag.py

WORKDIR /app/src
EXPOSE 8000

# porta: a do ambiente (o Render define PORT) ou 8000 (docker compose, Terraform)
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}"]
