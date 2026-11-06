# Gráficos da EDA

Gerados por `notebooks/eda.ipynb` (rodar de novo recria todos). Cada gráfico tem a tabela
com os números logo abaixo, no notebook.

| Arquivo | O que mostra | Fonte |
|---|---|---|
| `01_catalogo_por_categoria.png` | Modelos no catálogo por categoria | Inmetro / PBE |
| `02_consumo_tipico_categoria.png` | kWh/mês do modelo mediano de cada categoria, com uso padrão | Inmetro + premissas do grupo |
| `03_tarifa_por_uf.png` | Tarifa B1 vigente por estado (mediana e faixa) | ANEEL |
| `04_kwh_morador_seed_vs_sintetica.png` | Distribuição do kWh por morador, seed × CTGAN | dados sintéticos |
| `05_aparelhos_seed_vs_sintetica.png` | % de casas com cada aparelho opcional | dados sintéticos |
| `06_moradores_seed_vs_sintetica.png` | Distribuição de moradores (limitação do CTGAN) | dados sintéticos |
| `07_perfis_kmeans_dispersao.png` | Perfis do K-Means: kWh/morador × fração do chuveiro | dados sintéticos |
| `08_perfis_composicao.png` | kWh médio por grupo de aparelho em cada perfil | dados sintéticos |

Cores: paleta categórica validada para daltonismo (azul, laranja, aqua, amarelo, magenta, nessa
ordem). Os perfis usam um só tom de azul, do claro ao escuro, porque são ordenados. As três
cores mais claras têm pouco contraste com o fundo, então os gráficos sempre trazem legenda e
rótulos com os valores.
