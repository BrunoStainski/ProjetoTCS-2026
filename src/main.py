"""
API do iamp (FastAPI). Usa as funcoes de servico.py e devolve JSON para o app Flutter.

Rodar sem Docker (dentro de src/):  uvicorn main:app --reload
Documentacao e testes pelo navegador: http://localhost:8000/docs

Na primeira subida, se o banco estiver vazio, a API carrega os CSVs limpos sozinha.
Para forcar uma nova carga: RECARREGAR_BANCO=1.
"""

import os
import time
from contextlib import asynccontextmanager
from datetime import date
from typing import Literal, Optional, Union

from fastapi import Depends, FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
from pydantic import BaseModel, Field, model_validator

import banco
import estimativa
import ml_pipeline
import rag_agent
import servico
from calculadora_residencial import LIMITE_BUSCA, LIMITE_MODELOS_MARCA
from criar_banco import COLUNAS_APARELHOS


def esperar_banco(tentativas=30, pausa=2):
    for numero in range(1, tentativas + 1):
        try:
            return banco.conectar()
        except ConnectionError:
            print(f"aguardando o PostgreSQL ({numero}/{tentativas})...", flush=True)
            time.sleep(pausa)
    raise RuntimeError("PostgreSQL nao respondeu a tempo")


def banco_carregado(con):
    # banco com a tabela fogoes e de antes da saida do gas de cozinha: recarrega para apagar
    sql = ("SELECT to_regclass('public.aparelhos') IS NOT NULL "
           "AND to_regclass('public.vw_tarifa_vigente') IS NOT NULL "
           "AND to_regclass('public.portateis') IS NOT NULL "
           "AND to_regclass('public.fogoes') IS NULL")
    if not banco.executar(con, sql).scalar_one():
        return False
    # banco criado por uma versao antiga do codigo (falta coluna nova): recarrega
    sql = "SELECT column_name FROM information_schema.columns WHERE table_name = 'aparelhos'"
    colunas = set(banco.consulta(con, sql)["column_name"])
    if not set(COLUNAS_APARELHOS) <= colunas:
        print("esquema do banco desatualizado", flush=True)
        return False
    return banco.executar(con, "SELECT COUNT(*) FROM aparelhos").scalar_one() > 0


def carregar_dados(con):
    from criar_banco import carregar_aparelhos, carregar_dados_extras, carregar_distribuidoras_e_tarifas

    con.exec_driver_sql(banco.ESQUEMA)
    aparelhos = carregar_aparelhos(con)
    distribuidoras, tarifas = carregar_distribuidoras_e_tarifas(con)
    carregar_dados_extras(con)
    con.commit()
    print(f"dados carregados: {aparelhos} aparelhos, {distribuidoras} distribuidoras, {tarifas} tarifas", flush=True)


@asynccontextmanager
async def ciclo_de_vida(app):
    con = esperar_banco()
    try:
        if os.getenv("RECARREGAR_BANCO") == "1" or not banco_carregado(con):
            print("banco vazio ou desatualizado, carregando os dados...", flush=True)
            carregar_dados(con)
    finally:
        con.close()
    yield


app = FastAPI(
    title="iamp API",
    description="Estima o consumo e o custo mensal de energia de aparelhos eletricos residenciais.",
    version="0.4.0",
    lifespan=ciclo_de_vida,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip() for o in os.getenv("CORS_ORIGINS", "*").split(",")],
    allow_methods=["*"],
    allow_headers=["*"],
)


class AparelhoResumo(BaseModel):
    id: int
    categoria: str
    marca: str
    modelo: str
    detalhe: Optional[str] = None


class AparelhoEncontrado(AparelhoResumo):
    total_categoria: int  # quantos modelos desse tipo batem com a busca (pode passar do limite)


class MarcaResumo(BaseModel):
    marca: str
    modelos: int  # quantos modelos a marca tem nesse tipo de aparelho


