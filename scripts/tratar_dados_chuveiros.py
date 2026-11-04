import os
import pandas as pd

# 1. Definição dos caminhos
caminho_entrada = "Datasets/chuveiros-eletricos.csv"
caminho_saida = "Datasets/chuveiros_eletricos_limpo.csv"

# Se o script for executado a partir de outra pasta, garante leitura do caminho relativo
if not os.path.exists(caminho_entrada) and os.path.exists(
    "chuveiros-eletricos.csv"
):
    caminho_entrada = "chuveiros-eletricos.csv"
    caminho_saida = "chuveiros_eletricos_limpo.csv"

# 2. Carregar os dados
df = pd.read_csv(caminho_entrada)
qtd_inicial = len(df)

# 3. Remoção de espaços em branco extras (strip) em colunas de texto
colunas_texto = df.select_dtypes(include=["object"]).columns
for col in colunas_texto:
    df[col] = df[col].astype(str).str.strip()

# 4. Correção de erros de digitação (typos) identificados
df["Modelo"] = df["Modelo"].replace(
    {"JET CONROL MULTITEMPERATURAS": "JET CONTROL MULTITEMPERATURAS"}
)

# 5. Normalização dos nomes das colunas (snake_case legível)
mapeamento_colunas = {
    "Marca": "marca",
    "Família": "familia",
    "Modelo": "modelo",
    "Tensão (V)": "tensao_v",
    "Potência (W)": "potencia_w",
    "Consumo mensal máximo (kWh/mês)": "consumo_mensal_max_kwh",
    "Elevação de temperatura (°C)": "elevacao_temperatura_c",
    "Consumo mensal mínimo (kWh/mês)": "consumo_mensal_min_kwh",
    "Vazão (l/min)": "vazao_l_min",
}
df = df.rename(columns=mapeamento_colunas)

# 6. Verificação e remoção de duplicadas exatas
df = df.drop_duplicates()
qtd_finais = len(df)
duplicadas_removidas = qtd_inicial - qtd_finais

# 7. Garantir tipos de dados numéricos coerentes
df["tensao_v"] = df["tensao_v"].astype(int)
df["potencia_w"] = df["potencia_w"].astype(int)
df["consumo_mensal_max_kwh"] = df["consumo_mensal_max_kwh"].astype(float)
df["elevacao_temperatura_c"] = df["elevacao_temperatura_c"].astype(float)
df["consumo_mensal_min_kwh"] = df["consumo_mensal_min_kwh"].astype(float)
df["vazao_l_min"] = df["vazao_l_min"].astype(float)

# 8. Guardar ficheiro limpo
df.to_csv(caminho_saida, index=False, encoding="utf-8-sig")

print(f"Tratamento concluído!")
print(f"- Linhas processadas: {qtd_inicial}")
print(f"- Linhas duplicadas removidas: {duplicadas_removidas}")
print(f"- Ficheiro guardado em: {caminho_saida}")