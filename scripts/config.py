"""Caminhos e utilitários compartilhados pelos scripts de tratamento de dados.

Todos os scripts leem de datasets/raw e escrevem em datasets/processed,
independente da pasta de onde forem executados.
"""

import os
import re
import unicodedata
from pathlib import Path

import pandas as pd

RAIZ_PROJETO = Path(__file__).resolve().parent.parent
PASTA_RAW = RAIZ_PROJETO / "datasets" / "raw"
PASTA_PROCESSED = RAIZ_PROJETO / "datasets" / "processed"


def carregar_env() -> None:
    """Carrega variáveis do arquivo .env da raiz (sem sobrescrever as já definidas)."""
    arquivo_env = RAIZ_PROJETO / ".env"
    if not arquivo_env.exists():
        return
    for linha in arquivo_env.read_text(encoding="utf-8").splitlines():
        linha = linha.strip()
        if not linha or linha.startswith("#") or "=" not in linha:
            continue
        chave, valor = linha.split("=", 1)
        os.environ.setdefault(chave.strip(), valor.strip().strip('"').strip("'"))


def database_url() -> str:
    """Monta a URL do PostgreSQL a partir das variáveis de ambiente."""
    carregar_env()
    if os.getenv("DATABASE_URL"):
        return os.environ["DATABASE_URL"]
    usuario = os.environ["POSTGRES_USER"]
    senha = os.environ["POSTGRES_PASSWORD"]
    banco = os.environ["POSTGRES_DB"]
    host = os.getenv("POSTGRES_HOST", "localhost")
    porta = os.getenv("POSTGRES_PORT", "5434")
    return f"postgresql+psycopg2://{usuario}:{senha}@{host}:{porta}/{banco}"


def caminho_raw(nome_arquivo: str) -> Path:
    caminho = PASTA_RAW / nome_arquivo
    if not caminho.is_file():
        raise FileNotFoundError(f"Arquivo bruto não encontrado: {caminho}")
    return caminho


def ler_csv_inmetro(nome_arquivo: str) -> pd.DataFrame:
    """Lê um CSV bruto do INMETRO (UTF-8 com BOM, separador vírgula)."""
    return pd.read_csv(caminho_raw(nome_arquivo), encoding="utf-8-sig")


def filtrar_modelos_incluidos(df: pd.DataFrame, coluna: str = "Status do Modelo") -> pd.DataFrame:
    """Mantém apenas modelos com status 'Incluido' (os demais saíram do programa PBE)."""
    if coluna not in df.columns:
        return df
    status = df[coluna].astype(str).str.strip().str.lower()
    return df[status == "incluido"].copy()


def para_snake_case(nome: str) -> str:
    """'Potência (W)' -> 'potencia_w'; 'Eficiência (%)' -> 'eficiencia_pct'."""
    nome = nome.replace("﻿", "").replace("%", " pct ").replace("²", "2").replace("³", "3")
    nome = unicodedata.normalize("NFKD", nome).encode("ascii", "ignore").decode("ascii")
    nome = re.sub(r"[^0-9a-zA-Z]+", "_", nome).strip("_").lower()
    return re.sub(r"_+", "_", nome)


def salvar_processado(df: pd.DataFrame, nome_arquivo: str) -> Path:
    """Padroniza colunas em snake_case e salva em datasets/processed (UTF-8, vírgula)."""
    df = df.copy()
    df.columns = [para_snake_case(str(c)) for c in df.columns]
    PASTA_PROCESSED.mkdir(parents=True, exist_ok=True)
    caminho = PASTA_PROCESSED / nome_arquivo
    df.to_csv(caminho, index=False, encoding="utf-8")
    print(f"✓ {len(df)} linhas salvas em: {caminho}")
    return caminho
