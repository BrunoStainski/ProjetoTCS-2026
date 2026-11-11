# %% [markdown]
# Notebook 1: Configuração do ambiente e carregamento do dataset

# %%
from pathlib import Path
import pandas as pd
from config import read_csv_inmetro, save_processed
import numpy as np

df = read_csv_inmetro("ventiladores-de-mesa-de-coluna-e-circulador-de-ar.csv")

# Padronização dos nomes das colunas
df.columns = (
    df.columns
    .str.strip()
    .str.replace(' ', '_')
    .str.replace('(', '')
    .str.replace(')', '')
    .str.replace('/', '_')
    .str.replace('°C', 'C')
)

print("Dataset carregado e colunas padronizadas!")
print(f"Total de linhas: {len(df)} | Total de colunas: {len(df.columns)}")
print("Colunas:", list(df.columns))

# %% [markdown]
# Notebook 2: Seleção de atributos (Feature selection)

# %%
# 1) Filtrar apenas modelos 'Incluido'
if 'Status_do_Modelo' in df.columns:
    before = len(df)
    df = df[df['Status_do_Modelo'].astype(str).str.strip().str.lower() == 'incluido']
    print(f"✓ Filtro 'Incluido' aplicado: {len(df)} linhas (removidas {before - len(df)})")

# 2) Remover as 4 colunas solicitadas
columns_to_remove = [
    'Status_do_Modelo',
    'Código_de_Barras',
    'Status_do_Registro',
    'Número_do_Registro'
]

existing_columns = [col for col in columns_to_remove if col in df.columns]
df = df.drop(columns=existing_columns)

print(f"✓ {len(existing_columns)} colunas irrelevantes removidas.")
print(f"Colunas restantes ({len(df.columns)}):", list(df.columns))

# %% [markdown]
# Notebook 3: Tratamento de Duplicatas e Registros Redundantes

# %%
# 1) Duplicatas exatas
lines_before = len(df)
df = df.drop_duplicates()
print(f"✓ Linhas duplicadas exatas removidas: {lines_before - len(df)}")

# 2) Duplicatas por (Marca, Modelo, Tensão) — preserva variantes 127V / 220V
if all(c in df.columns for c in ['Marca', 'Modelo', 'Tensão']):
    df['contagem_nulos'] = df.isnull().sum(axis=1)
    df = df.sort_values('contagem_nulos').drop_duplicates(
        subset=['Marca', 'Modelo', 'Tensão'], keep='first'
    )
    df = df.drop(columns=['contagem_nulos'])
    print(f"✓ Duplicatas por (Marca, Modelo, Tensão) tratadas. Total de linhas atual: {len(df)}")

# %% [markdown]
# Notebook 4: Conversão de Tipos e Filtragem de Outliers

# %%
# --- Conversão de Tipos ---
numeric_columns = [
    'Diâmetro_da_Hélice_cm',
    'No._de_Pás',
    'Vazão_Média_de_Ar_m3_h_Alta',
    'Potência_Elétrica_Consumida_W_Alta',
    'Consumo_de_Energia_MensalkWh_mês_Alta',
]
for col in numeric_columns:
    if col in df.columns:
        df[col] = pd.to_numeric(df[col], errors='coerce')

# Tensão: padronizar strings e manter apenas Bivolt, 127 ou 220
if 'Tensão' in df.columns:
    df['Tensão'] = df['Tensão'].astype(str).str.strip().str.upper()
    mask_voltage = df['Tensão'].str.contains('127|220|BIVOLT', na=False)
    df = df[mask_voltage]
    print(f"Após filtro de tensão: {len(df)} linhas")

print("✓ Tipos convertidos e tensão padronizada.")

# --- Filtros de Outliers (mantendo NaN para imputação posterior) ---
before = len(df)

filters = [
    ('Diâmetro_da_Hélice_cm', 10, 100),   # Corrige erros de digitação como 510cm
    ('Potência_Elétrica_Consumida_W_Alta', 10, 500),
    ('Consumo_de_Energia_MensalkWh_mês_Alta', 0, 20),
    ('Vazão_Média_de_Ar_m3_h_Alta', 0, 10),
]

for col, minimum, maximum in filters:
    if col in df.columns:
        mask = df[col].isna() | ((df[col] >= minimum) & (df[col] <= maximum))
        df = df[mask]
        print(f"Após filtro de {col} [{minimum}, {maximum}]: {len(df)} linhas")

print(f"✓ Filtros aplicados. Total removido: {before - len(df)} | Linhas restantes: {len(df)}")

# %% [markdown]
# Notebook 5: Imputação Inteligente e Exportação dos Dados Limpos

# %%
# ==========================================
# 1) Conversão de Tipos e Imputação Numérica
# ==========================================
numeric_columns = [
    'Diâmetro_da_Hélice_cm',
    'No._de_Pás',
    'Vazão_Média_de_Ar_m3_h_Alta',
    'Potência_Elétrica_Consumida_W_Alta',
    'Consumo_de_Energia_MensalkWh_mês_Baixa',
    'Consumo_de_Energia_MensalkWh_mês_Média',
    'Consumo_de_Energia_MensalkWh_mês_Alta',
    'Eficiência_m3_s_W_Baixa',
    'Eficiência_m3_s_W_Média',
    'Eficiência_m3_s_W_Alta'
]
valid_columns = [c for c in numeric_columns if c in df.columns]

for col in valid_columns:
    df[col] = pd.to_numeric(df[col], errors='coerce')

