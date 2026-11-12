"""
Pipeline de Limpeza e Tratamento de Dados - Refrigeradores e Assemelhados (INMETRO)
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
    """Etapa 2: Remove colunas burocráticas, de texto livre ou sem valor preditivo."""
    print("\n--- [Etapa 2/5] Seleção de Atributos (Feature Selection) ---")
    remove_columns = [
        "Se_outro_fluido_refrigerante,_especificar",
        "Se_outro_agente_de_expansão,_especificar",
        "Código_de_Barras",
        "Status_do_Modelo",
        "Status_do_Registro",
        "Número_do_Registro",
        "Norma_de_Segurança_Aplicada_IEC_60335-2-24",
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

    # 2. Modelos repetidos (mantém a linha com menor número de valores nulos)
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

    # Consumo energético mensal mínimo aceitável (ex: >= 5 kWh/mês)
    col_consumption = "Consumo_de_Energia_Mensal_kWh_mês"
    if col_consumption in df_clean.columns:
        df_clean = df_clean[
            (df_clean[col_consumption].isnull()) | (df_clean[col_consumption] >= 5.0)
        ]

    # Volume total mínimo aceitável (ex: >= 10 Litros)
    col_volume = "Volume_Total_L"
    if col_volume in df_clean.columns:
        df_clean = df_clean[
            (df_clean[col_volume].isnull()) | (df_clean[col_volume] >= 10.0)
        ]

    removed = initial_qty - len(df_clean)
    print(f"✓ Linhas com outliers/erros de cadastro removidas: {removed}")
    print(f"  Linhas restantes: {len(df_clean)}")
    return fix_total_volume(df_clean)


def fix_total_volume(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    total = "Volume_Total_litros"
    refrigerator = "Volume_do_Refrigerador_litros"
    stars = [c for c in df.columns if c.startswith("Volume_do_Compartimento_de_Alimentos_Congelados")]
    df["Volume_Corrigido"] = False
    if not {total, refrigerator}.issubset(df.columns):
        return df
    summed = df[refrigerator] + df[stars].fillna(0).sum(axis=1)
    wrong = df[refrigerator].notna() & (df[total] < df[refrigerator])
    key = ["Marca", total] + stars
    corrected = df.loc[wrong, key].assign(_novo=summed[wrong])
    df.loc[wrong, total] = summed[wrong]
    df.loc[wrong, "Volume_Corrigido"] = True
    if len(corrected):
        siblings = df[df[refrigerator].isna()].reset_index().merge(corrected, on=key, how="inner")
        for _, line in siblings.iterrows():
            df.loc[line["index"], total] = line["_novo"]
            df.loc[line["index"], "Volume_Corrigido"] = True
    print(f"✓ Volume total corrigido (menor que o do refrigerador): {int(df['Volume_Corrigido'].sum())} linha(s)")
    return df


def step_5_imputation(df: pd.DataFrame) -> pd.DataFrame:
    """Etapa 5: Realiza a imputação inteligente agrupada por Marca + Tipo e exporta o CSV limpo."""
    print("\n--- [Etapa 5/5] Imputação Inteligente ---")
    df_clean = df.copy()

    cols_numeric = [
        "Consumo_de_Energia_Mensal_kWh_mês",
        "Volume_Total_L",
        "Volume_Compartimento_Refrigerador_L",
        "Volume_Compartimento_Congelador_L",
    ]
    cols_impute = [c for c in cols_numeric if c in df_clean.columns]

    # Marca as linhas cujo consumo vai ser preenchido pela média (o app avisa o usuário).
    # Modelos do padrão 2025 trazem o consumo em outra coluna, que não é imputada.
    consumption = df_clean["Consumo_de_Energia_Mensal_kWh_mês"].isna()
    col_2025 = next((c for c in df_clean.columns
                     if c.lower().startswith("consumo_médio_de_energia_mensal")
                     or c.lower().startswith("consumo_medio_de_energia_mensal")), None)
    has_2025 = pd.to_numeric(df_clean[col_2025], errors="coerce").notna() if col_2025 else False
    has_only_2025 = consumption & has_2025
    consumption &= ~has_2025
    df_clean["Consumo_Imputado"] = consumption

    # 1. Imputação por Marca + Tipo
    if {"Marca", "Tipo"}.issubset(df_clean.columns) and cols_impute:
        df_clean[cols_impute] = df_clean.groupby(["Marca", "Tipo"])[
            cols_impute
        ].transform(lambda group: group.fillna(group.mean()))

    # 2. Fallback por Tipo (para casos onde a Marca tinha apenas um modelo incompleto)
    if "Tipo" in df_clean.columns and cols_impute:
        df_clean[cols_impute] = df_clean.groupby("Tipo")[cols_impute].transform(
            lambda group: group.fillna(group.mean())
        )

    col_target = "Consumo_de_Energia_Mensal_kWh_mês"
    df_clean.loc[has_only_2025, col_target] = float("nan")

    # 3. Remoção de registros irrecuperáveis (sem consumo mesmo após imputação)
    if col_target in df_clean.columns:
        has_consumption = df_clean[col_target].notna() | (
            pd.to_numeric(df_clean[col_2025], errors="coerce").notna() if col_2025 else False)
        df_clean = df_clean[has_consumption]

    print(f"✓ Imputação concluída. Shape final: {df_clean.shape}")

    return df_clean


def main():
    output_file_name = "refrigeradores-e-assemelhados_limpo.csv"

    try:
        df_raw = read_csv_inmetro("refrigeradores-e-assemelhados.csv")
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