"""
Base vetorial do Eco-Coach (RAG): trechos de documentos oficiais guardados no PostgreSQL
com a extensao pgvector.

- Embeddings LOCAIS (fastembed, modelo multilingue pequeno, sem torch): nenhum texto sai do
  computador para gerar os vetores, e nao depende de credito em API.
- Os trechos vem de documentos publicos (Inmetro, Cemig); nada do usuario e gravado aqui.
- Carga: scripts/carregar_rag.py (le datasets/raw/rag/ e o fontes.csv com a origem de cada um).
"""

from functools import lru_cache

import banco
import config

MODELO_EMBEDDING = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
DIMENSAO = 384
PASTA_MODELOS = config.RAIZ / "models" / "fastembed"  # cache do modelo (fora do git)

ESQUEMA_RAG = f"""
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
    embedding     vector({DIMENSAO}) NOT NULL,
    carregado_em  TIMESTAMP NOT NULL DEFAULT now()
);
"""


@lru_cache(maxsize=1)
def modelo():
    from fastembed import TextEmbedding  # import aqui: so carrega o modelo quando precisa
    PASTA_MODELOS.mkdir(parents=True, exist_ok=True)
    return TextEmbedding(MODELO_EMBEDDING, cache_dir=str(PASTA_MODELOS))


def vetorizar(textos):
    """Lista de textos -> lista de vetores (listas de float)."""
    return [v.tolist() for v in modelo().embed(list(textos))]


def literal_vetor(vetor):
    """Formato que o pgvector aceita: '[0.1,0.2,...]' (passado como parametro, nunca concatenado)."""
    return "[" + ",".join(f"{x:.6f}" for x in vetor) + "]"


def base_carregada(con):
    sql = "SELECT to_regclass('public.trechos_rag') IS NOT NULL"
    if not banco.executar(con, sql).scalar_one():
        return False
    return banco.executar(con, "SELECT COUNT(*) FROM trechos_rag").scalar_one() > 0


def buscar_trechos(con, pergunta, k=5):
    """Os k trechos mais parecidos com a pergunta (distancia de cosseno do pgvector)."""
    vetor = literal_vetor(vetorizar([pergunta])[0])
    sql = ("SELECT documento, orgao, url, secao, pagina, texto, "
           "1 - (embedding <=> CAST(? AS vector)) AS similaridade "
           "FROM trechos_rag ORDER BY embedding <=> CAST(? AS vector) LIMIT ?")
    return banco.consulta(con, sql, (vetor, vetor, k)).to_dict("records")
