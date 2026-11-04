
from pathlib import Path
import pandas as pd

# Caminhos
diretorio_atual = Path.cwd()

arquivo = (
    diretorio_atual.parent
    / "Datasets"
    / "lampadas-de-vapor-de-sodio-de-alta-pressao.csv"
)

if not arquivo.is_file():
    raise FileNotFoundError(f"Arquivo não encontrado: {arquivo}")

# Leitura
df = pd.read_csv(arquivo, encoding="utf-8-sig")

print("Dados originais:", df.shape)

# Manter somente registros ativos
df = df[df["Status do Registro"] == "Ativo"].copy()

# Converter potência e tensão
df["Potência (W)"] = pd.to_numeric(
    df["Potência (W)"], errors="coerce"
)

df["Tensão (V)"] = pd.to_numeric(
    df["Tensão (V)"], errors="coerce"
)

# Remover registros sem potência válida
df = df[
    df["Potência (W)"].notna()
    & (df["Potência (W)"] > 0)
]

# Manter somente colunas úteis
df = df[
    ["Marca", "Modelo", "Tensão (V)", "Potência (W)"]
].copy()

# Remover duplicatas
df = df.drop_duplicates(subset=["Marca", "Modelo"])

# Salvar
saida = (
    diretorio_atual
    / "lampadas_vapor_sodio_limpo.csv"
)

df.to_csv(saida, index=False, encoding="utf-8-sig")

print("\nLimpeza concluída!")
print("Dados finais:", df.shape)
print("Arquivo salvo em:", saida)
