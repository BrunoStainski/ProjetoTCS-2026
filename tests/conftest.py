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


def aparelho(categoria, **valores):
    """Aparelho de teste com todas as colunas do catalogo (NaN no que nao foi informado)."""
    colunas = ["kwh_mes", "kwh_mes_baixa", "kwh_mes_media", "kwh_mes_alta",
               "kwh_ciclo", "potencia_w", "standby_kwh_mes"]
    base = {c: math.nan for c in colunas}
    base.update({"categoria": categoria, "marca": "TESTE", "modelo": "M1",
                 "detalhe": "", "origem_dado": "informado"})
    base.update(valores)
    return base


@pytest.fixture(scope="session")
def banco_disponivel():
    """True se o PostgreSQL responde e ja tem os dados carregados."""
    try:
        con = banco.conectar()
    except ConnectionError:
        return False
    try:
        return banco.executar(con, "SELECT COUNT(*) FROM aparelhos").scalar_one() > 0
    except Exception:
        return False
    finally:
        con.close()


@pytest.fixture
def con(banco_disponivel):
    if not banco_disponivel:
        pytest.skip("PostgreSQL fora do ar ou vazio (rode: docker compose up -d)")
    conexao = banco.conectar()
    yield conexao
    conexao.close()


@pytest.fixture(scope="session")
def client():
    """Cliente da API. Sem 'with', o lifespan (que espera o banco) nao roda."""
    from fastapi.testclient import TestClient

    import main
    return TestClient(main.app)


@pytest.fixture
def api(client, banco_disponivel):
    """Cliente da API para rotas que leem o banco."""
    if not banco_disponivel:
        pytest.skip("PostgreSQL fora do ar ou vazio (rode: docker compose up -d)")
    return client
