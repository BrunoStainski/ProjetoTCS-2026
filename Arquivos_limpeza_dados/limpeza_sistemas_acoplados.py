"""
Pipeline de Limpeza e Tratamento de Dados - Sistemas Acoplados e Equipamentos Solares de Água (INMETRO)
Projeto: EcoEnergy AI

Etapas:
1. Configuração e Padronização de Colunas
2. Seleção de Atributos (Feature Selection)
3. Tratamento de Duplicatas e Redundâncias
4. Filtragem de Erros e Outliers Irrealistas
5. Imputação Agrupada e Exportação Final
"""

import sys
from pathlib import Path
import numpy as np
import pandas as pd


def localizar_caminhos(nome_entrada: str, nome_saida: str) -> tuple[Path, Path]:
    """Localiza os caminhos de entrada e saída na pasta 'Datasets' a partir da estrutura do projeto."""
    diretorio_script = Path(__file__).resolve().parent
    if diretorio_script.name == "Arquivos_limpeza_dados":
        raiz_projeto = diretorio_script.parent
    else:
        raiz_projeto = Path.cwd()

    pasta_datasets = raiz_projeto / "Datasets"

    # Busca dinâmica caso o nome do arquivo apresente variações no caminho
    caminhos_entrada = list(raiz_projeto.rglob(nome_entrada))
    if not caminhos_entrada:
        caminhos_entrada = list(raiz_projeto.parent.rglob(nome_entrada))

    if caminhos_entrada:
        caminho_entrada = caminhos_entrada[0]
        caminho_saida = caminho_entrada.parent / nome_saida
    else:
        caminho_entrada = pasta_datasets / nome_entrada
        caminho_saida = pasta_datasets / nome_saida

    if not caminho_entrada.exists():
        raise FileNotFoundError(
            f"Arquivo de entrada '{nome_entrada}' não foi localizado em {caminho_entrada}"
        )

    return caminho_entrada, caminho_saida


def etapa_1_padronizar_colunas(df: pd.DataFrame) -> pd.DataFrame:
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


def etapa_2_selecionar_atributos(df: pd.DataFrame) -> pd.DataFrame:
    """Etapa 2: Remove colunas burocráticas, administrativas ou 100% nulas."""
    print("\n--- [Etapa 2/5] Seleção de Atributos (Feature Selection) ---")
    colunas_remover = [
        "Código_de_Barras",
        "Status_do_Modelo",
        "Status_do_Registro",
        "Número_do_Registro",
        "Produção_Média_Mensal_de_Energia",  # Coluna 100% nula no cabeçalho do INMETRO
    ]

    colunas_existentes = [col for col in colunas_remover if col in df.columns]
    df_clean = df.drop(columns=colunas_existentes)
    print(f"✓ {len(colunas_existentes)} colunas administrativas/nulas removidas.")
    return df_clean


def etapa_3_tratar_duplicatas(df: pd.DataFrame) -> pd.DataFrame:
    """Etapa 3: Elimina duplicatas exatas e consolida registros repetidos do mesmo modelo."""
    print("\n--- [Etapa 3/5] Tratamento de Duplicatas e Redundâncias ---")
    qtd_inicial = len(df)

    # 1. Duplicatas exatas
    df_clean = df.drop_duplicates().copy()
    duplicatas_exatas = qtd_inicial - len(df_clean)

    # 2. Modelos repetidos (preserva a versão mais completa)
    if "Modelo" in df_clean.columns:
        df_clean["_qtd_nulos"] = df_clean.isnull().sum(axis=1)
        df_clean = (
            df_clean.sort_values("_qtd_nulos")
            .drop_duplicates(subset=["Modelo"], keep="first")
            .drop(columns=["_qtd_nulos"])
        )

    qtd_removidas = qtd_inicial - len(df_clean)
    print(
        f"✓ Registros duplicados/redundantes removidos: {qtd_removidas} (Duplicatas exatas: {duplicatas_exatas})"
    )
    print(f"  Linhas restantes: {len(df_clean)}")
    return df_clean


