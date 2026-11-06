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
# modelo de embeddings do Eco-Coach baixado no build (~220 MB): a API nao depende de download na 1a busca
RUN python -c "from fastembed import TextEmbedding; TextEmbedding('sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2', cache_dir='/app/models/fastembed')"

WORKDIR /app/src
EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
