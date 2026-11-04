
from pathlib import Path
import pandas as pd
import numpy as np

# 1. Identificar a pasta do projeto
diretorio_script = Path(__file__).resolve().parent
diretorio_projeto = diretorio_script.parent

# 2. Localizar o CSV na pasta Datasets
arquivo = (
    diretorio_projeto
    / "Datasets"
    / "lampadas-fluorecentes-com-reator-integrado-a-base.csv"
)

print("Procurando arquivo em:", arquivo)

if not arquivo.is_file():
    raise FileNotFoundError(f"Arquivo não encontrado: {arquivo}")

# 3. Ler o CSV
df = pd.read_csv(arquivo, encoding="utf-8-sig")

print("Dados originais:", df.shape)

# 4. Manter somente modelos incluídos
df = df[df["Status do Modelo"] == "Incluido"].copy()

# 5. Remover colunas administrativas
colunas_remover = [
    "Status do Modelo",
    "Status do Registro",
    "Código de Barras",
    "Número do Registro",
    "Equivalência lâmpada Incandescente"
]

df = df.drop(columns=colunas_remover, errors="ignore")

# 6. Remover registros sem marca ou modelo
df = df.dropna(subset=["Marca", "Modelo"])

# 7. Converter tensão para número
df["Tensão (V)"] = (
    df["Tensão (V)"]
    .astype("string")
    .str.extract(r"(\d+(?:[.,]\d+)?)")[0]
    .str.replace(",", ".", regex=False)
)

df["Tensão (V)"] = pd.to_numeric(
    df["Tensão (V)"], errors="coerce"
)

# 8. Converter colunas numéricas
colunas_numericas = [
    "Potência (W)",
    "Fluxo Luminoso (lm)",
    "Temperatura de Cor (K)",
    "Vida Mediana (horas)",
    "Eficiência Luminosa (lm/W)",
    "Fator de Potência (cos ?)"
]

for coluna in colunas_numericas:
    if coluna in df.columns:
        df[coluna] = pd.to_numeric(
            df[coluna], errors="coerce"
        )

# 9. Remover registros sem potência válida
df = df[
    df["Potência (W)"].notna() &
    (df["Potência (W)"] > 0)
].copy()

# 10. Tratar valores inválidos
colunas_validar = [
    "Tensão (V)",
    "Fluxo Luminoso (lm)",
    "Temperatura de Cor (K)",
    "Vida Mediana (horas)",
    "Eficiência Luminosa (lm/W)",
    "Fator de Potência (cos ?)"
]

for coluna in colunas_validar:
    if coluna in df.columns:
        df.loc[df[coluna] <= 0, coluna] = np.nan

# 11. Remover duplicatas exatas
df = df.drop_duplicates()

# 12. Manter registro mais completo por marca e modelo
df["_completude"] = df.notna().sum(axis=1)

df = (
    df.sort_values("_completude", ascending=False)
    .drop_duplicates(subset=["Marca", "Modelo"])
    .drop(columns=["_completude"])
)

# 13. Salvar arquivo limpo na pasta Datasets
arquivo_saida = (
    diretorio_projeto
    / "Datasets"
    / "lampadas_fluorescentes_limpo.csv"
)

df.to_csv(
    arquivo_saida,
    index=False,
    encoding="utf-8-sig"
)

# 14. Exibir resultado
print("\nLimpeza concluída!")
print("Dados finais:", df.shape)
print("Arquivo salvo em:", arquivo_saida)
print("\nColunas mantidas:")
print(df.columns.tolist())
