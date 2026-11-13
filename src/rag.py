"""
Base vetorial do Eco-Coach (RAG): trechos de documentos oficiais guardados no PostgreSQL
com a extensao pgvector.

- Embeddings pela API do Gemini (mesma GEMINI_API_KEY do Eco-Coach). Antes eram locais (fastembed), mas o
  modelo ocupava ~550 MB de memoria e a API nao cabia no plano gratuito do Render (512 MB).
  Vao para o Google so os trechos dos documentos publicos e as perguntas de busca (nomes de aparelhos),
  nada do usuario. Modelo em GEMINI_EMBEDDING_MODEL (padrao gemini-embedding-001).
- Os trechos vem de documentos publicos (Inmetro, Cemig); nada do usuario e gravado aqui.
- Carga: scripts/carregar_rag.py (le datasets/raw/rag/ e o fontes.csv com a origem de cada um).
"""

from functools import lru_cache

import banco
import config

EMBEDDING_MODEL = config._ENV.get("GEMINI_EMBEDDING_MODEL", "gemini-embedding-001")
DIMENSION = 768  # tamanho recomendado pelo Google (768, 1536 ou 3072)
BATCH = 100  # textos por chamada na carga

RAG_SCHEMA = f"""
CREATE EXTENSION IF NOT EXISTS vector;
CREATE TABLE IF NOT EXISTS trechos_rag (
    id            SERIAL PRIMARY KEY,
    documento     TEXT NOT NULL,          -- titulo do documento de origem
    orgao         TEXT NOT NULL,          -- quem publicou (Inmetro, Cemig...)
    tipo_fonte    TEXT NOT NULL,          -- oficial | distribuidora
    url           TEXT NOT NULL,          -- link de origem (regra: toda fonte registrada)
    arquivo       TEXT NOT NULL,          -- arquivo em datasets/raw/rag/
    secao         TEXT,                   -- ex.: GELADEIRA / FREEZER
    pagina        INTEGER,                -- so para PDF
    texto         TEXT NOT NULL,
    embedding     vector({DIMENSION}) NOT NULL,
    carregado_em  TIMESTAMP NOT NULL DEFAULT now()
);
"""


@lru_cache(maxsize=1)
def _client():
    key = config._ENV.get("GEMINI_API_KEY")
    if not key:
        raise RuntimeError("GEMINI_API_KEY não configurada no .env")
    from google import genai  # import aqui: so quando precisa
    return genai.Client(api_key=key)


def vectorize(texts, task="RETRIEVAL_QUERY"):
    """Lista de textos -> lista de vetores (listas de float).

    task: RETRIEVAL_DOCUMENT na carga dos trechos, RETRIEVAL_QUERY na busca (o Gemini ajusta o vetor ao uso).
    Falha do Gemini vira RuntimeError: a API responde 503 (Eco-Coach indisponivel), nao 500.
    """
    from google.genai import types

    texts = list(texts)
    config_embedding = types.EmbedContentConfig(task_type=task, output_dimensionality=DIMENSION)
    vectors = []
    try:
        for start in range(0, len(texts), BATCH):
            response = _client().models.embed_content(
                model=EMBEDDING_MODEL, contents=texts[start:start + BATCH], config=config_embedding)
            vectors += [list(e.values) for e in response.embeddings]
    except RuntimeError:
        raise
    except Exception as error:  # limite do plano gratuito, rede, modelo fora do ar
        raise RuntimeError(f"embeddings indisponiveis ({type(error).__name__})") from error
    return vectors


@lru_cache(maxsize=512)
def _question_vector(question):
    """As buscas se repetem muito (dicas do chuveiro, da geladeira...): cada pergunta vai uma vez so."""
    return tuple(vectorize([question])[0])


def literal_vector(vector):
    """Formato que o pgvector aceita: '[0.1,0.2,...]' (passado como parametro, nunca concatenado)."""
    return "[" + ",".join(f"{x:.6f}" for x in vector) + "]"


def base_loaded(con):
    sql = "SELECT to_regclass('public.trechos_rag') IS NOT NULL"
    if not banco.run(con, sql).scalar_one():
        return False
    return banco.run(con, "SELECT COUNT(*) FROM trechos_rag").scalar_one() > 0


def search_chunks(con, question, k=5):
    """Os k trechos mais parecidos com a pergunta (distancia de cosseno do pgvector)."""
    vector = literal_vector(_question_vector(question))
    sql = ("SELECT documento, orgao, url, secao, pagina, texto, "
           "1 - (embedding <=> CAST(? AS vector)) AS similaridade "
           "FROM trechos_rag ORDER BY embedding <=> CAST(? AS vector) LIMIT ?")
    return banco.query(con, sql, (vector, vector, k)).to_dict("records")
