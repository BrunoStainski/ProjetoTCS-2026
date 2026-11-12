"""
Pipeline de Limpeza e Tratamento de Dados - Sistemas Acoplados e Equipamentos Solares de Água (INMETRO)
Projeto: iamp

Etapas:
1. Configuração e Padronização de Colunas
2. Seleção de Atributos (Feature Selection)
3. Tratamento de Duplicatas e Redundâncias
4. Filtragem de Erros e Outliers Irrealistas
5. Imputação Agrupada e Exportação Final
"""

import sys
import pandas as pd

from config import filter_included_models, read_csv_inmetro, save_processed


def step_1_standardize_columns(df: pd.DataFrame) -> pd.DataFrame:
    """Etapa 1: Padroniza o nome de todas as colunas do DataFrame."""
    print("\n--- [Etapa 1/5] Padronizando Nomes de Colunas ---")
    df_clean = df.copy()
    df_clean.columns = (
        df_clean.columns.str.strip()
        .str.replace(" ", "_")
        .str.replace("(", "", regex=False)
        .str.replace(")", "", regex=False)
        .str.replace("°C", "C", regex=False)
        .str.replace("/", "_", regex=False)
        .str.replace("%", "pct", regex=False)
        .str.replace("²", "2", regex=False)
        .str.replace("ï»¿", "", regex=False)
    )
    print(f"✓ Nomes de colunas padronizados. Total de colunas: {len(df_clean.columns)}")
    return df_clean


def step_2_select_attributes(df: pd.DataFrame) -> pd.DataFrame:
    """Etapa 2: Remove colunas burocráticas, administrativas ou 100% nulas."""
    print("\n--- [Etapa 2/5] Seleção de Atributos (Feature Selection) ---")
    remove_columns = [
        "Código_de_Barras",
        "Status_do_Modelo",
        "Status_do_Registro",
        "Número_do_Registro",
        "Produção_Média_Mensal_de_Energia",  # Coluna 100% nula no cabeçalho do INMETRO
    ]

    existing_columns = [col for col in remove_columns if col in df.columns]
    df_clean = df.drop(columns=existing_columns)
    print(f"✓ {len(existing_columns)} colunas administrativas/nulas removidas.")
    return df_clean


def step_3_clean_duplicates(df: pd.DataFrame) -> pd.DataFrame:
    """Etapa 3: Elimina duplicatas exatas e consolida registros repetidos do mesmo modelo."""
    print("\n--- [Etapa 3/5] Tratamento de Duplicatas e Redundâncias ---")
    initial_qty = len(df)

    # 1. Duplicatas exatas
    df_clean = df.drop_duplicates().copy()
    exact_duplicates = initial_qty - len(df_clean)

    # 2. Modelos repetidos (preserva a versão mais completa)
    if {"Marca", "Modelo"}.issubset(df_clean.columns):
        df_clean["_qtd_nulos"] = df_clean.isnull().sum(axis=1)
        df_clean = (
            df_clean.sort_values("_qtd_nulos")
            .drop_duplicates(subset=["Marca", "Modelo"], keep="first")
            .drop(columns=["_qtd_nulos"])
        )

    removed_qty = initial_qty - len(df_clean)
    print(
        f"✓ Registros duplicados/redundantes removidos: {removed_qty} (Duplicatas exatas: {exact_duplicates})"
    )
    print(f"  Linhas restantes: {len(df_clean)}")
    return df_clean