# Marca as linhas em que algum consumo por velocidade vai ser estimado (o app avisa o usuário)
df['Consumo_Imputado'] = df[[
    'Consumo_de_Energia_MensalkWh_mês_Baixa',
    'Consumo_de_Energia_MensalkWh_mês_Média',
    'Consumo_de_Energia_MensalkWh_mês_Alta',
]].isna().any(axis=1)

# --- Imputação Proporcional (Consumo e Eficiência) ---
ratio_cons_low = (df['Consumo_de_Energia_MensalkWh_mês_Baixa'] / df['Consumo_de_Energia_MensalkWh_mês_Média']).median()
ratio_cons_high = (df['Consumo_de_Energia_MensalkWh_mês_Alta'] / df['Consumo_de_Energia_MensalkWh_mês_Média']).median()
ratio_low_eff = (df['Eficiência_m3_s_W_Baixa'] / df['Eficiência_m3_s_W_Média']).median()
ratio_high_eff = (df['Eficiência_m3_s_W_Alta'] / df['Eficiência_m3_s_W_Média']).median()

ratio_cons_low = ratio_cons_low if pd.notna(ratio_cons_low) else 0.8
ratio_cons_high = ratio_cons_high if pd.notna(ratio_cons_high) else 1.2
ratio_low_eff = ratio_low_eff if pd.notna(ratio_low_eff) else 0.9
ratio_high_eff = ratio_high_eff if pd.notna(ratio_high_eff) else 1.1

mask = df['Consumo_de_Energia_MensalkWh_mês_Baixa'].isna() & df['Consumo_de_Energia_MensalkWh_mês_Média'].notna()
df.loc[mask, 'Consumo_de_Energia_MensalkWh_mês_Baixa'] = df.loc[mask, 'Consumo_de_Energia_MensalkWh_mês_Média'] * ratio_cons_low

mask = df['Consumo_de_Energia_MensalkWh_mês_Alta'].isna() & df['Consumo_de_Energia_MensalkWh_mês_Média'].notna()
df.loc[mask, 'Consumo_de_Energia_MensalkWh_mês_Alta'] = df.loc[mask, 'Consumo_de_Energia_MensalkWh_mês_Média'] * ratio_cons_high

mask = df['Eficiência_m3_s_W_Baixa'].isna() & df['Eficiência_m3_s_W_Média'].notna()
df.loc[mask, 'Eficiência_m3_s_W_Baixa'] = df.loc[mask, 'Eficiência_m3_s_W_Média'] * ratio_low_eff

mask = df['Eficiência_m3_s_W_Alta'].isna() & df['Eficiência_m3_s_W_Média'].notna()
df.loc[mask, 'Eficiência_m3_s_W_Alta'] = df.loc[mask, 'Eficiência_m3_s_W_Média'] * ratio_high_eff

# --- Imputação Hierárquica (Para o que sobrou) ---
if 'Marca' in df.columns and 'Tipo_de_Produto' in df.columns:
    df[valid_columns] = (
        df.groupby(['Marca', 'Tipo_de_Produto'])[valid_columns]
          .transform(lambda x: x.fillna(x.mean()))
    )
if 'Tipo_de_Produto' in df.columns:
    df[valid_columns] = (
        df.groupby(['Tipo_de_Produto'])[valid_columns]
          .transform(lambda x: x.fillna(x.mean()))
    )
df[valid_columns] = df[valid_columns].fillna(df[valid_columns].median())


# ==========================================
# 2) Imputação de Texto (Tipo de Controle)
# ==========================================
if 'Tipo_de_Controle' in df.columns and 'Tipo_de_Produto' in df.columns:
    df['Tipo_de_Controle'] = df['Tipo_de_Controle'].fillna(
        df.groupby('Tipo_de_Produto')['Tipo_de_Controle'].transform(lambda x: x.mode()[0] if not x.mode().empty else '3 Velocidades')
    )
    df['Tipo_de_Controle'] = df['Tipo_de_Controle'].fillna('3 Velocidades')


# ==========================================
# 3) Dados Regulatórios: Classificação e Selo Procel (BLINDADO)
# ==========================================
regulatory_columns = [
    'Classificação_Baixa', 'Classificação_Média', 'Classificação_Alta',
    'Selo_Procel_Baixa', 'Selo_Procel_Média', 'Selo_Procel_Alta'
]

for col in regulatory_columns:
    if col in df.columns:
        # 1. Converte para texto (objeto) e preenche os nulos reais
        df[col] = df[col].astype(object).fillna('Não Informado')
        
        # 2. Força a conversão para texto para conseguir manipular
        df[col] = df[col].astype(str)
        
        # 3. Limpa os ".0" (ex: 13.0 vira 13)
        df[col] = df[col].str.replace(r'\.0$', '', regex=True)
        
        # 4. Substitui qualquer resquício de texto de nulo que tenha sobrado
        df[col] = df[col].replace(['nan', 'None', '', 'NaN', ' ', ' nan'], 'Não Informado')


# ==========================================
# 4) Limpeza Final e Exportação
# ==========================================
# Remove apenas se as colunas essenciais estiverem nulas
df = df.dropna(subset=['Marca', 'Tipo_de_Produto'])

print(f"✓ Processo finalizado! Linhas prontas para uso: {len(df)}")
print(f"Colunas finais: {list(df.columns)}")

save_processed(df, "ventiladores_de_mesa_limpo.csv")