class PerguntaDeUso(BaseModel):
    pergunta: Optional[Literal["velocidade", "ciclos", "horas"]] = Field(
        None, description="O que o app precisa perguntar. null = nada, o consumo ja vem do Inmetro."
    )
    opcoes: Optional[list[str]] = Field(None, description="Opcoes de velocidade, quando a pergunta e velocidade.")
    padrao: Union[float, str, None] = Field(None, description="Valor sugerido. null = o usuario precisa informar.")
    opcional: bool = Field(False, description="true = o usuario pode deixar em branco e fica o valor do Inmetro.")
    perguntar_horas: bool = Field(False, description="true = depois da velocidade, pergunta as horas por dia.")


class Distribuidora(BaseModel):
    id: int
    nome: str
    uf: Optional[str] = None
    tarifa_kwh: float
    vigencia_inicio: Optional[date] = None
    fonte: Optional[str] = None


class Tarifa(BaseModel):
    distribuidora_id: Optional[int] = Field(None, description="Id vindo de GET /distribuidoras.")
    tarifa_manual: Optional[float] = Field(None, gt=0, description="R$/kWh da conta de luz do usuario.")

    @model_validator(mode="after")
    def exigir_uma_tarifa(self):
        if (self.distribuidora_id is None) == (self.tarifa_manual is None):
            raise ValueError("informe distribuidora_id ou tarifa_manual (apenas um dos dois)")
        return self

    def tarifa(self):
        return self.model_dump(include={"distribuidora_id", "tarifa_manual"})


class UsoETarifa(Tarifa):
    """Campos comuns: como o aparelho e usado e qual tarifa vale."""
    horas_dia: Optional[float] = Field(None, ge=0, le=24)
    ciclos_mes: Optional[float] = Field(None, ge=0)
    velocidade: Optional[Literal["baixa", "media", "alta"]] = None

    def uso_e_tarifa(self):
        return self.model_dump(include={"distribuidora_id", "tarifa_manual", "horas_dia", "ciclos_mes", "velocidade"})


class CalculoEntrada(UsoETarifa):
    aparelho_id: int
    registrar: bool = Field(True, description="Grava o calculo no historico (tabela consultas).")


class SugestaoEntrada(UsoETarifa):
    aparelho_id: int = Field(..., description="Aparelho que o usuario tem hoje.")
    limite: int = Field(5, ge=1, le=10)


class ComparacaoEntrada(UsoETarifa):
    aparelho_id: int = Field(..., description="Aparelho que o usuario tem hoje.")
    alternativa_id: int = Field(..., description="Modelo novo (normalmente vindo de POST /sugestoes).")
    preco_novo: Optional[float] = Field(None, gt=0, description="Preco do modelo novo em R$, para o payback.")


class Resultado(BaseModel):
    categoria: str
    marca: str
    modelo: str
    detalhe: str = ""
    distribuidora: str
    uf: str
    horas_dia: Optional[float] = None
    kwh_mes: float
    metodo: str
    tarifa_kwh: float
    origem_tarifa: str
    custo_mes: float
    custo_ano: float
    avisos: list[str]
    fonte_dados: str
    aproximado: bool = Field(False, description="true = gasto aproximado (modelo fora do catalogo ou valor padrao).")
    kwh_min: Optional[float] = Field(None, description="Faixa da estimativa, quando aproximada.")
    kwh_max: Optional[float] = None
    custo_min_mes: Optional[float] = None
    custo_max_mes: Optional[float] = None
    tipo: Optional[str] = Field(None, description="Tipo do Inmetro do aparelho estimado (para sugerir equivalentes).")
    capacidade: Optional[float] = Field(None, description="Medida do aparelho estimado (L, kg, BTU/h, pol, cm, W ou cv).")
    pelos_parecidos: bool = Field(False, description="true = gasto da mediana dos modelos parecidos (sem numero do aparelho).")


