# %% [markdown]
# Notebook 1: Configuração do ambiente e carregamento do dataset

# %%
from pathlib import Path
import pandas as pd
import numpy as np

arquivo_nome = "microondas.csv"

diretorio_atual = Path.cwd()

caminhos_encontrados = list(diretorio_atual.rglob(arquivo_nome))

if not caminhos_encontrados:
    caminhos_encontrados = list(diretorio_atual.parent.rglob(arquivo_nome))

if caminhos_encontrados:
    caminho_final = caminhos_encontrados[0]
    print(f"Arquivo localizado com sucesso em: {caminho_final}")
else:
    caminho_final = Path("../Datasets Itens de casa/microondas.csv")
    print(f"Carregado via caminho manual: {caminho_final}")

# encoding utf-8-sig por causa do BOM no início do arquivo
df = pd.read_csv(caminho_final, encoding='utf-8-sig')

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
    antes = len(df)
    df = df[df['Status_do_Modelo'].astype(str).str.strip().str.lower() == 'incluido']
    print(f"✓ Filtro 'Incluido' aplicado: {len(df)} linhas (removidas {antes - len(df)})")

# 2) Remover colunas irrelevantes para a aplicação
colunas_para_remover = [
    'Status_do_Modelo',
    'Volume_Útil_l',
    'Código_de_Barras',
    'Status_do_Registro',
    'Número_do_Registro',
]

colunas_existentes = [col for col in colunas_para_remover if col in df.columns]
df = df.drop(columns=colunas_existentes)

print(f"✓ {len(colunas_existentes)} colunas irrelevantes removidas.")
print(f"Colunas restantes ({len(df.columns)}):", list(df.columns))

# %% [markdown]
# Notebook 3: Tratamento de Duplicatas

# %%
# 1) Duplicatas exatas
linhas_antes = len(df)
df = df.drop_duplicates()
print(f"✓ Linhas duplicadas exatas removidas: {linhas_antes - len(df)}")

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
colunas_numericas = [
    'Potência_Nominal_W',
    'Volume_l',
    'Consumo_Modo_Espera_Stand-by_kWh_dia',
    'Eficiência_Energética_%',
]
for col in colunas_numericas:
    if col in df.columns:
        df[col] = pd.to_numeric(df[col], errors='coerce')

# Tensão: extrair parte numérica de "127 V" / "220 V"
if 'Tensão_V' in df.columns:
    df['Tensão_V'] = df['Tensão_V'].astype(str).str.extract(r'(\d+)')[0]
    df['Tensão_V'] = pd.to_numeric(df['Tensão_V'], errors='coerce')

print("✓ Tipos convertidos para numérico.")

# --- Correção de typos conhecidos ---
if 'Eficiência_Energética_%' in df.columns:
    mask_ef = df['Eficiência_Energética_%'] < 20
    df.loc[mask_ef, 'Eficiência_Energética_%'] = df.loc[mask_ef, 'Eficiência_Energética_%'] * 10

if 'Consumo_Modo_Espera_Stand-by_kWh_dia' in df.columns:
    mask_cons = df['Consumo_Modo_Espera_Stand-by_kWh_dia'] > 0.5
    df.loc[mask_cons, 'Consumo_Modo_Espera_Stand-by_kWh_dia'] = (
        df.loc[mask_cons, 'Consumo_Modo_Espera_Stand-by_kWh_dia'] / 100
    )
print("✓ Typos corrigidos.")

# --- Filtros de inconsistência ---
antes = len(df)

if 'Tensão_V' in df.columns:
    df = df[df['Tensão_V'].isin([127, 220])]
    print(f"Após filtro de tensão: {len(df)} linhas")

filtros = [
    ('Potência_Nominal_W', 500, 4000),
    ('Volume_l', 10, 100),
    ('Consumo_Modo_Espera_Stand-by_kWh_dia', 0, 0.5),
    ('Eficiência_Energética_%', 20, 65),
]

for col, minimo, maximo in filtros:
    if col in df.columns:
        mask = df[col].isna() | ((df[col] >= minimo) & (df[col] <= maximo))
        df = df[mask]
        print(f"Após filtro de {col}: {len(df)} linhas")

print(f"✓ Linhas restantes: {len(df)}")

# %% [markdown]
# Notebook 5: Imputação e Exportação

# %%
colunas_imputar = [
    'Volume_l',
    'Potência_Nominal_W',
    'Consumo_Modo_Espera_Stand-by_kWh_dia',
    'Eficiência_Energética_%',
]
colunas_validas = [c for c in colunas_imputar if c in df.columns]

# Imputação pela média agrupada em (Marca, Tensão)
if 'Marca' in df.columns and 'Tensão_V' in df.columns:
    df[colunas_validas] = (
        df.groupby(['Marca', 'Tensão_V'])[colunas_validas]
          .transform(lambda x: x.fillna(x.mean()))
    )

df = df.dropna(subset=colunas_validas)

print(f"✓ Processo finalizado! Linhas prontas para uso: {len(df)}")
print(f"Colunas finais: {list(df.columns)}")

caminho_saida = caminho_final.parent / "microondas_limpo.csv"
df.to_csv(caminho_saida, index=False)
print(f"✓ Dataset limpo salvo com sucesso em: {caminho_saida}")