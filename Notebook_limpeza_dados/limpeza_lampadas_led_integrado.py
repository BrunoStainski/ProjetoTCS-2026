
from pathlib import Path
import pandas as pd
import numpy as np

# Localizar arquivo
arquivo_nome = "Datasets/Lampadas-led-dispositivo-integrado-a-base.csv"

diretorio_atual = Path.cwd()
caminho_final = diretorio_atual / arquivo_nome

if not caminho_final.is_file():
    raise FileNotFoundError(
        f"Arquivo não encontrado: {caminho_final.resolve()}\n"
        "Coloque o CSV na pasta do notebook ou ajuste o caminho."
    )

print("Carregando dataset...", flush=True)

df = pd.read_csv(caminho_final, encoding="utf-8-sig")

print(f"Dataset carregado: {len(df)} linhas.")

# Padronizar nomes das colunas
df.columns = (
    df.columns.str.strip()
    .str.replace(' ', '_')
    .str.replace('(', '', regex=False)
    .str.replace(')', '', regex=False)
    .str.replace('/', '_', regex=False)
)

# Manter somente modelos incluídos e registros ativos
if 'Status_do_Modelo' in df.columns:
    df = df[df['Status_do_Modelo'] == 'Incluido']

if 'Status_do_Registro' in df.columns:
    df = df[df['Status_do_Registro'] == 'Ativo']

print(f"Registros válidos: {len(df)}")

# Remover colunas desnecessárias
colunas_para_remover = [
    'Status_do_Modelo',
    'Status_do_Registro',
    'Código_de_Barras',
    'Número_do_Registro',
    'Equivalência_lâmpada_Incandescente',
    'Equivalência_lâmpada_fluorescente_compacta'
]

colunas_existentes = [
    col for col in colunas_para_remover if col in df.columns
]

df = df.drop(columns=colunas_existentes)

print(f"Colunas removidas: {len(colunas_existentes)}")

# Manter somente as colunas relevantes
colunas_relevantes = [
    'Marca',
    'Modelo',
    'Tipo_de_Lâmpada',
    'Padrão_Dimensional',
    'Tensão_V',
    'Potência_W',
    'Fluxo_Luminoso_lm',
    'TCC_K',
    'IRC',
    'Vida_Útil_Nominal_horas',
    'Eficiência_Luminosa_lm_W',
    'Fator_de_Potência_cos_',
    'Selo_Procel'
]

colunas_validas = [
    col for col in colunas_relevantes if col in df.columns
]

df = df[colunas_validas].copy()

# Remover linhas completamente duplicadas
linhas_antes = len(df)

df = df.drop_duplicates()

print(f"Linhas duplicadas removidas: {linhas_antes - len(df)}")

# Converter informações numéricas
colunas_numericas = [
    'Tensão_V',
    'Potência_W',
    'Fluxo_Luminoso_lm',
    'TCC_K',
    'IRC',
    'Vida_Útil_Nominal_horas',
    'Eficiência_Luminosa_lm_W',
    'Fator_de_Potência_cos_'
]

for coluna in colunas_numericas:
    if coluna in df.columns:
        df[coluna] = pd.to_numeric(df[coluna], errors='coerce')

# Remover potências ausentes, zero ou negativas
if 'Potência_W' in df.columns:
    df = df.dropna(subset=['Potência_W'])
    df = df[df['Potência_W'] > 0]

# Remover valores negativos ou iguais a zero em características
# que devem possuir valores positivos
colunas_positivas = [
    'Tensão_V',
    'Fluxo_Luminoso_lm',
    'TCC_K',
    'Vida_Útil_Nominal_horas',
    'Eficiência_Luminosa_lm_W'
]

for coluna in colunas_positivas:
    if coluna in df.columns:
        df.loc[df[coluna] <= 0, coluna] = np.nan

# Manter o registro mais completo de cada marca e modelo
if 'Marca' in df.columns and 'Modelo' in df.columns:
    df['_nulos'] = df.isnull().sum(axis=1)

    df = df.sort_values('_nulos')

    df = df.drop_duplicates(
        subset=['Marca', 'Modelo'],
        keep='first'
    )

    df = df.drop(columns=['_nulos'])

print(f"Modelos únicos: {len(df)}")

# Salvar dataset limpo
caminho_saida = caminho_final.parent / "lampadas_led_limpo.csv"

df.to_csv(caminho_saida, index=False, encoding="utf-8-sig")

print("--------------------------------")
print("Processo de limpeza finalizado!")
print(f"Linhas finais: {len(df)}")
print(f"Colunas finais: {len(df.columns)}")
print(f"Arquivo salvo em: {caminho_saida.resolve()}")