class EstimadoEntrada(UsoETarifa):
    categoria: str = Field(..., description="Categoria de GET /estimativa/categorias (menos refrigerador).")
    tipo: Optional[str] = None
    medida: Optional[float] = Field(None, gt=0, description="Tamanho do aparelho na unidade da categoria.")
    valor_etiqueta: Optional[float] = Field(None, gt=0, description="Numero escrito no aparelho, na unidade da forma.")
    campo_etiqueta: Optional[Literal["kwh_mes", "kwh_ciclo", "potencia_w"]] = Field(
        None, description="Qual das 'formas' da categoria e o valor_etiqueta. null = a primeira.")
    marca: Optional[str] = Field(None, max_length=60)
    modelo: Optional[str] = Field(None, max_length=60)
    registrar: bool = True


class TipoEstimavel(BaseModel):
    valor: str = Field(..., description="Tipo do Inmetro (vai em EstimadoEntrada.tipo).")
    nome: str
    descricao: Optional[str] = None


class TamanhoComum(BaseModel):
    valor: float
    nome: str


class FormaDeInformar(BaseModel):
    campo: Literal["kwh_mes", "kwh_ciclo", "potencia_w"]
    nome: str
    rotulo: str
    unidade: str
    onde: str
    dica: Optional[str] = None
    exemplo: str
    maximo: float


class CategoriaEstimavel(BaseModel):
    categoria: str
    nome: str
    especial: bool
    medida: Optional[str] = None
    unidade_medida: Optional[str] = None
    tamanhos: list[TamanhoComum]
    tipos: list[TipoEstimavel]
    formas: list[FormaDeInformar] = Field(..., description="Numeros do proprio aparelho que o usuario pode informar.")
    valor_obrigatorio: bool = Field(..., description="true = sem catalogo para comparar; precisa de uma das formas.")
    uso: PerguntaDeUso


class SugestaoEstimadaEntrada(UsoETarifa):
    categoria: str
    capacidade: Optional[float] = Field(None, gt=0)
    kwh_mes: float = Field(..., gt=0, description="kwh_mes do resultado da estimativa.")
    tipo: Optional[str] = None
    nome: Optional[str] = Field(None, max_length=120)
    limite: int = Field(5, ge=1, le=10)
    pelos_parecidos: bool = Field(False, description="Copie de Resultado.pelos_parecidos.")


class ComparacaoEstimadaEntrada(UsoETarifa):
    categoria: str
    kwh_mes: float = Field(..., gt=0, description="kwh_mes do resultado da estimativa.")
    alternativa_id: int
    nome: Optional[str] = Field(None, max_length=120)
    preco_novo: Optional[float] = Field(None, gt=0)


class RefrigeradorAntigoEntrada(Tarifa):
    tipo: Literal[tuple(estimativa.TIPOS)] = Field(..., description="1_porta, frigobar, duplex, freezer_vertical ou freezer_horizontal.")
    frost_free: bool
    volume_total_l: float = Field(..., gt=0, le=estimativa.VOLUME_MAXIMO_L)
    volume_congelador_l: Optional[float] = Field(None, ge=0, description="Volume do freezer. Em branco = proporcao tipica do tipo.")
    ano_compra: int = Field(..., ge=estimativa.ANO_MINIMO)
    kwh_etiqueta: Optional[float] = Field(None, gt=0, le=300, description="kWh/mes da etiqueta do Inmetro colada no aparelho.")
    marca: Optional[str] = Field(None, max_length=60)
    modelo: Optional[str] = Field(None, max_length=60)
    registrar: bool = True


class ResistivoEntrada(Tarifa):
    categoria: str = Field(..., max_length=40, description="Categoria de GET /resistivos. Ex.: air_fryer")
    potencia_w: Optional[float] = Field(None, gt=0, le=10000, description="Potencia da etiqueta. Em branco = tipica da categoria.")
    horas_dia: Optional[float] = Field(None, ge=0, le=24)
    dias_mes: Optional[float] = Field(None, ge=0, le=31)
    registrar: bool = True


class Resistivo(BaseModel):
    categoria: str
    nome: str
    potencia_w: float
    horas_dia: float
    dias_mes: float
    fonte: str


