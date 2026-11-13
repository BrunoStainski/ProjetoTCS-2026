"""
Cria (ou recria) as tabelas no PostgreSQL a partir dos CSVs limpos.
Antes: docker compose up -d (na raiz do projeto).

Uso:
  python criar_banco.py               cria o banco e mostra um resumo
  python criar_banco.py --exemplos    tambem roda as consultas de consultas_exemplo.sql

As tabelas de dados sao recriadas a cada execucao.
A tabela consultas (historico do app) e mantida.
"""

import argparse
import hashlib
from pathlib import Path

import pandas as pd

import config
import banco
from banco import SCHEMA
import calculadora_residencial
import tarifas_aneel
from calculadora_residencial import SPECS, load_catalog, normalize
from tarifas_aneel import read_residential_tariffs

QUERIES_SQL = Path(__file__).resolve().parent / "consultas_exemplo.sql"

APPLIANCE_COLUMNS = [
    "categoria", "marca", "modelo", "tipo", "capacidade", "unidade", "detalhe", "tensao",
    "kwh_mes", "kwh_mes_baixa", "kwh_mes_media", "kwh_mes_alta", "kwh_ciclo",
    "potencia_w", "standby_kwh_mes", "fluxo_lm", "origem_dado", "arquivo_origem", "busca",
]


def catalog_files():
    """Tudo o que decide o conteudo das tabelas de dados: os CSVs carregados e o codigo que monta o catalogo."""
    data = [config.DATA / s["arquivo"] for s in SPECS] + [SMALL_APPLIANCES_CSV, config.TARIFFS_CSV, config.DISTRIBUTORS_CSV]
    code = [Path(__file__), Path(calculadora_residencial.__file__), Path(tarifas_aneel.__file__),
            config.ROOT / "models" / "refrigerador.pkl"]  # conversao das geladeiras da metodologia antiga
    return [p for p in data + code if p.exists()]


def catalog_fingerprint(files=None):
    """Impressao digital do catalogo, gravada em `cargas` a cada carga. A API compara na subida e recarrega o banco
    quando um CSV ou a regra de montagem mudou. Antes so recarregava com coluna nova: mudar o conteudo (limpeza
    refeita, tensao de cada modelo) nao chegava ao banco da nuvem."""
    digest = hashlib.sha256()
    for path in sorted(files if files is not None else catalog_files(), key=lambda p: p.name):
        digest.update(path.name.encode() + b"|" + path.read_bytes().replace(b"\r\n", b"\n"))
    return "catalogo:" + digest.hexdigest()[:16]


def _uf_valid(value):
    uf = str(value).strip().upper() if pd.notna(value) else ""
    return uf if len(uf) == 2 and uf.isalpha() else None


def load_appliances(con):
    catalog = load_catalog().rename(columns={"arquivo": "arquivo_origem"})
    catalog[APPLIANCE_COLUMNS].to_sql("aparelhos", con, if_exists="append", index=False)
    for file, lines in catalog["arquivo_origem"].value_counts().sort_index().items():
        banco.run(con, "INSERT INTO cargas (arquivo, linhas) VALUES (?, ?)", (file, int(lines)))
    banco.run(con, "INSERT INTO cargas (arquivo, linhas) VALUES (?, ?)", (catalog_fingerprint(), len(catalog)))
    return len(catalog)


SMALL_APPLIANCES_CSV = config.DATA / "eletroportateis.csv"


def _register_load(con, file, lines):
    banco.run(con, "INSERT INTO cargas (arquivo, linhas) VALUES (?, ?)", (file, int(lines)))


def load_small_appliances(con):
    df = pd.read_csv(SMALL_APPLIANCES_CSV, encoding="utf-8-sig")
    df[["categoria", "nome", "potencia_w", "horas_dia", "dias_mes", "fonte"]].to_sql(
        "portateis", con, if_exists="append", index=False)
    _register_load(con, SMALL_APPLIANCES_CSV.name, len(df))
    return len(df)


def load_extra_data(con):
    return {"portateis": load_small_appliances(con)}


def _text(value):
    return str(value).strip() if pd.notna(value) and str(value).strip() else None


def read_ufs():
    """distribuidoras_uf.csv -> {nome normalizado: (nome, uf, fonte da uf, tarifa, vigencia, fonte tarifa)}."""
    if not config.DISTRIBUTORS_CSV.exists():
        print(f"[aviso] {config.DISTRIBUTORS_CSV.name} nao encontrado: distribuidoras ficam sem UF")
        return {}
    df = pd.read_csv(config.DISTRIBUTORS_CSV, encoding="utf-8-sig", dtype=str)
    df.columns = [c.strip().lower() for c in df.columns]
    name = "distribuidora" if "distribuidora" in df.columns else df.columns[0]
    return {
        normalize(l[name]): {
            "nome": l[name].strip(), "uf": _uf_valid(l.get("uf")), "fonte_uf": _text(l.get("base")),
            "tarifa_kwh": _text(l.get("tarifa_kwh")), "vigencia_inicio": _text(l.get("vigencia_inicio")),
            "fonte": _text(l.get("fonte_tarifa")),
        }
        for l in df.to_dict("records") if _text(l.get(name))
    }


