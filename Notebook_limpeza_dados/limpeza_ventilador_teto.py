
from pathlib import Path
import pandas as pd
import numpy as np

# Localização do arquivo
arquivo_nome = "ventilador-de-teto-de-uso-residencial.csv"

diretorio_atual = Path.cwd()

caminhos_possiveis = [
    diretorio_atual / arquivo_nome,
    diretorio_atual / "Datasets" / arquivo_nome,
    diretorio_atual.parent / "Datasets" / arquivo_nome,
    diretorio_atual.parent.parent / "Datasets" / arquivo_nome
]

caminho_final = next(
    (caminho for caminho in caminhos_possiveis if caminho.is_file()),
    None
)

if caminho_final is None:
    raise FileNotFoundError(
        "Arquivo não encontrado. Verifique o caminho do dataset."
    )

print(f"Arquivo localizado: {caminho_final}")

# Carregar dataset
df = pd.read_csv(caminho_final, encoding="utf-8-sig")

print(f"Dataset carregado: {len(df)} linhas.")

# Padronizar nomes das colunas
df.columns = (
    df.columns.str.strip()
    .str.replace(' ', '_')
    .str.replace('(', '', regex=False)
    .str.replace(')', '', regex=False)
    .str.replace('/', '_', regex=False)
    .str.replace('[', '', regex=False)
    .str.replace(']', '', regex=False)
)

print("Colunas padronizadas!")

# Remover colunas administrativas
colunas_para_remover = [
    'Código_de_Barras',
    'Status_do_Modelo',
    'Status_do_Registro',
    'Número_do_Registro'
]

colunas_existentes = [
    col for col in colunas_para_remover if col in df.columns
]

df = df.drop(columns=colunas_existentes)

print(f"Colunas removidas: {len(colunas_existentes)}")

# Remover linhas duplicadas
linhas_antes = len(df)

df = df.drop_duplicates()

print(f"Linhas duplicadas removidas: {linhas_antes - len(df)}")

# Tratar modelos duplicados
if 'Marca' in df.columns and 'Modelo' in df.columns:
    df['_nulos'] = df.isnull().sum(axis=1)

    df = df.sort_values('_nulos')

    df = df.drop_duplicates(
        subset=['Marca', 'Modelo'],
        keep='first'
    )

    df = df.drop(columns=['_nulos'])

    print(f"Modelos duplicados tratados. Linhas restantes: {len(df)}")

# Tratar colunas de consumo
colunas_consumo = [
    'Consumo_de_energia_mensal_na_vel._alta_kWh_mês',
    'Consumo_de_energia_mensal_na_vel._média_kWh_mês',
    'Consumo_de_energia_mensal_na_vel._baixa_kWh_mês'
]

colunas_validas = [
    coluna for coluna in colunas_consumo
    if coluna in df.columns
]

for coluna in colunas_validas:
    df[coluna] = pd.to_numeric(df[coluna], errors='coerce')
    df.loc[df[coluna] < 0, coluna] = np.nan

# Remover registros sem nenhum consumo válido
if colunas_validas:
    df = df.dropna(subset=colunas_validas, how='all')

print(f"Linhas prontas para uso: {len(df)}")

# Salvar dataset limpo
caminho_saida = caminho_final.parent / "ventiladores_teto_limpo.csv"

df.to_csv(caminho_saida, index=False, encoding="utf-8-sig")

print(f"Dataset limpo salvo em: {caminho_saida}")
print("Processo finalizado!")
