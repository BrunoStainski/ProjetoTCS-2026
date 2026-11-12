"""
Configuracao comum dos testes.

Rodar (na raiz, com o .venv ativo):
  pytest                 # tudo; testes de banco sao pulados se o PostgreSQL nao estiver no ar
  pytest -m "not banco"  # so os que nao precisam de banco (rapidos)
  pytest -m banco        # so os de banco (antes: docker compose up -d)
"""

import math
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

import banco  # noqa: E402


def appliance(category, **values):
    """Aparelho de teste com todas as colunas do catalogo (NaN no que nao foi informado)."""
    columns = ["kwh_mes", "kwh_mes_baixa", "kwh_mes_media", "kwh_mes_alta",
               "kwh_ciclo", "potencia_w", "standby_kwh_mes"]
    base = {c: math.nan for c in columns}
    base.update({"categoria": category, "marca": "TESTE", "modelo": "M1",
                 "detalhe": "", "origem_dado": "informado"})
    base.update(values)
    return base


@pytest.fixture(scope="session")
def database_available():
    """True se o PostgreSQL responde e ja tem os dados carregados."""
    try:
        con = banco.connect()
    except ConnectionError:
        return False
    try:
        return banco.run(con, "SELECT COUNT(*) FROM aparelhos").scalar_one() > 0
    except Exception:
        return False
    finally:
        con.close()


@pytest.fixture
def con(database_available):
    if not database_available:
        pytest.skip("PostgreSQL fora do ar ou vazio (rode: docker compose up -d)")
    connection = banco.connect()
    yield connection
    connection.close()


@pytest.fixture(scope="session")
def client():
    """Cliente da API. Sem 'with', o lifespan (que espera o banco) nao roda."""
    from fastapi.testclient import TestClient

    import main
    return TestClient(main.app)


@pytest.fixture
def api(client, database_available):
    """Cliente da API para rotas que leem o banco."""
    if not database_available:
        pytest.skip("PostgreSQL fora do ar ou vazio (rode: docker compose up -d)")
    return client
