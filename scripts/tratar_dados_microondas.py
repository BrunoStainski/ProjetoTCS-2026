# %% [markdown]
# Notebook 1: Configuração do ambiente e carregamento do dataset

# %%
from pathlib import Path
import pandas as pd
from config import read_csv_inmetro, save_processed
import numpy as np

df = read_csv_inmetro("microondas.csv")

df.columns = (
    df.columns
    .str.strip()
    .str.replace(' ', '_')
    .str.replace('(', '')
    .str.replace(')', '')
    .str.replace('°C', 'C')
    .str.replace('/', '_')
)

print("Dataset carregado e colunas padronizadas!")
print(f"Total de linhas: {len(df)} | Total de colunas: {len(df.columns)}")
print("Colunas:", list(df.columns))

# %% [markdown]
# Notebook 2: Seleção de atributos (Feature selection)

# %%
# 1) Filtrar apenas modelos 'Incluido' ANTES de remover a coluna de status
if 'Status_do_Modelo' in df.columns:
    before = len(df)
    df = df[df['Status_do_Modelo'].astype(str).str.strip().str.lower() == 'incluido']
    print(f"✓ Filtro 'Incluido' aplicado: {len(df)} linhas (removidas {before - len(df)})")

# 2) Remover colunas irrelevantes para a aplicação
columns_to_remove = [
    'Status_do_Modelo',
    'Volume_Útil_l',
    'Código_de_Barras',
    'Status_do_Registro',
    'Número_do_Registro',
]

existing_columns = [col for col in columns_to_remove if col in df.columns]
df = df.drop(columns=existing_columns)

print(f"✓ {len(existing_columns)} colunas irrelevantes removidas.")
print(f"Colunas restantes ({len(df.columns)}):", list(df.columns))

# %% [markdown]
# Notebook 3: Tratamento de Duplicatas

# %%
# 1) Duplicatas exatas
lines_before = len(df)
df = df.drop_duplicates()
print(f"✓ Linhas duplicadas exatas removidas: {lines_before - len(df)}")

# 2) Duplicatas por (Marca, Modelo, Tensão) — preserva variantes 127V / 220V
if all(c in df.columns for c in ['Marca', 'Modelo', 'Tensão_V']):
    df['contagem_nulos'] = df.isnull().sum(axis=1)
    df = df.sort_values('contagem_nulos').drop_duplicates(
        subset=['Marca', 'Modelo', 'Tensão_V'], keep='first'
    )
    df = df.drop(columns=['contagem_nulos'])
    print(f"✓ Duplicatas tratadas. Total de linhas atual: {len(df)}")

# %% [markdown]
# Notebook 4: Correção de Typos e Filtros

# %%
# --- Conversão de tipos ---
numeric_columns = [
    'Potência_Nominal_W',
    'Volume_l',
    'Consumo_Modo_Espera_Stand-by_kWh_dia',
    'Eficiência_Energética_%',
]
for col in numeric_columns:
    if col in df.columns:
        df[col] = pd.to_numeric(df[col], errors='coerce')

# Tensão: extrair parte numérica de "127 V" / "220 V"
if 'Tensão_V' in df.columns:
    df['Tensão_V'] = df['Tensão_V'].astype(str).str.extract(r'(\d+)')[0]
    df['Tensão_V'] = pd.to_numeric(df['Tensão_V'], errors='coerce')

print("✓ Tipos convertidos para numérico.")

# --- Recuperação de registros com erro de escala ---
# Alguns cadastros do INMETRO vêm com a vírgula decimal deslocada
# (ex.: eficiência 5,8 em vez de 58%; stand-by 2,3 em vez de 0,023 kWh/dia).
# Em vez de descartar esses modelos, a escala é corrigida para manter
# mais micro-ondas na base. Os filtros de faixa abaixo removem o que
# continuar fora do plausível depois da correção.
if 'Eficiência_Energética_%' in df.columns:
    mask_eff = df['Eficiência_Energética_%'] < 20
    df.loc[mask_eff, 'Eficiência_Energética_%'] = df.loc[mask_eff, 'Eficiência_Energética_%'] * 10

if 'Consumo_Modo_Espera_Stand-by_kWh_dia' in df.columns:
    mask_cons = df['Consumo_Modo_Espera_Stand-by_kWh_dia'] > 0.5
    df.loc[mask_cons, 'Consumo_Modo_Espera_Stand-by_kWh_dia'] = (
        df.loc[mask_cons, 'Consumo_Modo_Espera_Stand-by_kWh_dia'] / 100
    )
print("✓ Erros de escala corrigidos.")

# --- Filtros de inconsistência ---
before = len(df)

if 'Tensão_V' in df.columns:
    df = df[df['Tensão_V'].isin([127, 220])]
    print(f"Após filtro de tensão: {len(df)} linhas")

filters = [
    ('Potência_Nominal_W', 500, 4000),
    ('Volume_l', 10, 100),
    ('Consumo_Modo_Espera_Stand-by_kWh_dia', 0, 0.5),
    ('Eficiência_Energética_%', 20, 65),
]

for col, minimum, maximum in filters:
    if col in df.columns:
        mask = df[col].isna() | ((df[col] >= minimum) & (df[col] <= maximum))
        df = df[mask]
        print(f"Após filtro de {col}: {len(df)} linhas")

print(f"✓ Linhas restantes: {len(df)}")

# %% [markdown]
# Notebook 5: Imputação e Exportação

# %%
impute_columns = [
    'Volume_l',
    'Potência_Nominal_W',
    'Consumo_Modo_Espera_Stand-by_kWh_dia',
    'Eficiência_Energética_%',
]
valid_columns = [c for c in impute_columns if c in df.columns]

# Marca as linhas cuja potência ou stand-by vai ser preenchido pela média (o app avisa o usuário)
df['Consumo_Imputado'] = df[[c for c in ('Potência_Nominal_W', 'Consumo_Modo_Espera_Stand-by_kWh_dia')
                             if c in df.columns]].isna().any(axis=1)

# Imputação pela média agrupada em (Marca, Tensão)
if 'Marca' in df.columns and 'Tensão_V' in df.columns:
    df[valid_columns] = (
        df.groupby(['Marca', 'Tensão_V'])[valid_columns]
          .transform(lambda x: x.fillna(x.mean()))
    )

df = df.dropna(subset=valid_columns)

print(f"✓ Processo finalizado! Linhas prontas para uso: {len(df)}")
print(f"Colunas finais: {list(df.columns)}")

save_processed(df, "microondas_limpo.csv")
