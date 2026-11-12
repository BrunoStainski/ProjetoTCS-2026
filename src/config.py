"""
Caminhos e conexao do projeto iamp. Se algo mudar, ajuste so aqui.

Por padrao procura a pasta "datasets" subindo a partir deste arquivo, entao funciona
com o codigo na raiz do projeto ou dentro de src/.
As credenciais do PostgreSQL vem do .env da raiz (o mesmo que o docker-compose usa).
Da para trocar pelas variaveis de ambiente IAMP_DADOS e DATABASE_URL.
"""

import os
from pathlib import Path


def _root():
    here = Path(__file__).resolve().parent
    for folder in (here, *here.parents):
        if (folder / "datasets").is_dir():
            return folder
    return here


def _read_env(path):
    """Le o .env (CHAVE=valor) sem precisar de biblioteca extra."""
    values = {}
    if path.exists():
        for line in path.read_text(encoding="utf-8-sig").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                values[key.strip()] = value.strip().strip('"').strip("'")
    return values


ROOT = _root()
# Variavel de ambiente vence o .env. O strip tira espaco ou Enter colado junto no painel da nuvem:
# com ele a chave do Gemini virava cabecalho HTTP invalido (LocalProtocolError) e o Eco-Coach nao carregava.
_ENV = {**_read_env(ROOT / ".env"), **{k: v.strip() for k, v in os.environ.items()}}


def _env(key, default_value=None):
    return _ENV.get(key) or default_value


DATA = Path(_env("IAMP_DADOS", ROOT / "datasets" / "processed"))
TARIFFS_CSV = DATA / "tarifas_aneel_limpo.csv"

# PostgreSQL do docker-compose (container postgres_iamp)
DATABASE_URL = _env("DATABASE_URL") or "postgresql+psycopg2://{u}:{s}@{h}:{p}/{d}".format(
    u=_env("POSTGRES_USER", "admin"),
    s=_env("POSTGRES_PASSWORD", ""),
    h=_env("POSTGRES_HOST", "localhost"),
    p=_env("POSTGRES_PORT", "5434"),
    d=_env("POSTGRES_DB", "banco_projeto"),
)
# Neon/Render entregam "postgresql://..." (ou "postgres://"); o SQLAlchemy 2.1 usa o driver psycopg 3
# nesse formato, e o projeto usa o psycopg2: troca para o driver certo (o resto, como ?sslmode=require, fica).
for _prefix in ("postgres://", "postgresql://"):
    if DATABASE_URL.startswith(_prefix):
        DATABASE_URL = "postgresql+psycopg2://" + DATABASE_URL[len(_prefix):]


def _find(name):
    for folder in (DATA, ROOT / "datasets", ROOT / "datasets" / "raw", ROOT):
        if (folder / name).exists():
            return folder / name
    return DATA / name


DISTRIBUTORS_CSV = _find("distribuidoras_uf.csv")