class ItemConsumo(BaseModel):
    categoria: str = Field(..., description="Categoria do aparelho (GET /categorias). Ex.: chuveiro")
    kwh_mes: float = Field(..., ge=0, description="Consumo mensal, normalmente o kwh_mes de POST /calcular.")


class ClassificacaoEntrada(BaseModel):
    moradores: int = Field(..., ge=1, le=20)
    itens: list[ItemConsumo] = Field(..., min_length=1, description="Aparelhos da casa com o consumo de cada um.")


class ComparacaoMedia(BaseModel):
    mediana_kwh_por_morador: float
    diferenca_percentual: float
    texto: str


class Classificacao(BaseModel):
    perfil: Literal["Consciente", "Moderado", "Ineficiente"]
    kwh_total: float
    kwh_por_morador: float
    comparacao_media: ComparacaoMedia
    fracoes: dict[str, float]
    aviso: str
    fonte: str


class AparelhoConsumo(AparelhoResumo):
    tipo: str = ""
    kwh_mes: float
    custo_mes: float


class AparelhoSugerido(AparelhoConsumo):
    economia_kwh_mes: float
    economia_mes: float
    economia_ano: float
    economia_percentual: float


class Sugestoes(BaseModel):
    atual: AparelhoConsumo
    tarifa_kwh: float
    criterio: Optional[str] = Field(None, description="Como os modelos equivalentes foram escolhidos.")
    mensagem: Optional[str] = Field(None, description="Explica por que nao ha sugestao, quando a lista vem vazia.")
    suspeitos_descartados: int = Field(0, description="Modelos com consumo baixo demais para ser real (provavel erro no dado).")
    sugestoes: list[AparelhoSugerido]


class Payback(BaseModel):
    preco_novo: float
    meses: Optional[float] = Field(None, description="null = a troca nao se paga pela conta de luz.")
    anos: Optional[float] = None
    texto: str


class Comparacao(BaseModel):
    atual: Resultado
    novo: Resultado
    economia_kwh_mes: float
    economia_mes: float
    economia_ano: float
    payback: Optional[Payback] = Field(None, description="So vem quando preco_novo e informado.")
    avisos: list[str]


def conexao():
    try:
        con = banco.conectar()
    except ConnectionError as erro:
        raise HTTPException(status_code=503, detail="banco de dados indisponivel") from erro
    try:
        yield con
    finally:
        con.close()


def erro_do_servico(erro):
    mensagem = str(erro)
    nao_achou = "nao existe" in mensagem or "sem tarifa vigente" in mensagem
    return HTTPException(status_code=404 if nao_achou else 422, detail=mensagem)


@app.get("/", include_in_schema=False)
def inicio():
    return RedirectResponse("/docs")


@app.get("/saude", tags=["Sistema"])
def saude(con=Depends(conexao)):
    banco.executar(con, "SELECT 1")
    return {"status": "ok"}


@app.get("/categorias", response_model=list[str], tags=["Aparelhos"])
def listar_categorias(con=Depends(conexao)):
    return banco.categorias(con)


@app.get("/aparelhos", response_model=list[AparelhoEncontrado], tags=["Aparelhos"])
def buscar_aparelhos(
    busca: str = Query(..., min_length=2, description="Marca e/ou modelo. Ex.: brastemp brm44"),
    categoria: Optional[str] = Query(None, description="Filtra por categoria. Ver GET /categorias."),
    limite: int = Query(LIMITE_BUSCA, ge=1, le=50, description="Maximo de modelos por tipo de aparelho."),
    con=Depends(conexao),
):
    return servico.buscar_modelos(con, busca, categoria, limite)


@app.get("/marcas", response_model=list[MarcaResumo], tags=["Aparelhos"])
def listar_marcas(
    categoria: str = Query(..., description="Tipo de aparelho. Ver GET /categorias."),
    con=Depends(conexao),
):
    """Marcas de um tipo de aparelho, com a quantidade de modelos (tipo que nao existe: lista vazia)."""
    return servico.listar_marcas(con, categoria)


