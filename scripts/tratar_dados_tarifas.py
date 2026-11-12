
import pandas as pd

from config import RAW_FOLDER, save_processed

# Arquivo de entrada (dados abertos ANEEL, separador ';')
input_file = RAW_FOLDER / "tarifas_aneel.csv"

# Data atual
today = pd.Timestamp.today().normalize()

# Colunas que queremos manter
useful_columns = [
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

if not input_file.exists():
    print(f"Arquivo não encontrado: {input_file}")
    print("Confira o caminho do CSV.")
    raise SystemExit(1)

# Ler o arquivo
df = pd.read_csv(
    input_file,
    sep=";",
    encoding="utf-8-sig",
    dtype=str,
    keep_default_na=False
)

print("Linhas originais:", len(df))
print("Colunas originais:", len(df.columns))

# Verificar quais colunas existem
existing_columns = [
    column for column in useful_columns
    if column in df.columns
]

missing_columns = [
    column for column in useful_columns
    if column not in df.columns
]

if missing_columns:
    print("ATENÇÃO - colunas não encontradas:", missing_columns)

# Não continuar se faltarem informações essenciais
essential = [
    "SigAgente",
    "DscClasse",
    "DscUnidadeTerciaria",
    "DatInicioVigencia",
    "DatFimVigencia",
    "VlrTUSD",
    "VlrTE",
]

if not all(column in df.columns for column in essential):
    print("Confira os nomes das colunas antes de continuar.")
    raise SystemExit(1)

# Manter apenas as colunas selecionadas
df = df[existing_columns].copy()

# Remover espaços extras dos textos
for column in df.columns:
    df[column] = df[column].str.strip()

# Converter datas para comparação
start = pd.to_datetime(
    df["DatInicioVigencia"],
    format="%Y-%m-%d",
    errors="coerce"
)

end = pd.to_datetime(
    df["DatFimVigencia"],
    format="%Y-%m-%d",
    errors="coerce"
)

# Manter tarifas que podem estar vigentes hoje.
# Datas vazias ou inválidas são preservadas para revisão,
# evitando excluir registros por engano.
valid_start_date = start.isna() | (start <= today)
valid_end_date = (
    df["DatFimVigencia"].eq("")
    | end.isna()
    | (end >= today)
)

df = df[valid_start_date & valid_end_date].copy()

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
for column in ["VlrTUSD", "VlrTE"]:
    df[column] = pd.to_numeric(
        df[column].str.replace(".", "", regex=False).str.replace(",", ".", regex=False),
        errors="coerce",
    )

# Tarifa final por kWh (TUSD + TE), convertendo de R$/MWh quando necessário
factor = df["DscUnidadeTerciaria"].str.upper().map({"MWH": 1000, "KWH": 1}).fillna(1)
df["tarifa_r_kwh"] = (df["VlrTUSD"] + df["VlrTE"]) / factor

save_processed(df, "tarifas_aneel_limpo.csv")
print("Linhas finais:", len(df))
