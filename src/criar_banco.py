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
from pathlib import Path

import pandas as pd

import config
import banco
from banco import ESQUEMA
from calculadora_residencial import carregar_catalogo, normalizar
from tarifas_aneel import ler_tarifas_residenciais

CONSULTAS_SQL = Path(__file__).resolve().parent / "consultas_exemplo.sql"

COLUNAS_APARELHOS = [
    "categoria", "marca", "modelo", "tipo", "capacidade", "unidade", "detalhe",
    "kwh_mes", "kwh_mes_baixa", "kwh_mes_media", "kwh_mes_alta", "kwh_ciclo",
    "potencia_w", "standby_kwh_mes", "fluxo_lm", "origem_dado", "arquivo_origem", "busca",
]


def _uf_valida(valor):
    uf = str(valor).strip().upper() if pd.notna(valor) else ""
    return uf if len(uf) == 2 and uf.isalpha() else None


def carregar_aparelhos(con):
    catalogo = carregar_catalogo().rename(columns={"arquivo": "arquivo_origem"})
    catalogo[COLUNAS_APARELHOS].to_sql("aparelhos", con, if_exists="append", index=False)
    for arquivo, linhas in catalogo["arquivo_origem"].value_counts().sort_index().items():
        banco.executar(con, "INSERT INTO cargas (arquivo, linhas) VALUES (?, ?)", (arquivo, int(linhas)))
    return len(catalogo)


PORTATEIS_CSV = config.DADOS / "eletroportateis.csv"
FOGOES_CSV = config.DADOS / "fogoes_fornos_gas_limpo.csv"
PRECO_GLP_CSV = config.DADOS / "preco_glp_uf_limpo.csv"
COLUNAS_FOGOES = {
    "marca": "marca", "modelo": "modelo", "tipo_de_produto": "tipo", "numerode_bocas": "bocas",
    "rendimento_medio_dos_queimadores_pct": "rendimento_pct", "volume_do_forno_litros": "forno_litros",
    "consumo_do_forno_glpkg_h_gnm3_h": "consumo_forno_kg_h", "classificacao_pbe_mesa_de_coccao": "classe_mesa",
    "classificacao_pbe_forno": "classe_forno",
}


def _registrar_carga(con, arquivo, linhas):
    banco.executar(con, "INSERT INTO cargas (arquivo, linhas) VALUES (?, ?)", (arquivo, int(linhas)))


def carregar_portateis(con):
    df = pd.read_csv(PORTATEIS_CSV, encoding="utf-8-sig")
    df[["categoria", "nome", "potencia_w", "horas_dia", "dias_mes", "fonte"]].to_sql(
        "portateis", con, if_exists="append", index=False)
    _registrar_carga(con, PORTATEIS_CSV.name, len(df))
    return len(df)


def carregar_fogoes(con):
    df = pd.read_csv(FOGOES_CSV, encoding="utf-8-sig")
    df = df[[c for c in COLUNAS_FOGOES if c in df.columns]].rename(columns=COLUNAS_FOGOES)
    df["marca"] = df["marca"].astype(str).str.strip()
    df["modelo"] = df["modelo"].astype(str).str.strip()
    df = df[(df["marca"] != "") & (df["modelo"] != "")].drop_duplicates(subset=["marca", "modelo"])
    df["bocas"] = pd.to_numeric(df["bocas"], errors="coerce").round().astype("Int64")
    df["detalhe"] = [
        ", ".join(p for p in (f"{b} bocas" if pd.notna(b) else "", f"forno {f:g} L" if pd.notna(f) else "") if p)
        for b, f in zip(df["bocas"], df["forno_litros"])
    ]
    df["busca"] = (df["marca"] + " " + df["modelo"]).map(normalizar)
    df.to_sql("fogoes", con, if_exists="append", index=False)
    _registrar_carga(con, FOGOES_CSV.name, len(df))
    return len(df)


def carregar_precos_glp(con):
    df = pd.read_csv(PRECO_GLP_CSV, encoding="utf-8-sig")
    df[["uf", "ano", "preco_kg", "fonte"]].to_sql("precos_glp", con, if_exists="append", index=False)
    _registrar_carga(con, PRECO_GLP_CSV.name, len(df))
    return len(df)


def carregar_dados_extras(con):
    return {"portateis": carregar_portateis(con), "fogoes": carregar_fogoes(con),
            "precos_glp": carregar_precos_glp(con)}


def _texto(valor):
    return str(valor).strip() if pd.notna(valor) and str(valor).strip() else None


def ler_ufs():
    """distribuidoras_uf.csv -> {nome normalizado: (nome, uf, fonte da uf, tarifa, vigencia, fonte tarifa)}."""
    if not config.DISTRIBUIDORAS_CSV.exists():
        print(f"[aviso] {config.DISTRIBUIDORAS_CSV.name} nao encontrado: distribuidoras ficam sem UF")
        return {}
    df = pd.read_csv(config.DISTRIBUIDORAS_CSV, encoding="utf-8-sig", dtype=str)
    df.columns = [c.strip().lower() for c in df.columns]
    nome = "distribuidora" if "distribuidora" in df.columns else df.columns[0]
    return {
        normalizar(l[nome]): {
            "nome": l[nome].strip(), "uf": _uf_valida(l.get("uf")), "fonte_uf": _texto(l.get("base")),
            "tarifa_kwh": _texto(l.get("tarifa_kwh")), "vigencia_inicio": _texto(l.get("vigencia_inicio")),
            "fonte": _texto(l.get("fonte_tarifa")),
        }
        for l in df.to_dict("records") if _texto(l.get(nome))
    }


