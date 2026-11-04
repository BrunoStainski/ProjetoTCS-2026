"""Limpeza do dataset INMETRO de bombas e motobombas centrífugas."""

from config import filtrar_modelos_incluidos, ler_csv_inmetro, salvar_processado

COLUNAS_ADMINISTRATIVAS = ["Status do Modelo", "Código de Barras", "Status do Registro", "Número do Registro"]

df = ler_csv_inmetro("bombas-e-motobombas-centrifuga.csv")
print("Dados originais:", df.shape)

df = filtrar_modelos_incluidos(df)
df = df.drop(columns=COLUNAS_ADMINISTRATIVAS, errors="ignore")
df = df.dropna(subset=["Marca", "Modelo"]).drop_duplicates()

salvar_processado(df, "bombas-e-motobombas_limpo.csv")