def load_distributors_and_tariffs(con):
    ufs = read_ufs()

    # Tarifas: do tarifas_aneel_limpo.csv; sem ele, da coluna tarifa_kwh do distribuidoras_uf.csv
    if config.TARIFFS_CSV.exists():
        tariffs = read_residential_tariffs(config.TARIFFS_CSV)
        origin = config.TARIFFS_CSV.name
    else:
        print(f"[aviso] {config.TARIFFS_CSV.name} nao encontrado, usando tarifa_kwh do distribuidoras_uf.csv")
        tariffs = pd.DataFrame(
            [{"nome": d["nome"], "tarifa_kwh": pd.to_numeric(str(d["tarifa_kwh"]).replace(",", "."), errors="coerce"),
              "vigencia_inicio": d["vigencia_inicio"], "fonte": d["fonte"] or config.DISTRIBUTORS_CSV.name}
             for d in ufs.values() if d["tarifa_kwh"]],
            columns=["nome", "tarifa_kwh", "vigencia_inicio", "fonte"],
        )
        origin = config.DISTRIBUTORS_CSV.name
    tariffs = tariffs[tariffs["tarifa_kwh"] > 0]

    # Distribuidoras: todas que aparecem em qualquer um dos dois arquivos
    names = {}
    for name in tariffs["nome"]:
        names.setdefault(normalize(name), name)
    for key, item in ufs.items():
        names.setdefault(key, item["nome"])

    ids = {}
    for key, name in sorted(names.items()):
        item = ufs.get(key, {})
        ids[key] = banco.run(
            con, "INSERT INTO distribuidoras (nome, uf, fonte_uf) VALUES (?, ?, ?) RETURNING id",
            (name, item.get("uf"), item.get("fonte_uf")),
        ).scalar_one()

    for line in tariffs.to_dict("records"):
        banco.run(
            con, "INSERT INTO tarifas (distribuidora_id, tarifa_kwh, vigencia_inicio, fonte) VALUES (?, ?, ?, ?)",
            (ids[normalize(line["nome"])], float(line["tarifa_kwh"]),
             _text(line["vigencia_inicio"]), line["fonte"]),
        )

    banco.run(con, "INSERT INTO cargas (arquivo, linhas) VALUES (?, ?)", (origin, len(tariffs)))
    if ufs and origin != config.DISTRIBUTORS_CSV.name:
        banco.run(con, "INSERT INTO cargas (arquivo, linhas) VALUES (?, ?)", (config.DISTRIBUTORS_CSV.name, len(ufs)))
    return len(names), len(tariffs)


def run_examples(con):
    if not QUERIES_SQL.exists():
        print(f"{QUERIES_SQL.name} nao encontrado")
        return
    blocks = [b.strip() for b in QUERIES_SQL.read_text(encoding="utf-8").split(";") if b.strip()]
    for block in blocks:
        title = next((l.lstrip("- ").strip() for l in block.splitlines() if l.startswith("--")), "consulta")
        print(f"\n=== {title}")
        result = banco.query(con, block)
        print("(sem linhas)" if result.empty else result.to_string(index=False))


def main():
    parser = argparse.ArgumentParser(description="Cria as tabelas do iamp no PostgreSQL")
    parser.add_argument("--exemplos", action="store_true", help="roda as consultas de exemplo no final")
    args = parser.parse_args()

    try:
        con = banco.connect()
    except ConnectionError as error:
        print(f"Erro: {error}")
        raise SystemExit(1)
    try:
        con.exec_driver_sql(SCHEMA)
        n_appliances = load_appliances(con)
        n_dist, n_tariffs = load_distributors_and_tariffs(con)
        extra = load_extra_data(con)
        con.commit()
    except Exception:
        con.rollback()
        raise

    def count(sql):
        return banco.run(con, sql).scalar_one()

    without_uf = count("SELECT COUNT(*) FROM distribuidoras WHERE uf IS NULL")
    n_queries = count("SELECT COUNT(*) FROM consultas")
    with_tariff = count("SELECT COUNT(*) FROM vw_tarifa_vigente")
    print(f"Banco criado: {con.engine.url.render_as_string(hide_password=True)}")
    print(f"  aparelhos:      {n_appliances}")
    print(f"  distribuidoras: {n_dist} ({without_uf} sem UF, {with_tariff} com tarifa vigente)")
    print(f"  tarifas:        {n_tariffs} (incluindo vigencias antigas)")
    print(f"  consultas:      {n_queries} (historico mantido)")
    print(f"  portateis:      {extra['portateis']}")

    if args.exemplos:
        run_examples(con)
    con.close()


if __name__ == "__main__":
    main()