def carregar_distribuidoras_e_tarifas(con):
    ufs = ler_ufs()

    # Tarifas: do tarifas_aneel_limpo.csv; sem ele, da coluna tarifa_kwh do distribuidoras_uf.csv
    if config.TARIFAS_CSV.exists():
        tarifas = ler_tarifas_residenciais(config.TARIFAS_CSV)
        origem = config.TARIFAS_CSV.name
    else:
        print(f"[aviso] {config.TARIFAS_CSV.name} nao encontrado, usando tarifa_kwh do distribuidoras_uf.csv")
        tarifas = pd.DataFrame(
            [{"nome": d["nome"], "tarifa_kwh": pd.to_numeric(str(d["tarifa_kwh"]).replace(",", "."), errors="coerce"),
              "vigencia_inicio": d["vigencia_inicio"], "fonte": d["fonte"] or config.DISTRIBUIDORAS_CSV.name}
             for d in ufs.values() if d["tarifa_kwh"]],
            columns=["nome", "tarifa_kwh", "vigencia_inicio", "fonte"],
        )
        origem = config.DISTRIBUIDORAS_CSV.name
    tarifas = tarifas[tarifas["tarifa_kwh"] > 0]

    # Distribuidoras: todas que aparecem em qualquer um dos dois arquivos
    nomes = {}
    for nome in tarifas["nome"]:
        nomes.setdefault(normalizar(nome), nome)
    for chave, dado in ufs.items():
        nomes.setdefault(chave, dado["nome"])

    ids = {}
    for chave, nome in sorted(nomes.items()):
        dado = ufs.get(chave, {})
        ids[chave] = banco.executar(
            con, "INSERT INTO distribuidoras (nome, uf, fonte_uf) VALUES (?, ?, ?) RETURNING id",
            (nome, dado.get("uf"), dado.get("fonte_uf")),
        ).scalar_one()

    for linha in tarifas.to_dict("records"):
        banco.executar(
            con, "INSERT INTO tarifas (distribuidora_id, tarifa_kwh, vigencia_inicio, fonte) VALUES (?, ?, ?, ?)",
            (ids[normalizar(linha["nome"])], float(linha["tarifa_kwh"]),
             _texto(linha["vigencia_inicio"]), linha["fonte"]),
        )

    banco.executar(con, "INSERT INTO cargas (arquivo, linhas) VALUES (?, ?)", (origem, len(tarifas)))
    if ufs and origem != config.DISTRIBUIDORAS_CSV.name:
        banco.executar(con, "INSERT INTO cargas (arquivo, linhas) VALUES (?, ?)", (config.DISTRIBUIDORAS_CSV.name, len(ufs)))
    return len(nomes), len(tarifas)


def rodar_exemplos(con):
    if not CONSULTAS_SQL.exists():
        print(f"{CONSULTAS_SQL.name} nao encontrado")
        return
    blocos = [b.strip() for b in CONSULTAS_SQL.read_text(encoding="utf-8").split(";") if b.strip()]
    for bloco in blocos:
        titulo = next((l.lstrip("- ").strip() for l in bloco.splitlines() if l.startswith("--")), "consulta")
        print(f"\n=== {titulo}")
        resultado = banco.consulta(con, bloco)
        print("(sem linhas)" if resultado.empty else resultado.to_string(index=False))


def main():
    parser = argparse.ArgumentParser(description="Cria as tabelas do iamp no PostgreSQL")
    parser.add_argument("--exemplos", action="store_true", help="roda as consultas de exemplo no final")
    args = parser.parse_args()

    try:
        con = banco.conectar()
    except ConnectionError as erro:
        print(f"Erro: {erro}")
        raise SystemExit(1)
    try:
        con.exec_driver_sql(ESQUEMA)
        n_aparelhos = carregar_aparelhos(con)
        n_dist, n_tarifas = carregar_distribuidoras_e_tarifas(con)
        extras = carregar_dados_extras(con)
        con.commit()
    except Exception:
        con.rollback()
        raise

    def contar(sql):
        return banco.executar(con, sql).scalar_one()

    sem_uf = contar("SELECT COUNT(*) FROM distribuidoras WHERE uf IS NULL")
    n_consultas = contar("SELECT COUNT(*) FROM consultas")
    com_tarifa = contar("SELECT COUNT(*) FROM vw_tarifa_vigente")
    print(f"Banco criado: {con.engine.url.render_as_string(hide_password=True)}")
    print(f"  aparelhos:      {n_aparelhos}")
    print(f"  distribuidoras: {n_dist} ({sem_uf} sem UF, {com_tarifa} com tarifa vigente)")
    print(f"  tarifas:        {n_tarifas} (incluindo vigencias antigas)")
    print(f"  consultas:      {n_consultas} (historico mantido)")
    print(f"  portateis:      {extras['portateis']}")
    print(f"  fogoes a gas:   {extras['fogoes']}")
    print(f"  precos do GLP:  {extras['precos_glp']} (UF x ano)")

    if args.exemplos:
        rodar_exemplos(con)
    con.close()


if __name__ == "__main__":
    main()
