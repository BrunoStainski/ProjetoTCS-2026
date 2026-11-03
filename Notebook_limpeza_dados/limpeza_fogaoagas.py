# %% [markdown]
# Notebook 1: Configuração do ambiente e carregamento do dataset de fogões

# %%
from pathlib import Path
import pandas as pd
import numpy as np

arquivo_nome = "fogoes-e-fornos-a-gas-de-uso-domestico.csv"

diretorio_atual = Path.cwd()

caminhos_encontrados = list(diretorio_atual.rglob(arquivo_nome))

if not caminhos_encontrados:
    caminhos_encontrados = list(diretorio_atual.parent.rglob(arquivo_nome))

if caminhos_encontrados:
    caminho_final = caminhos_encontrados[0]
    print(f"Arquivo localizado com sucesso em: {caminho_final}")
else:
    caminho_final = Path("../Datasets Itens de casa/fogoes-e-fornos-a-gas-de-uso-domestico.csv")
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
    .str.replace('á', 'a')
    .str.replace('é', 'e')
    .str.replace('í', 'i')
    .str.replace('ó', 'o')
    .str.replace('ú', 'u')
    .str.replace('ç', 'c')
    .str.replace('ª', '')
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
    'Codigo_de_Barras',
    'Status_do_Registro',
    'Numero_do_Registro',
    'Selo_CONPET',
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

# 2) Duplicatas por chave composta (Marca, Modelo, Número de Bocas, Tipo de Gás, Piso/Embutir)
chave_duplicatas = ['Marca', 'Modelo', 'Numerode_Bocas', 'Tipo_de_Gas', 'Piso_ou_Embutir']
chave_existente = [c for c in chave_duplicatas if c in df.columns]

if chave_existente:
    df['contagem_nulos'] = df.isnull().sum(axis=1)
    df = df.sort_values('contagem_nulos').drop_duplicates(
        subset=chave_existente, keep='first'
    )
    df = df.drop(columns=['contagem_nulos'])
    print(f"✓ Duplicatas lógicas tratadas. Total de linhas atual: {len(df)}")

# %% [markdown]
# Notebook 4: Correção de Typos e Filtros de Domínio

# %%
# --- Conversão de tipos numéricos ---
colunas_numericas = [
    'Numerode_Bocas',
    'Rendimento_Medio_dos_Queimadores_%',
    'Volume_do_Forno_litros',
    'Consumo_do_Forno_GLPkg_h_GNm3_h',
    'Índice_de_Consumo_do_Forno_%'
]

for col in colunas_numericas:
    if col in df.columns:
        df[col] = pd.to_numeric(df[col], errors='coerce')

print("✓ Tipos convertidos para numérico.")

# --- Filtros de consistência e domínio físico ---
antes = len(df)

filtros = [
    ('Numerode_Bocas', 1, 6),
    ('Rendimento_Medio_dos_Queimadores_%', 40, 100),
    ('Volume_do_Forno_litros', 15, 150),
    ('Consumo_do_Forno_GLPkg_h_GNm3_h', 0.01, 0.5),
]

for col, minimo, maximo in filtros:
    if col in df.columns:
        mask = df[col].isna() | ((df[col] >= minimo) & (df[col] <= maximo))
        df = df[mask]
        print(f"Após filtro de {col}: {len(df)} linhas")

print(f"✓ Linhas restantes após filtros: {len(df)}")

# %% [markdown]
# Notebook 5: Imputação e Exportação

# %%
colunas_imputar = [
    'Rendimento_Medio_dos_Queimadores_%',
    'Volume_do_Forno_litros',
    'Consumo_do_Forno_GLPkg_h_GNm3_h',
    'Índice_de_Consumo_do_Forno_%'
]
colunas_validas = [c for c in colunas_imputar if c in df.columns]

# Imputação pela média agrupada em (Marca, Numerode_Bocas)
if 'Marca' in df.columns and 'Numerode_Bocas' in df.columns:
    df[colunas_validas] = (
        df.groupby(['Marca', 'Numerode_Bocas'])[colunas_validas]
          .transform(lambda x: x.fillna(x.mean()))
    )

df = df.dropna(subset=colunas_validas)

print(f"✓ Processo finalizado! Linhas prontas para uso: {len(df)}")
print(f"Colunas finais: {list(df.columns)}")

caminho_saida = caminho_final.parent / "fogoes_limpo.csv"
df.to_csv(caminho_saida, index=False)
print(f"✓ Dataset limpo salvo com sucesso em: {caminho_saida}")