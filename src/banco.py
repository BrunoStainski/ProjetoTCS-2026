"""
Acesso ao PostgreSQL do iamp (container postgres_iamp do docker-compose), via SQLAlchemy.
Todas as consultas usam parametros e nunca montam SQL com texto do usuario.
"""

import pandas as pd
from sqlalchemy import create_engine, text
from sqlalchemy.exc import OperationalError

import config

ESQUEMA = """
-- Tabelas de dados: recriadas a cada carga (vem dos CSVs limpos).
DROP VIEW IF EXISTS vw_tarifa_vigente;
DROP TABLE IF EXISTS tarifas;
DROP TABLE IF EXISTS distribuidoras;
DROP TABLE IF EXISTS aparelhos;
DROP TABLE IF EXISTS cargas;

CREATE TABLE aparelhos (
    id              SERIAL PRIMARY KEY,
    categoria       TEXT NOT NULL,
    marca           TEXT NOT NULL,
    modelo          TEXT NOT NULL,
    tipo            TEXT,
    capacidade      DOUBLE PRECISION,  -- litros, polegadas, BTU/h, W, kg ou cv
    unidade         TEXT,
    detalhe         TEXT,              -- texto pronto para a tela, ex.: "375 L"
    kwh_mes         DOUBLE PRECISION,
    kwh_mes_baixa   DOUBLE PRECISION,
    kwh_mes_media   DOUBLE PRECISION,
    kwh_mes_alta    DOUBLE PRECISION,
    kwh_ciclo       DOUBLE PRECISION,
    potencia_w      DOUBLE PRECISION,
    standby_kwh_mes DOUBLE PRECISION,
    origem_dado     TEXT NOT NULL,     -- "informado" ou "derivado ou estimado na limpeza"
    arquivo_origem  TEXT NOT NULL,
    busca           TEXT NOT NULL,     -- marca + modelo sem acento, minusculo
    UNIQUE (categoria, marca, modelo),
    CHECK (kwh_mes IS NOT NULL OR kwh_ciclo IS NOT NULL OR potencia_w IS NOT NULL)
);
CREATE INDEX idx_aparelhos_categoria ON aparelhos (categoria, busca);

CREATE TABLE distribuidoras (
    id       SERIAL PRIMARY KEY,
    nome     TEXT NOT NULL UNIQUE,
    uf       CHAR(2),
    fonte_uf TEXT
);

CREATE TABLE tarifas (
    id               SERIAL PRIMARY KEY,
    distribuidora_id INTEGER NOT NULL REFERENCES distribuidoras (id),
    classe           TEXT NOT NULL DEFAULT 'residencial_b1',
    tarifa_kwh       DOUBLE PRECISION NOT NULL CHECK (tarifa_kwh > 0),
    vigencia_inicio  DATE,
    fonte            TEXT NOT NULL,
    UNIQUE (distribuidora_id, classe, vigencia_inicio)
);

-- Rastreabilidade: de qual arquivo veio cada dado e quando foi carregado.
CREATE TABLE cargas (
    id           SERIAL PRIMARY KEY,
    arquivo      TEXT NOT NULL,
    linhas       INTEGER NOT NULL,
    carregado_em TIMESTAMP NOT NULL DEFAULT now()
);

-- Tarifa que vale hoje para cada distribuidora (a vigencia mais recente ja iniciada).
CREATE VIEW vw_tarifa_vigente AS
SELECT DISTINCT ON (d.id)
       d.id AS distribuidora_id, d.nome AS distribuidora, d.uf,
       t.tarifa_kwh, t.vigencia_inicio, t.fonte
FROM distribuidoras d
JOIN tarifas t ON t.distribuidora_id = d.id AND t.classe = 'residencial_b1'
WHERE t.vigencia_inicio IS NULL OR t.vigencia_inicio <= CURRENT_DATE
ORDER BY d.id, t.vigencia_inicio DESC NULLS LAST;

-- Historico de uso do app: NAO e apagado quando os dados sao recarregados.
-- Guarda o nome do aparelho (e nao o id) para o historico continuar valido
-- mesmo se o catalogo mudar. Nao guarda nenhum dado pessoal do usuario.
CREATE TABLE IF NOT EXISTS consultas (
    id            SERIAL PRIMARY KEY,
    criado_em     TIMESTAMP NOT NULL DEFAULT now(),
    categoria     TEXT NOT NULL,
    marca         TEXT NOT NULL,
    modelo        TEXT NOT NULL,
    uf            TEXT NOT NULL,
    distribuidora TEXT,
    horas_dia     DOUBLE PRECISION,
    ciclos_mes    DOUBLE PRECISION,
    velocidade    TEXT,
    kwh_mes       DOUBLE PRECISION NOT NULL,
    metodo        TEXT NOT NULL,
    tarifa_kwh    DOUBLE PRECISION NOT NULL,
    origem_tarifa TEXT NOT NULL,
    custo_mes     DOUBLE PRECISION NOT NULL
);
"""