@app.get("/modelos", response_model=list[AparelhoEncontrado], tags=["Aparelhos"])
def listar_modelos_da_marca(
    categoria: str = Query(..., description="Tipo de aparelho. Ver GET /categorias."),
    marca: str = Query(..., min_length=1, description="Marca, como veio do GET /marcas (sem diferenciar maiusculas)."),
    limite: int = Query(LIMITE_MODELOS_MARCA, ge=1, le=500),
    con=Depends(conexao),
):
    """Modelos de uma marca dentro de um tipo. total_categoria = quantos a marca tem nesse tipo."""
    return servico.modelos_da_marca(con, categoria, marca, limite)


@app.get("/aparelhos/{aparelho_id}/uso", response_model=PerguntaDeUso, tags=["Aparelhos"])
def pergunta_de_uso(aparelho_id: int, con=Depends(conexao)):
    try:
        return servico.dados_de_uso(con, aparelho_id)
    except ValueError as erro:
        raise erro_do_servico(erro) from erro


@app.get("/ufs", response_model=list[str], tags=["Distribuidoras"])
def listar_ufs(con=Depends(conexao)):
    return servico.listar_ufs(con)


@app.get("/distribuidoras", response_model=list[Distribuidora], tags=["Distribuidoras"])
def listar_distribuidoras(
    uf: Optional[str] = Query(None, pattern="^[A-Za-z]{2}$", description="Sigla do estado. Ex.: PR"),
    busca: Optional[str] = Query(None, description="Parte do nome. Ex.: copel"),
    con=Depends(conexao),
):
    return servico.listar_distribuidoras(con, uf=uf, busca=busca)


@app.post("/calcular", response_model=Resultado, tags=["Calculo"])
def calcular(entrada: CalculoEntrada, con=Depends(conexao)):
    try:
        return servico.calcular(con, entrada.aparelho_id, registrar=entrada.registrar, **entrada.uso_e_tarifa())
    except ValueError as erro:
        raise erro_do_servico(erro) from erro


@app.post("/calcular/refrigerador-antigo", response_model=Resultado, tags=["Calculo"])
def calcular_refrigerador_antigo(entrada: RefrigeradorAntigoEntrada, con=Depends(conexao)):
    """Geladeira fora do catalogo: usa a etiqueta, se houver; senao estima por tipo, volume e ano de compra."""
    try:
        consumo = estimativa.consumo_refrigerador_estimado(
            entrada.tipo, entrada.frost_free, entrada.volume_total_l, entrada.ano_compra,
            volume_congelador_l=entrada.volume_congelador_l, kwh_etiqueta=entrada.kwh_etiqueta)
        return servico.calcular_estimado(con, consumo, marca=entrada.marca, modelo=entrada.modelo,
                                         registrar=entrada.registrar, **entrada.tarifa())
    except FileNotFoundError as erro:
        raise HTTPException(status_code=503, detail="modelo de estimativa indisponivel") from erro
    except ValueError as erro:
        raise erro_do_servico(erro) from erro


@app.get("/resistivos", response_model=list[Resistivo], tags=["Calculo"])
def listar_resistivos(con=Depends(conexao)):
    """Eletroportateis (tabela portateis) e os valores padrao usados quando o usuario nao informa."""
    return servico.listar_portateis(con)


@app.post("/calcular/resistivo", response_model=Resultado, tags=["Calculo"])
def calcular_resistivo(entrada: ResistivoEntrada, con=Depends(conexao)):
    """kWh/mes = potencia (W) / 1000 x horas por dia x dias de uso no mes."""
    try:
        padrao = servico.portatil(con, entrada.categoria)
        consumo = estimativa.consumo_resistivo(padrao, entrada.potencia_w, entrada.horas_dia, entrada.dias_mes)
        return servico.calcular_estimado(con, consumo, registrar=entrada.registrar, **entrada.tarifa())
    except ValueError as erro:
        raise erro_do_servico(erro) from erro


