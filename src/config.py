"""
Caminhos e conexao do projeto iamp. Se algo mudar, ajuste so aqui.

Por padrao procura a pasta "datasets" subindo a partir deste arquivo, entao funciona
com o codigo na raiz do projeto ou dentro de src/.
As credenciais do PostgreSQL vem do .env da raiz (o mesmo que o docker-compose usa).
Da para trocar pelas variaveis de ambiente IAMP_DADOS e DATABASE_URL.
"""

import os
from pathlib import Path


def _raiz():
    aqui = Path(__file__).resolve().parent
    for pasta in (aqui, *aqui.parents):
        if (pasta / "datasets").is_dir():
            return pasta
    return aqui


def _ler_env(caminho):
    """Le o .env (CHAVE=valor) sem precisar de biblioteca extra."""
    valores = {}
    if caminho.exists():
        for linha in caminho.read_text(encoding="utf-8-sig").splitlines():
            linha = linha.strip()
            if linha and not linha.startswith("#") and "=" in linha:
                chave, valor = linha.split("=", 1)
                valores[chave.strip()] = valor.strip().strip('"').strip("'")
    return valores


RAIZ = _raiz()
_ENV = {**_ler_env(RAIZ / ".env"), **os.environ}  # variavel de ambiente vence o .env


def _env(chave, padrao=None):
    return _ENV.get(chave) or padrao


DADOS = Path(_env("IAMP_DADOS", RAIZ / "datasets" / "processed"))
TARIFAS_CSV = DADOS / "tarifas_aneel_limpo.csv"

# PostgreSQL do docker-compose (container postgres_iamp)
DATABASE_URL = _env("DATABASE_URL") or "postgresql+psycopg2://{u}:{s}@{h}:{p}/{d}".format(
    u=_env("POSTGRES_USER", "admin"),
    s=_env("POSTGRES_PASSWORD", ""),
    h=_env("POSTGRES_HOST", "localhost"),
    p=_env("POSTGRES_PORT", "5434"),
    d=_env("POSTGRES_DB", "banco_projeto"),
)


def _achar(nome):
    for pasta in (DADOS, RAIZ / "datasets", RAIZ / "datasets" / "raw", RAIZ):
        if (pasta / nome).exists():
            return pasta / nome
    return DADOS / nome


DISTRIBUIDORAS_CSV = _achar("distribuidoras_uf.csv")