_engine = None


def engine():
    global _engine
    if _engine is None:
        _engine = create_engine(config.DATABASE_URL, pool_pre_ping=True)
    return _engine


def conectar():
    """Abre uma conexao. Feche com con.close() (ou use 'with conectar() as con')."""
    try:
        return engine().connect()
    except OperationalError as erro:
        raise ConnectionError(
            "nao consegui conectar no PostgreSQL. O container esta rodando? "
            "(docker compose up -d) e o .env esta preenchido?\n"
            f"Detalhe: {erro.orig}"
        ) from None


def _nomear(sql, params):
    """Troca cada ? por :p0, :p1... (formato do SQLAlchemy) e monta o dicionario."""
    partes = sql.split("?")
    if len(partes) - 1 != len(params):
        raise ValueError("numero de ? diferente do numero de parametros")
    novo = partes[0] + "".join(f":p{i}{parte}" for i, parte in enumerate(partes[1:]))
    return text(novo), {f"p{i}": v for i, v in enumerate(params)}


def consulta(con, sql, params=()):
    """SELECT -> DataFrame. Use ? no lugar de cada parametro."""
    sql, valores = _nomear(sql, params)
    return pd.read_sql_query(sql, con, params=valores)


def executar(con, sql, params=()):
    sql, valores = _nomear(sql, params)
    return con.execute(sql, valores)


def categorias(con):
    return consulta(con, "SELECT DISTINCT categoria FROM aparelhos ORDER BY 1")["categoria"].tolist()


def buscar_aparelhos(con, categoria, alvo, limite):
    """alvo ja vem normalizado. Devolve (match exato, match por termos)."""
    exato = consulta(con, "SELECT * FROM aparelhos WHERE categoria = ? AND busca = ?", (categoria, alvo))
    termos = alvo.split()
    if not termos:
        return exato, exato.head(0)
    # normalizar() so deixa letras, numeros e espaco, entao % e _ nunca aparecem nos termos
    filtro = " AND ".join("busca LIKE ?" for _ in termos)
    resultados = consulta(
        con,
        f"SELECT * FROM aparelhos WHERE categoria = ? AND {filtro} ORDER BY marca, modelo LIMIT ?",
        (categoria, *[f"%{t}%" for t in termos], limite),
    )
    return exato, resultados


def distribuidoras_com_tarifa(con):
    return consulta(
        con,
        """
        SELECT d.id AS distribuidora_id, d.nome AS distribuidora, d.uf,
               v.tarifa_kwh, v.vigencia_inicio, v.fonte AS fonte_tarifa
        FROM distribuidoras d
        LEFT JOIN vw_tarifa_vigente v ON v.distribuidora_id = d.id
        WHERE d.uf IS NOT NULL
        """,
    )


def registrar_consulta(con, r, horas_dia=None, ciclos_mes=None, velocidade=None):
    executar(
        con,
        """
        INSERT INTO consultas (categoria, marca, modelo, uf, distribuidora, horas_dia, ciclos_mes,
                               velocidade, kwh_mes, metodo, tarifa_kwh, origem_tarifa, custo_mes)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (r["categoria"], r["marca"], r["modelo"], r["uf"],
         None if r["distribuidora"] == "-" else r["distribuidora"],
         horas_dia, ciclos_mes, velocidade, r["kwh_mes"], r["metodo"],
         r["tarifa_kwh"], r["origem_tarifa"], r["custo_mes"]),
    )
    con.commit()
