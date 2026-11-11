"""Caminhos e utilitários compartilhados pelos scripts de tratamento de dados.

Todos os scripts leem de datasets/raw e escrevem em datasets/processed,
independente da pasta de onde forem executados.
"""

import os
import re
import unicodedata
from pathlib import Path

import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parent.parent
RAW_FOLDER = PROJECT_ROOT / "datasets" / "raw"
PROCESSED_FOLDER = PROJECT_ROOT / "datasets" / "processed"


def load_env() -> None:
    """Carrega variáveis do arquivo .env da raiz (sem sobrescrever as já definidas)."""
    env_file = PROJECT_ROOT / ".env"
    if not env_file.exists():
        return
    for line in env_file.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def database_url() -> str:
    """Monta a URL do PostgreSQL a partir das variáveis de ambiente."""
    load_env()
    if os.getenv("DATABASE_URL"):
        return os.environ["DATABASE_URL"]
    user = os.environ["POSTGRES_USER"]
    password = os.environ["POSTGRES_PASSWORD"]
    database = os.environ["POSTGRES_DB"]
    host = os.getenv("POSTGRES_HOST", "localhost")
    port = os.getenv("POSTGRES_PORT", "5434")
    return f"postgresql+psycopg2://{user}:{password}@{host}:{port}/{database}"


def raw_path(file_name: str) -> Path:
    path = RAW_FOLDER / file_name
    if not path.is_file():
        raise FileNotFoundError(f"Arquivo bruto não encontrado: {path}")
    return path


def read_csv_inmetro(file_name: str) -> pd.DataFrame:
    """Lê um CSV bruto do INMETRO (UTF-8 com BOM, separador vírgula)."""
    return pd.read_csv(raw_path(file_name), encoding="utf-8-sig")


def filter_included_models(df: pd.DataFrame, column: str = "Status do Modelo") -> pd.DataFrame:
    """Mantém apenas modelos com status 'Incluido' (os demais saíram do programa PBE)."""
    if column not in df.columns:
        return df
    status = df[column].astype(str).str.strip().str.lower()
    return df[status == "incluido"].copy()


def to_snake_case(name: str) -> str:
    """'Potência (W)' -> 'potencia_w'; 'Eficiência (%)' -> 'eficiencia_pct'."""
    name = name.replace("﻿", "").replace("%", " pct ").replace("²", "2").replace("³", "3")
    name = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode("ascii")
    name = re.sub(r"[^0-9a-zA-Z]+", "_", name).strip("_").lower()
    return re.sub(r"_+", "_", name)


def save_processed(df: pd.DataFrame, file_name: str) -> Path:
    """Padroniza colunas em snake_case e salva em datasets/processed (UTF-8, vírgula)."""
    df = df.copy()
    df.columns = [to_snake_case(str(c)) for c in df.columns]
    PROCESSED_FOLDER.mkdir(parents=True, exist_ok=True)
    path = PROCESSED_FOLDER / file_name
    df.to_csv(path, index=False, encoding="utf-8")
    print(f"✓ {len(df)} linhas salvas em: {path}")
    return path