@app.get("/estimativa/categorias", response_model=list[CategoriaEstimavel], tags=["Calculo"])
def listar_categorias_estimaveis(con=Depends(conexao)):
    """Eletro pesado que da para estimar quando o modelo nao esta no catalogo, e o que perguntar de cada um."""
    return servico.categorias_estimaveis(con)


@app.post("/calcular/estimado", response_model=Resultado, tags=["Calculo"])
def calcular_estimado(entrada: EstimadoEntrada, con=Depends(conexao)):
    """Aparelho fora do catalogo: valor da etiqueta, se houver; senao a mediana dos modelos parecidos."""
    try:
        consumo = servico.estimar_por_equivalentes(
            con, entrada.categoria, entrada.tipo, entrada.medida, entrada.valor_etiqueta,
            entrada.horas_dia, entrada.ciclos_mes, entrada.velocidade, entrada.campo_etiqueta)
        return servico.calcular_estimado(con, consumo, marca=entrada.marca, modelo=entrada.modelo,
                                         registrar=entrada.registrar, **entrada.tarifa())
    except ValueError as erro:
        raise erro_do_servico(erro) from erro


@app.post("/sugestoes/estimado", response_model=Sugestoes, tags=["Economia"])
def sugerir_para_estimado(entrada: SugestaoEstimadaEntrada, con=Depends(conexao)):
    """Modelos do catalogo que gastam menos que um aparelho estimado (mesmo criterio de POST /sugestoes)."""
    try:
        return servico.sugerir_para_estimado(
            con, entrada.categoria, entrada.capacidade, entrada.kwh_mes, tipo=entrada.tipo, nome=entrada.nome,
            limite=entrada.limite, pelos_parecidos=entrada.pelos_parecidos, **entrada.uso_e_tarifa())
    except ValueError as erro:
        raise erro_do_servico(erro) from erro


@app.post("/comparar/estimado", response_model=Comparacao, tags=["Economia"])
def comparar_estimado(entrada: ComparacaoEstimadaEntrada, con=Depends(conexao)):
    """Economia e payback de trocar um aparelho estimado por um modelo do catalogo."""
    try:
        return servico.comparar_estimado(
            con, entrada.categoria, entrada.kwh_mes, entrada.alternativa_id, nome=entrada.nome,
            preco_novo=entrada.preco_novo, **entrada.uso_e_tarifa())
    except ValueError as erro:
        raise erro_do_servico(erro) from erro


@app.post("/sugestoes", response_model=Sugestoes, tags=["Economia"])
def sugerir(entrada: SugestaoEntrada, con=Depends(conexao)):
    """Modelos equivalentes (mesmo servico) que gastam pelo menos 5% menos, com o mesmo uso e tarifa."""
    try:
        return servico.sugerir_alternativas(con, entrada.aparelho_id, limite=entrada.limite, **entrada.uso_e_tarifa())
    except ValueError as erro:
        raise erro_do_servico(erro) from erro


@app.post("/comparar", response_model=Comparacao, tags=["Economia"])
def comparar(entrada: ComparacaoEntrada, con=Depends(conexao)):
    """Economia de trocar o aparelho atual pelo novo e, com preco_novo, o payback (em meses)."""
    try:
        return servico.comparar(con, entrada.aparelho_id, entrada.alternativa_id,
                                preco_novo=entrada.preco_novo, **entrada.uso_e_tarifa())
    except ValueError as erro:
        raise erro_do_servico(erro) from erro


@app.post("/classificar", response_model=Classificacao, tags=["Perfil (ML)"])
def classificar(entrada: ClassificacaoEntrada):
    """Perfil de consumo da casa (K-Means treinado com residencias sinteticas)."""
    try:
        return ml_pipeline.classificar_residencia(entrada.model_dump())
    except FileNotFoundError as erro:
        raise HTTPException(status_code=503, detail="modelo de perfil indisponivel") from erro
    except ValueError as erro:
        raise HTTPException(status_code=422, detail=str(erro)) from erro


