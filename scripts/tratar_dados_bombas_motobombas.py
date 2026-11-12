"""Limpeza do dataset INMETRO de bombas e motobombas centrífugas."""

from config import filter_included_models, read_csv_inmetro, save_processed

ADMINISTRATIVE_COLUMNS = ["Status do Modelo", "Código de Barras", "Status do Registro", "Número do Registro"]

df = read_csv_inmetro("bombas-e-motobombas-centrifuga.csv")
print("Dados originais:", df.shape)

df = filter_included_models(df)
df = df.drop(columns=ADMINISTRATIVE_COLUMNS, errors="ignore")
df = df.dropna(subset=["Marca", "Modelo"]).drop_duplicates()

save_processed(df, "bombas-e-motobombas_limpo.csv")
