
from pathlib import Path
import pandas as pd

diretorio_atual = Path.cwd()

arquivo = (
    diretorio_atual.parent
    / "Datasets"
    / "televisores.csv"
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

# Converter consumo para número
coluna_consumo = "Consumo (kWh/mês)"

df[coluna_consumo] = pd.to_numeric(
    df[coluna_consumo], errors="coerce"
)

# Remover registros sem consumo válido
df = df[
    df[coluna_consumo].notna()
    & (df[coluna_consumo] > 0)
].copy()

# Manter o registro mais completo por marca e modelo
df["_completude"] = df.notna().sum(axis=1)

df = (
    df.sort_values("_completude", ascending=False)
    .drop_duplicates(subset=["Marca", "Modelo"])
    .drop(columns=["_completude"])
)

# Salvar
saida = diretorio_atual / "televisores_limpo.csv"

df.to_csv(saida, index=False, encoding="utf-8-sig")

print("\nLimpeza concluída!")
print("Dados finais:", df.shape)
print("Arquivo salvo em:", saida)