# Eco-Coach (RAG + LLM) -------------------------------------------------------------------

class ItemEco(ItemConsumo):
    custo_mes: Optional[float] = Field(None, ge=0, description="R$/mes do aparelho (custo_mes de POST /calcular).")


class TrocaAvaliada(BaseModel):
    aparelho: str = Field(..., description="Aparelho atual. Ex.: geladeira Brastemp BRM44")
    alternativa: str = Field(..., description="Modelo sugerido. Ex.: geladeira Electrolux TF39")
    economia_mes: float = Field(..., description="R$/mes economizados (de POST /comparar).")
    payback_meses: Optional[float] = Field(None, ge=0, description="Meses para a troca se pagar (de /comparar).")


class EcoCoachEntrada(BaseModel):
    moradores: int = Field(..., ge=1, le=20)
    itens: list[ItemEco] = Field(..., min_length=1, description="Aparelhos da casa com consumo (e custo).")
    trocas: list[TrocaAvaliada] = Field(default_factory=list, max_length=5,
                                        description="Trocas ja calculadas no /comparar (opcional).")


class FonteCitada(BaseModel):
    n: int
    documento: str
    orgao: str
    url: str
    secao: Optional[str] = None
    pagina: Optional[int] = None


class MaiorConsumo(BaseModel):
    categoria: str
    nome: str
    kwh_mes: float
    custo_mes: Optional[float] = None
    percentual: float


class EcoCoach(BaseModel):
    perfil: Literal["Consciente", "Moderado", "Ineficiente"]
    kwh_total: float
    custo_total: Optional[float] = None
    maiores_consumos: list[MaiorConsumo]
    plano: str = Field(..., description="Texto em markdown; as citacoes [n] apontam para 'fontes'.")
    fontes: list[FonteCitada]
    modelo: str
    aviso: str


@app.post("/eco-coach", response_model=EcoCoach, tags=["Eco-Coach (RAG)"])
def eco_coach(entrada: EcoCoachEntrada, con=Depends(conexao)):
    """Plano de acao em linguagem simples, com dicas oficiais citadas. Os numeros sao calculados
    pelo iamp; o LLM (Gemini) so escreve. Pode levar alguns segundos."""
    dados = entrada.model_dump()
    try:
        return rag_agent.gerar_plano(con, dados, trocas=dados.pop("trocas"))
    except ValueError as erro:
        raise HTTPException(status_code=422, detail=str(erro)) from erro
    except FileNotFoundError as erro:
        raise HTTPException(status_code=503, detail="modelo de perfil indisponivel") from erro
    except (LookupError, RuntimeError) as erro:
        raise HTTPException(status_code=503, detail=f"Eco-Coach indisponivel: {erro}") from erro


class DicasEntrada(BaseModel):
    categoria: str = Field(..., max_length=40)
    nome: str = Field(..., max_length=120)
    kwh_mes: float = Field(..., ge=0)
    custo_mes: float = Field(..., ge=0)
    metodo: Optional[str] = Field(None, max_length=400, description="Texto 'metodo' de POST /calcular.")


class DicasDoAparelho(BaseModel):
    dicas: str = Field(..., description="Texto em markdown; as citacoes [n] apontam para 'fontes'.")
    fontes: list[FonteCitada]
    modelo: str
    aviso: str


@app.post("/eco-coach/aparelho", response_model=DicasDoAparelho, tags=["Eco-Coach (RAG)"])
def eco_coach_aparelho(entrada: DicasEntrada, con=Depends(conexao)):
    """Dicas personalizadas para gastar menos com um aparelho (usado nos eletroportateis)."""
    try:
        return rag_agent.gerar_dicas_do_aparelho(con, entrada.model_dump())
    except ValueError as erro:
        raise HTTPException(status_code=422, detail=str(erro)) from erro
    except (LookupError, RuntimeError) as erro:
        raise HTTPException(status_code=503, detail=f"Eco-Coach indisponivel: {erro}") from erro
