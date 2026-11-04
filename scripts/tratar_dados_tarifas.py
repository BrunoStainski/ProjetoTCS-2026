
import pandas as pd

from config import PASTA_RAW, salvar_processado

# Arquivo de entrada (dados abertos ANEEL, separador ';')
arquivo_entrada = PASTA_RAW / "tarifas_aneel.csv"

# Data atual
hoje = pd.Timestamp.today().normalize()

# Colunas que queremos manter
colunas_uteis = [
    "SigAgente",
    "DscClasse",
    "DscBaseTarifaria",        # "Tarifa de Aplicação" x "Base Econômica"
    "DscSubGrupo",             # B1 = residencial de baixa tensão
    "DscModalidadeTarifaria",
    "DscSubClasse",            # separa residencial comum de baixa renda
    "DscDetalhe",
    "NomPostoTarifario",       # tarifa branca tem um valor por horário
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
    encoding="utf-8-sig",
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
    format="%Y-%m-%d",
    errors="coerce"
)

fim = pd.to_datetime(
    df["DatFimVigencia"],
    format="%Y-%m-%d",
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

# Valores vêm com vírgula decimal ("696,40") -> número
for coluna in ["VlrTUSD", "VlrTE"]:
    df[coluna] = pd.to_numeric(
        df[coluna].str.replace(".", "", regex=False).str.replace(",", ".", regex=False),
        errors="coerce",
    )

# Tarifa final por kWh (TUSD + TE), convertendo de R$/MWh quando necessário
fator = df["DscUnidadeTerciaria"].str.upper().map({"MWH": 1000, "KWH": 1}).fillna(1)
df["tarifa_r_kwh"] = (df["VlrTUSD"] + df["VlrTE"]) / fator

salvar_processado(df, "tarifas_aneel_limpo.csv")
print("Linhas finais:", len(df))
