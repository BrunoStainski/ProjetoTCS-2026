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
    "potencia_w", "standby_kwh_mes", "origem_dado", "arquivo_origem", "busca",
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
    parser = argparse.ArgumentParser(description="Cria as tabelas do WattWise no PostgreSQL")
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

    if args.exemplos:
        rodar_exemplos(con)
    con.close()


if __name__ == "__main__":
    main()