def etapa_4_filtrar_erros_outliers(df: pd.DataFrame) -> pd.DataFrame:
    """Etapa 4: Remove registros com valores fisicamente impossíveis ou corrompidos."""
    print("\n--- [Etapa 4/5] Filtragem de Erros e Outliers Irrealistas ---")
    qtd_inicial = len(df)
    df_clean = df.copy()

    # Geração de energia por coletor mínima aceitável (>= 1.0 kWh/mês)
    col_geracao = "Por_Coletor_KWh_mês"
    if col_geracao in df_clean.columns:
        df_clean = df_clean[
            (df_clean[col_geracao].isnull()) | (df_clean[col_geracao] >= 1.0)
        ]

    # Volume do sistema reservatório mínimo aceitável (>= 5.0 Litros)
    col_volume = "Volume_do_Sistema_litros"
    if col_volume in df_clean.columns:
        df_clean = df_clean[
            (df_clean[col_volume].isnull()) | (df_clean[col_volume] >= 5.0)
        ]

    # Eficiência energética média mínima aceitável (>= 5.0%)
    col_eficiencia = "Eficiência_Média_Energética_pct"
    if col_eficiencia in df_clean.columns:
        df_clean = df_clean[
            (df_clean[col_eficiencia].isnull()) | (df_clean[col_eficiencia] >= 5.0)
        ]

    removidos = qtd_inicial - len(df_clean)
    print(f"✓ Linhas com outliers/erros de cadastro removidas: {removidos}")
    print(f"  Linhas restantes: {len(df_clean)}")
    return df_clean


def etapa_5_imputacao_e_exportacao(
    df: pd.DataFrame, caminho_saida: Path
) -> pd.DataFrame:
    """Etapa 5: Realiza a imputação inteligente por Marca/Classificação e exporta o CSV limpo."""
    print("\n--- [Etapa 5/5] Imputação Inteligente e Exportação ---")
    df_clean = df.copy()

    cols_numericas = [
        "Por_Coletor_KWh_mês",
        "Volume_do_Sistema_litros",
        "Por_m2_KWh_Mês.m2",
        "Eficiência_Média_Energética_pct",
        "Area_Externa_do_Coletor_M2",
    ]
    cols_imputar = [c for c in cols_numericas if c in df_clean.columns]

    # 1. Imputação por Marca + Classificação
    if {"Marca", "Classificação"}.issubset(df_clean.columns) and cols_imputar:
        df_clean[cols_imputar] = df_clean.groupby(["Marca", "Classificação"])[
            cols_imputar
        ].transform(lambda group: group.fillna(group.mean()))

    # 2. Fallback por Classificação
    if "Classificação" in df_clean.columns and cols_imputar:
        df_clean[cols_imputar] = df_clean.groupby("Classificação")[
            cols_imputar
        ].transform(lambda group: group.fillna(group.mean()))

    # 3. Fallback por Marca
    if "Marca" in df_clean.columns and cols_imputar:
        df_clean[cols_imputar] = df_clean.groupby("Marca")[
            cols_imputar
        ].transform(lambda group: group.fillna(group.mean()))

    # 4. Remoção de registros irrecuperáveis (sem métrica de geração após imputação)
    col_alvo = "Por_Coletor_KWh_mês"
    if col_alvo in df_clean.columns:
        df_clean = df_clean.dropna(subset=[col_alvo])

    # Exportação para CSV
    df_clean.to_csv(caminho_saida, index=False, encoding="utf-8-sig")
    print(f"✓ Imputação concluída com sucesso.")
    print(f"✓ Base limpa final exportada para: {caminho_saida}")
    print(f"  Shape final da base: {df_clean.shape[0]} linhas x {df_clean.shape[1]} colunas")

    return df_clean


def main():
    nome_arquivo_entrada = "sistemas-acoplados-equipamentos-solar-de-agua.csv"
    nome_arquivo_saida = "sistemas-acoplados-equipamentos-solar-de-agua_limpo.csv"

    try:
        caminho_entrada, caminho_saida = localizar_caminhos(
            nome_arquivo_entrada, nome_arquivo_saida
        )

        print(f"Lendo dataset inicial de: {caminho_entrada}")
        df_raw = pd.read_csv(caminho_entrada)
        print(f"Linhas carregadas originalmente: {len(df_raw)}")

        # Execução sequencial da pipeline
        df_e1 = etapa_1_padronizar_colunas(df_raw)
        df_e2 = etapa_2_selecionar_atributos(df_e1)
        df_e3 = etapa_3_tratar_duplicatas(df_e2)
        df_e4 = etapa_4_filtrar_erros_outliers(df_e3)
        df_final = etapa_5_imputacao_e_exportacao(df_e4, caminho_saida)

        print("\n==================================================")
        print(" PIPELINE DE LIMPEZA CONCLUÍDA COM SUCESSO! ")
        print("==================================================")

    except Exception as e:
        print(f"\n[ERRO NA EXECUÇÃO]: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()