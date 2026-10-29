
import pandas as pd
from pathlib import Path

# Arquivos de entrada e saída
arquivo_entrada = Path("dataset_tarifas/tarifas_wattwise.csv")
arquivo_saida = Path("dataset_tarifas/tarifas_wattwise_final.csv")

# Data atual
hoje = pd.Timestamp.today().normalize()

# Colunas que queremos manter
colunas_uteis = [
    "SigAgente",
    "DscClasse",
    "DscModalidadeTarifaria",
    "DscUnidadeTerciaria",
    "DatInicioVigencia",
    "DatFimVigencia",
    "VlrTUSD",
    "VlrTE",
]

if not arquivo_entrada.exists():
    print(f"Arquivo não encontrado: {arquivo_entrada}")
    print("Confira o caminho do CSV.")
    raise SystemExit(1)

# Ler o arquivo
df = pd.read_csv(
    arquivo_entrada,
    sep=";",
    dtype=str,
    keep_default_na=False
)

print("Linhas originais:", len(df))
print("Colunas originais:", len(df.columns))

# Verificar quais colunas existem
colunas_existentes = [
    coluna for coluna in colunas_uteis
    if coluna in df.columns
]

colunas_faltantes = [
    coluna for coluna in colunas_uteis
    if coluna not in df.columns
]

if colunas_faltantes:
    print("ATENÇÃO - colunas não encontradas:", colunas_faltantes)

# Não continuar se faltarem informações essenciais
essenciais = [
    "SigAgente",
    "DscClasse",
    "DscUnidadeTerciaria",
    "DatInicioVigencia",
    "DatFimVigencia",
    "VlrTUSD",
    "VlrTE",
]

if not all(coluna in df.columns for coluna in essenciais):
    print("Confira os nomes das colunas antes de continuar.")
    raise SystemExit(1)

# Manter apenas as colunas selecionadas
df = df[colunas_existentes].copy()

# Remover espaços extras dos textos
for coluna in df.columns:
    df[coluna] = df[coluna].str.strip()

# Converter datas para comparação
inicio = pd.to_datetime(
    df["DatInicioVigencia"],
    dayfirst=True,
    errors="coerce"
)

fim = pd.to_datetime(
    df["DatFimVigencia"],
    dayfirst=True,
    errors="coerce"
)

# Manter tarifas que podem estar vigentes hoje.
# Datas vazias ou inválidas são preservadas para revisão,
# evitando excluir registros por engano.
data_inicio_valida = inicio.isna() | (inicio <= hoje)
data_fim_valida = (
    df["DatFimVigencia"].eq("")
    | fim.isna()
    | (fim >= hoje)
)

df = df[data_inicio_valida & data_fim_valida].copy()

# Manter somente classes residenciais
df = df[
    df["DscClasse"].str.contains(
        "residencial",
        case=False,
        na=False
    )
].copy()

# Remover linhas totalmente duplicadas
df = df.drop_duplicates()

# Criar pasta de saída, se necessário
arquivo_saida.parent.mkdir(parents=True, exist_ok=True)

# Salvar resultado
df.to_csv(
    arquivo_saida,
    sep=";",
    index=False,
    encoding="utf-8-sig"
)

print("\nLimpeza concluída!")
print("Linhas finais:", len(df))
print("Colunas finais:", len(df.columns))
print("Colunas mantidas:", df.columns.tolist())
print("Arquivo salvo em:", arquivo_saida)
