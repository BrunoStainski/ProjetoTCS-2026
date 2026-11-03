
from pathlib import Path
import pandas as pd
import numpy as np

diretorio_atual = Path.cwd()

arquivo = (
    diretorio_atual.parent
    / "Datasets"
    / "ventilador-de-teto-de-uso-residencial.csv"
)

if not arquivo.is_file():
    raise FileNotFoundError(f"Arquivo não encontrado: {arquivo}")

df = pd.read_csv(arquivo, encoding="utf-8-sig")

print("Dados originais:", df.shape)

# Remover colunas administrativas
colunas_remover = [
    "Código de Barras",
    "Status do Modelo",
    "Status do Registro",
    "Número do Registro"
]

df = df.drop(columns=colunas_remover, errors="ignore")

# Remover duplicatas exatas
df = df.drop_duplicates()

# Colunas de consumo
colunas_consumo = [
    "Consumo de energia mensal na vel. alta (kWh/mês)",
    "Consumo de energia mensal na vel. média (kWh/mês)",
    "Consumo de energia mensal na vel. baixa (kWh/mês)"
]

# Converter consumos para números
for coluna in colunas_consumo:
    df[coluna] = pd.to_numeric(
        df[coluna], errors="coerce"
    )

# Valores negativos são inválidos
for coluna in colunas_consumo:
    df.loc[df[coluna] < 0, coluna] = np.nan

# Remover linhas sem nenhum consumo informado
df = df.dropna(subset=colunas_consumo, how="all")

# Manter o registro mais completo por marca e modelo
df["_completude"] = df.notna().sum(axis=1)

df = (
    df.sort_values("_completude", ascending=False)
    .drop_duplicates(subset=["Marca", "Modelo"])
    .drop(columns=["_completude"])
)

# Salvar
saida = diretorio_atual / "ventiladores_limpo.csv"

df.to_csv(saida, index=False, encoding="utf-8-sig")

print("\nLimpeza concluída!")
print("Dados finais:", df.shape)
print("Arquivo salvo em:", saida)