def step_4_filter_errors_outliers(df: pd.DataFrame) -> pd.DataFrame:
    """Etapa 4: Remove registros com valores fisicamente impossíveis ou corrompidos."""
    print("\n--- [Etapa 4/5] Filtragem de Erros e Outliers Irrealistas ---")
    initial_qty = len(df)
    df_clean = df.copy()

    # Geração de energia por coletor mínima aceitável (>= 1.0 kWh/mês)
    col_generation = "Por_Coletor_KWh_mês"
    if col_generation in df_clean.columns:
        df_clean = df_clean[
            (df_clean[col_generation].isnull()) | (df_clean[col_generation] >= 1.0)
        ]

    # Volume do sistema reservatório mínimo aceitável (>= 5.0 Litros)
    col_volume = "Volume_do_Sistema_litros"
    if col_volume in df_clean.columns:
        df_clean = df_clean[
            (df_clean[col_volume].isnull()) | (df_clean[col_volume] >= 5.0)
        ]

    # Eficiência energética média mínima aceitável (>= 5.0%)
    col_efficiency = "Eficiência_Média_Energética_pct"
    if col_efficiency in df_clean.columns:
        df_clean = df_clean[
            (df_clean[col_efficiency].isnull()) | (df_clean[col_efficiency] >= 5.0)
        ]

    removed = initial_qty - len(df_clean)
    print(f"✓ Linhas com outliers/erros de cadastro removidas: {removed}")
    print(f"  Linhas restantes: {len(df_clean)}")
    return df_clean


def step_5_imputation(df: pd.DataFrame) -> pd.DataFrame:
    """Etapa 5: Realiza a imputação inteligente por Marca/Classificação e exporta o CSV limpo."""
    print("\n--- [Etapa 5/5] Imputação Inteligente ---")
    df_clean = df.copy()

    cols_numeric = [
        "Por_Coletor_KWh_mês",
        "Volume_do_Sistema_litros",
        "Por_m2_KWh_Mês.m2",
        "Eficiência_Média_Energética_pct",
        "Area_Externa_do_Coletor_M2",
    ]
    cols_impute = [c for c in cols_numeric if c in df_clean.columns]

    # 1. Imputação por Marca + Classificação
    if {"Marca", "Classificação"}.issubset(df_clean.columns) and cols_impute:
        df_clean[cols_impute] = df_clean.groupby(["Marca", "Classificação"])[
            cols_impute
        ].transform(lambda group: group.fillna(group.mean()))

    # 2. Fallback por Classificação
    if "Classificação" in df_clean.columns and cols_impute:
        df_clean[cols_impute] = df_clean.groupby("Classificação")[
            cols_impute
        ].transform(lambda group: group.fillna(group.mean()))

    # 3. Fallback por Marca
    if "Marca" in df_clean.columns and cols_impute:
        df_clean[cols_impute] = df_clean.groupby("Marca")[
            cols_impute
        ].transform(lambda group: group.fillna(group.mean()))

    # 4. Remoção de registros irrecuperáveis (sem métrica de geração após imputação)
    col_target = "Por_Coletor_KWh_mês"
    if col_target in df_clean.columns:
        df_clean = df_clean.dropna(subset=[col_target])

    print(f"✓ Imputação concluída. Shape final: {df_clean.shape}")

    return df_clean


def main():
    output_file_name = "sistemas-acoplados-equipamentos-solar-de-agua_limpo.csv"

    try:
        df_raw = read_csv_inmetro("sistemas-acoplados-equipamentos-solar-de-agua.csv")
        print(f"Linhas carregadas originalmente: {len(df_raw)}")

        # Mantém apenas modelos vigentes antes de descartar a coluna de status
        df_raw = filter_included_models(df_raw)

        # Execução sequencial da pipeline
        df_e1 = step_1_standardize_columns(df_raw)
        df_e2 = step_2_select_attributes(df_e1)
        df_e3 = step_3_clean_duplicates(df_e2)
        df_e4 = step_4_filter_errors_outliers(df_e3)
        df_final = step_5_imputation(df_e4)
        save_processed(df_final, output_file_name)

        print("\n==================================================")
        print(" PIPELINE DE LIMPEZA CONCLUÍDA COM SUCESSO! ")
        print("==================================================")

    except Exception as e:
        print(f"\n[ERRO NA EXECUÇÃO]: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()