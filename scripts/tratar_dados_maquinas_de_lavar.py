# %% [markdown]
# Notebook 1: Configuração do ambiente e carregamento do dataset

# %%
import pandas as pd
from config import read_csv_inmetro, save_processed

df = read_csv_inmetro("maquinas-de-lavar.csv")

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
if 'Status_do_Modelo' in df.columns:
    before = len(df)
    df = df[df['Status_do_Modelo'].astype(str).str.strip().str.lower() == 'incluido']
    print(f"✓ Filtro 'Incluido' aplicado: {len(df)} linhas (removidas {before - len(df)})")

columns_to_remove = [
    'Status_do_Modelo',
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
for col in ['Marca', 'Modelo', 'Tipo_de_Lavadora']:
    if col in df.columns:
        df[col] = df[col].astype(str).str.strip()

if 'Marca' in df.columns:
    df['Marca'] = df['Marca'].str.upper()

lines_before = len(df)
df = df.drop_duplicates()
print(f"✓ Linhas duplicadas exatas removidas: {lines_before - len(df)}")

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
numeric_columns = [
    'Capacidade_de_lavagem_kg',
    'Consumo_de_energia_kWh_ciclo_água_fria',
    'Desempenho_de_lavagem_água_fria',
    'Consumo_de_energia_kWh_ciclo_água_quente',
    'Velocidade_de_centrifugação_rpm',
    'Consumo_de_água_l',
    'Tempo_do_ciclo_min',
]
for col in numeric_columns:
    if col in df.columns:
        df[col] = pd.to_numeric(df[col], errors='coerce')

if 'Tensão_V' in df.columns:
    df['Tensão_V'] = df['Tensão_V'].astype(str).str.extract(r'(\d+)')[0]
    df['Tensão_V'] = pd.to_numeric(df['Tensão_V'], errors='coerce')

print("✓ Tipos convertidos para numérico.")

if 'Desempenho_de_lavagem_água_fria' in df.columns:
    mask_performance = df['Desempenho_de_lavagem_água_fria'] > 1.5
    df.loc[mask_performance, 'Desempenho_de_lavagem_água_fria'] = (
        df.loc[mask_performance, 'Desempenho_de_lavagem_água_fria'] / 100
    )
print("✓ Typos corrigidos.")

before = len(df)

if 'Tensão_V' in df.columns:
    df = df[df['Tensão_V'].isin([127, 220])]
    print(f"Após filtro de tensão: {len(df)} linhas")

filters = [
    ('Capacidade_de_lavagem_kg', 1, 25),
    ('Consumo_de_energia_kWh_ciclo_água_fria', 0, 1.5),
    ('Desempenho_de_lavagem_água_fria', 0.5, 1.2),
    ('Consumo_de_energia_kWh_ciclo_água_quente', 0, 5),
    ('Velocidade_de_centrifugação_rpm', 400, 1600),
    ('Consumo_de_água_l', 5, 300),
    ('Tempo_do_ciclo_min', 3, 700),
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
required_columns = [
    'Capacidade_de_lavagem_kg',
    'Consumo_de_energia_kWh_ciclo_água_fria',
    'Desempenho_de_lavagem_água_fria',
    'Consumo_de_água_l',
    'Tempo_do_ciclo_min',
]
optional_columns = [
    'Consumo_de_energia_kWh_ciclo_água_quente',
    'Velocidade_de_centrifugação_rpm',
]

required_columns = [c for c in required_columns if c in df.columns]
optional_columns = [c for c in optional_columns if c in df.columns]

# Marca as linhas cujo consumo vai ser preenchido pela média (o app avisa o usuário)
df['Consumo_Imputado'] = df['Consumo_de_energia_kWh_ciclo_água_fria'].isna()

if 'Marca' in df.columns and 'Tensão_V' in df.columns:
    df[required_columns] = (
        df.groupby(['Marca', 'Tensão_V'])[required_columns]
          .transform(lambda x: x.fillna(x.mean()))
    )

df = df.dropna(subset=required_columns)

if 'Tipo_de_Lavadora' in df.columns and 'Marca' in df.columns:
    for col in optional_columns:
        if df.groupby('Tipo_de_Lavadora')[col].count().max() > 0:
            df[col] = df.groupby(['Tipo_de_Lavadora', 'Marca'])[col].transform(
                lambda x: x.fillna(x.mean())
            )
            df[col] = df.groupby('Tipo_de_Lavadora')[col].transform(
                lambda x: x.fillna(x.mean())
            )

print(f"✓ Processo finalizado! Linhas prontas para uso: {len(df)}")
print(f"Colunas finais: {list(df.columns)}")
print("Nulos restantes por coluna:")
print(df.isnull().sum())

save_processed(df, "maquinas-de-lavar_limpo.csv")
