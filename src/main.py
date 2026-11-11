"""
API do iamp (FastAPI). Usa as funcoes de servico.py e devolve JSON para o app Flutter.

Rodar sem Docker (dentro de src/):  uvicorn main:app --reload
Documentacao e testes pelo navegador: http://localhost:8000/docs

Na primeira subida, se o banco estiver vazio, a API carrega os CSVs limpos sozinha.
Para forcar uma nova carga: RECARREGAR_BANCO=1.

Idioma: com o cabecalho "Accept-Language: en" os textos da resposta (metodo, avisos, mensagens,
erros, plano do Eco-Coach) vem em ingles; sem ele, em portugues (ver idioma.py).
"""

import os
import time
from contextlib import asynccontextmanager
from datetime import date
from typing import Literal, Optional, Union

from fastapi import Depends, FastAPI, HTTPException, Path, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
from pydantic import BaseModel, ConfigDict, Field, model_validator

import banco
import config
import estimativa
import idioma
import ml_pipeline
import rag
import rag_agent
import servico
from calculadora_residencial import SEARCH_LIMIT, BRAND_MODEL_LIMIT
from criar_banco import APPLIANCE_COLUMNS


# Contrato com o app: o JSON da API continua com os nomes em portugues (o app le essas chaves como
# texto). No codigo os campos tem nome em ingles; o alias liga um ao outro nas duas direcoes.
JSON_NAMES = {
    "agency": "orgao",
    "alternative": "alternativa",
    "alternative_id": "alternativa_id",
    "appliance": "aparelho",
    "appliance_id": "aparelho_id",
    "approximate": "aproximado",
    "ask_hours": "perguntar_horas",
    "brand": "marca",
    "by_similar": "pelos_parecidos",
    "capacity": "capacidade",
    "category": "categoria",
    "criterion": "criterio",
    "current": "atual",
    "daily_hours": "horas_dia",
    "data_source": "fonte_dados",
    "days_per_month": "dias_mes",
    "default_value": "padrao",
    "description": "descricao",
    "detail": "detalhe",
    "discarded_suspects": "suspeitos_descartados",
    "distributor": "distribuidora",
    "distributor_id": "distribuidora_id",
    "document": "documento",
    "example": "exemplo",
    "field": "campo",
    "fractions": "fracoes",
    "freezer_volume_l": "volume_congelador_l",
    "items": "itens",
    "kind": "tipo",
    "kwh_label": "kwh_etiqueta",
    "kwh_per_resident": "kwh_por_morador",
    "label": "rotulo",
    "label_field": "campo_etiqueta",
    "label_value": "valor_etiqueta",
    "largest_consumptions": "maiores_consumos",
    "limit": "limite",
    "manual_tariff": "tarifa_manual",
    "maximum": "maximo",
    "mean_comparison": "comparacao_media",
    "measure": "medida",
    "measure_unit": "unidade_medida",
    "median_kwh_per_resident": "mediana_kwh_por_morador",
    "message": "mensagem",
    "method": "metodo",
    "model": "modelo",
    "models": "modelos",
    "monthly_cost": "custo_mes",
    "monthly_cycles": "ciclos_mes",
    "monthly_kwh": "kwh_mes",
    "monthly_max_cost": "custo_max_mes",
    "monthly_min_cost": "custo_min_mes",
    "monthly_savings": "economia_mes",
    "monthly_savings_kwh": "economia_kwh_mes",
    "months": "meses",
    "name": "nome",
    "new_appliance": "novo",
    "new_price": "preco_novo",
    "notice": "aviso",
    "notices": "avisos",
    "optional": "opcional",
    "options": "opcoes",
    "page": "pagina",
    "payback_months": "payback_meses",
    "percentage": "percentual",
    "percentage_difference": "diferenca_percentual",
    "percentage_savings": "economia_percentual",
    "plan": "plano",
    "power_w": "potencia_w",
    "profile": "perfil",
    "purchase_year": "ano_compra",
    "question": "pergunta",
    "save_query": "registrar",
    "required_value": "valor_obrigatorio",
    "residents": "moradores",
    "section": "secao",
    "shapes": "formas",
    "sizes": "tamanhos",
    "source": "fonte",
    "sources": "fontes",
    "special": "especial",
    "speed": "velocidade",
    "start_validity": "vigencia_inicio",
    "suggestions": "sugestoes",
    "swaps": "trocas",
    "tariff_kwh": "tarifa_kwh",
    "tariff_origin": "origem_tarifa",
    "text": "texto",
    "tip": "dica",
    "tips": "dicas",
    "total_category": "total_categoria",
    "total_cost": "custo_total",
    "types": "tipos",
    "unit": "unidade",
    "usage": "uso",
    "value": "valor",
    "where": "onde",
    "yearly_cost": "custo_ano",
    "yearly_savings": "economia_ano",
    "years": "anos",
}


class ApiModel(BaseModel):
    """Base dos modelos da API: le e escreve o JSON com os nomes em portugues (JSON_NAMES)."""
    model_config = ConfigDict(alias_generator=lambda name: JSON_NAMES.get(name, name), populate_by_name=True)


def wait_for_database(attempts=30, pause=2):
    for number in range(1, attempts + 1):
        try:
            return banco.connect()
        except ConnectionError:
            print(f"aguardando o PostgreSQL ({number}/{attempts})...", flush=True)
            time.sleep(pause)
    raise RuntimeError("PostgreSQL nao respondeu a tempo")


def database_loaded(con):
    # banco com a tabela fogoes e de antes da saida do gas de cozinha: recarrega para apagar
    sql = ("SELECT to_regclass('public.aparelhos') IS NOT NULL "
           "AND to_regclass('public.vw_tarifa_vigente') IS NOT NULL "
           "AND to_regclass('public.portateis') IS NOT NULL "
           "AND to_regclass('public.fogoes') IS NULL")
    if not banco.run(con, sql).scalar_one():
        return False
    # banco criado por uma versao antiga do codigo (falta coluna nova): recarrega
    sql = "SELECT column_name FROM information_schema.columns WHERE table_name = 'aparelhos'"
    columns = set(banco.query(con, sql)["column_name"])
    if not set(APPLIANCE_COLUMNS) <= columns:
        print("esquema do banco desatualizado", flush=True)
        return False
    return banco.run(con, "SELECT COUNT(*) FROM aparelhos").scalar_one() > 0


def load_data(con):
    from criar_banco import load_appliances, load_extra_data, load_distributors_and_tariffs

    con.exec_driver_sql(banco.SCHEMA)
    appliances = load_appliances(con)
    distributors, tariffs = load_distributors_and_tariffs(con)
    load_extra_data(con)
    con.commit()
    print(f"dados carregados: {appliances} aparelhos, {distributors} distribuidoras, {tariffs} tarifas", flush=True)


def load_rag():
    """Base do Eco-Coach vazia (banco novo): roda scripts/carregar_rag.py. Sem a chave do Gemini ou sem
    os documentos, so avisa; a API sobe do mesmo jeito e o /eco-coach responde 503 ate a base existir."""
    import runpy

    script = config.ROOT / "scripts" / "carregar_rag.py"
    if not script.exists() or not config._ENV.get("GEMINI_API_KEY"):
        print("base do Eco-Coach vazia (sem a chave do Gemini ou sem os documentos): pulei a carga", flush=True)
        return
    try:
        runpy.run_path(str(script), run_name="__main__")
    except Exception as error:  # rede, limite do Gemini: a API continua no ar
        print(f"nao consegui carregar a base do Eco-Coach: {error}", flush=True)


@asynccontextmanager
async def life_cycle(app):
    con = wait_for_database()
    try:
        if os.getenv("RECARREGAR_BANCO") == "1" or not database_loaded(con):
            print("banco vazio ou desatualizado, carregando os dados...", flush=True)
            load_data(con)
        rag_empty = not rag.base_loaded(con)
    finally:
        con.close()
    if rag_empty:
        load_rag()
    yield


app = FastAPI(
    title="iamp API",
    description="Estima o consumo e o custo mensal de energia de aparelhos eletricos residenciais.",
    version="0.5.0",
    lifespan=life_cycle,
)


class RequestLanguage:
    """Le o Accept-Language de cada requisicao e deixa o idioma valendo enquanto ela roda.
    Middleware ASGI puro (e nao @app.middleware): o valor da ContextVar chega ate as rotas e a resposta
    avisa o idioma (Content-Language) e que ele depende do cabecalho (Vary), para caches nao misturarem."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        headers = dict(scope.get("headers") or [])
        chosen = idioma.from_header(headers.get(b"accept-language", b"").decode("latin-1"))

        async def send_with_language(message):
            if message["type"] == "http.response.start":
                extra = [(b"content-language", b"en" if chosen == "en" else b"pt-BR"), (b"vary", b"Accept-Language")]
                message = {**message, "headers": [*message.get("headers", []), *extra]}
            await send(message)

        token = idioma.define(chosen)
        try:
            await self.app(scope, receive, send_with_language)
        finally:
            idioma.restore(token)


app.add_middleware(RequestLanguage)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip() for o in os.getenv("CORS_ORIGINS", "*").split(",")],
    allow_methods=["*"],
    allow_headers=["*"],
)


class ApplianceSummary(ApiModel):
    id: int
    category: str
    brand: str
    model: str
    detail: Optional[str] = None


class FoundAppliance(ApplianceSummary):
    total_category: int  # quantos modelos desse tipo batem com a busca (pode passar do limite)


class BrandSummary(ApiModel):
    brand: str
    models: int  # quantos modelos a marca tem nesse tipo de aparelho


class UsageQuestion(ApiModel):
    question: Optional[Literal["velocidade", "ciclos", "horas"]] = Field(
        None, description="O que o app precisa perguntar. null = nada, o consumo ja vem do Inmetro."
    )
    options: Optional[list[str]] = Field(None, description="Opcoes de velocidade, quando a pergunta e velocidade.")
    default_value: Union[float, str, None] = Field(None, description="Valor sugerido. null = o usuario precisa informar.")
    optional: bool = Field(False, description="true = o usuario pode deixar em branco e fica o valor do Inmetro.")
    ask_hours: bool = Field(False, description="true = depois da velocidade, pergunta as horas por dia.")


class Distributor(ApiModel):
    id: int
    name: str
    uf: Optional[str] = None
    tariff_kwh: float
    start_validity: Optional[date] = None
    source: Optional[str] = None


class Tariff(ApiModel):
    distributor_id: Optional[int] = Field(None, description="Id vindo de GET /distribuidoras.")
    manual_tariff: Optional[float] = Field(None, gt=0, description="R$/kWh da conta de luz do usuario.")

    @model_validator(mode="after")
    def require_tariff(self):
        if (self.distributor_id is None) == (self.manual_tariff is None):
            raise ValueError("informe distribuidora_id ou tarifa_manual (apenas um dos dois)")
        return self

    def tariff(self):
        return self.model_dump(include={"distributor_id", "manual_tariff"})


class UsageAndTariff(Tariff):
    """Campos comuns: como o aparelho e usado e qual tarifa vale."""
    daily_hours: Optional[float] = Field(None, ge=0, le=24)
    monthly_cycles: Optional[float] = Field(None, ge=0)
    speed: Optional[Literal["baixa", "media", "alta"]] = None

    def usage_and_tariff(self):
        return self.model_dump(include={"distributor_id", "manual_tariff", "daily_hours", "monthly_cycles", "speed"})


class CalculationInput(UsageAndTariff):
    appliance_id: int
    save_query: bool = Field(True, description="Grava o calculo no historico (tabela consultas).")


class SuggestionInput(UsageAndTariff):
    appliance_id: int = Field(..., description="Aparelho que o usuario tem hoje.")
    limit: int = Field(5, ge=1, le=10)


class ComparisonInput(UsageAndTariff):
    appliance_id: int = Field(..., description="Aparelho que o usuario tem hoje.")
    alternative_id: int = Field(..., description="Modelo novo (normalmente vindo de POST /sugestoes).")
    new_price: Optional[float] = Field(None, gt=0, description="Preco do modelo novo em R$, para o payback.")


class Result(ApiModel):
    category: str
    brand: str
    model: str
    detail: str = ""
    distributor: str
    uf: str
    daily_hours: Optional[float] = None
    monthly_kwh: float
    method: str
    tariff_kwh: float
    tariff_origin: str
    monthly_cost: float
    yearly_cost: float
    notices: list[str]
    data_source: str
    approximate: bool = Field(False, description="true = gasto aproximado (modelo fora do catalogo ou valor padrao).")
    kwh_min: Optional[float] = Field(None, description="Faixa da estimativa, quando aproximada.")
    kwh_max: Optional[float] = None
    monthly_min_cost: Optional[float] = None
    monthly_max_cost: Optional[float] = None
    kind: Optional[str] = Field(None, description="Tipo do Inmetro do aparelho estimado (para sugerir equivalentes).")
    capacity: Optional[float] = Field(None, description="Medida do aparelho estimado (L, kg, BTU/h, pol, cm, W ou cv).")
    by_similar: bool = Field(False, description="true = gasto da mediana dos modelos parecidos (sem numero do aparelho).")


class EstimatedInput(UsageAndTariff):
    category: str = Field(..., description="Categoria de GET /estimativa/categorias (menos refrigerador).")
    kind: Optional[str] = None
    measure: Optional[float] = Field(None, gt=0, description="Tamanho do aparelho na unidade da categoria.")
    label_value: Optional[float] = Field(None, gt=0, description="Numero escrito no aparelho, na unidade da forma.")
    label_field: Optional[Literal["kwh_mes", "kwh_ciclo", "potencia_w"]] = Field(
        None, description="Qual das 'formas' da categoria e o valor_etiqueta. null = a primeira.")
    brand: Optional[str] = Field(None, max_length=60)
    model: Optional[str] = Field(None, max_length=60)
    save_query: bool = True


class EstimableType(ApiModel):
    value: str = Field(..., description="Tipo do Inmetro (vai em EstimadoEntrada.tipo).")
    name: str
    description: Optional[str] = None


class CommonSize(ApiModel):
    value: float
    name: str


class EntryMode(ApiModel):
    field: Literal["kwh_mes", "kwh_ciclo", "potencia_w"]
    name: str
    label: str
    unit: str
    where: str
    tip: Optional[str] = None
    example: str
    maximum: float


class EstimableCategory(ApiModel):
    category: str
    name: str
    special: bool
    measure: Optional[str] = None
    measure_unit: Optional[str] = None
    sizes: list[CommonSize]
    types: list[EstimableType]
    shapes: list[EntryMode] = Field(..., description="Numeros do proprio aparelho que o usuario pode informar.")
    required_value: bool = Field(..., description="true = sem catalogo para comparar; precisa de uma das formas.")
    usage: UsageQuestion


class EstimatedSuggestionInput(UsageAndTariff):
    category: str
    capacity: Optional[float] = Field(None, gt=0)
    monthly_kwh: float = Field(..., gt=0, description="kwh_mes do resultado da estimativa.")
    kind: Optional[str] = None
    name: Optional[str] = Field(None, max_length=120)
    limit: int = Field(5, ge=1, le=10)
    by_similar: bool = Field(False, description="Copie de Resultado.pelos_parecidos.")


class EstimatedComparisonInput(UsageAndTariff):
    category: str
    monthly_kwh: float = Field(..., gt=0, description="kwh_mes do resultado da estimativa.")
    alternative_id: int
    name: Optional[str] = Field(None, max_length=120)
    new_price: Optional[float] = Field(None, gt=0)


class OldRefrigeratorInput(Tariff):
    kind: Literal[tuple(estimativa.TYPES)] = Field(..., description="1_porta, frigobar, duplex, freezer_vertical ou freezer_horizontal.")
    frost_free: bool
    volume_total_l: float = Field(..., gt=0, le=estimativa.MAX_VOLUME_L)
    freezer_volume_l: Optional[float] = Field(None, ge=0, description="Volume do freezer. Em branco = proporcao tipica do tipo.")
    purchase_year: int = Field(..., ge=estimativa.MIN_YEAR)
    kwh_label: Optional[float] = Field(None, gt=0, le=300, description="kWh/mes da etiqueta do Inmetro colada no aparelho.")
    brand: Optional[str] = Field(None, max_length=60)
    model: Optional[str] = Field(None, max_length=60)
    save_query: bool = True


class ResistiveInput(Tariff):
    category: str = Field(..., max_length=40, description="Categoria de GET /resistivos. Ex.: air_fryer")
    power_w: Optional[float] = Field(None, gt=0, le=10000, description="Potencia da etiqueta. Em branco = tipica da categoria.")
    daily_hours: Optional[float] = Field(None, ge=0, le=24)
    days_per_month: Optional[float] = Field(None, ge=0, le=31)
    save_query: bool = True


class Resistive(ApiModel):
    category: str
    name: str
    power_w: float
    daily_hours: float
    days_per_month: float
    source: str


class ConsumptionItem(ApiModel):
    category: str = Field(..., description="Categoria do aparelho (GET /categorias). Ex.: chuveiro")
    monthly_kwh: float = Field(..., ge=0, description="Consumo mensal, normalmente o kwh_mes de POST /calcular.")


class ClassificationInput(ApiModel):
    residents: int = Field(..., ge=1, le=20)
    items: list[ConsumptionItem] = Field(..., min_length=1, description="Aparelhos da casa com o consumo de cada um.")


class MeanComparison(ApiModel):
    median_kwh_per_resident: float
    percentage_difference: float
    text: str


class Classification(ApiModel):
    profile: Literal["Consciente", "Moderado", "Ineficiente"]
    kwh_total: float
    kwh_per_resident: float
    mean_comparison: MeanComparison
    fractions: dict[str, float]
    notice: str
    source: str


class ApplianceConsumption(ApplianceSummary):
    kind: str = ""
    monthly_kwh: float
    monthly_cost: float


class SuggestedAppliance(ApplianceConsumption):
    monthly_savings_kwh: float
    monthly_savings: float
    yearly_savings: float
    percentage_savings: float


class Suggestions(ApiModel):
    current: ApplianceConsumption
    tariff_kwh: float
    criterion: Optional[str] = Field(None, description="Como os modelos equivalentes foram escolhidos.")
    message: Optional[str] = Field(None, description="Explica por que nao ha sugestao, quando a lista vem vazia.")
    discarded_suspects: int = Field(0, description="Modelos com consumo baixo demais para ser real (provavel erro no dado).")
    suggestions: list[SuggestedAppliance]


class Payback(ApiModel):
    new_price: float
    months: Optional[float] = Field(None, description="null = a troca nao se paga pela conta de luz.")
    years: Optional[float] = None
    text: str


class Comparison(ApiModel):
    current: Result
    new_appliance: Result
    monthly_savings_kwh: float
    monthly_savings: float
    yearly_savings: float
    payback: Optional[Payback] = Field(None, description="So vem quando preco_novo e informado.")
    notices: list[str]


def connection():
    try:
        con = banco.connect()
    except ConnectionError as error:
        raise HTTPException(status_code=503, detail=idioma.tr("banco de dados indisponivel", "database unavailable")) from error
    try:
        yield con
    finally:
        con.close()


def service_error(error):
    message = str(error)
    not_found = any(chunk in message for chunk in
                    ("nao existe", "sem tarifa vigente", "does not exist", "has no current tariff"))
    return HTTPException(status_code=404 if not_found else 422, detail=message)


@app.get("/", include_in_schema=False)
def start():
    return RedirectResponse("/docs")


@app.get("/saude", tags=["Sistema"])
def health(con=Depends(connection)):
    banco.run(con, "SELECT 1")
    return {"status": "ok"}


@app.get("/categorias", response_model=list[str], tags=["Aparelhos"])
def list_categories(con=Depends(connection)):
    return banco.categories(con)


@app.get("/aparelhos", response_model=list[FoundAppliance], tags=["Aparelhos"])
def search_appliances(
    search_text: str = Query(..., alias="busca", min_length=2, description="Marca e/ou modelo. Ex.: brastemp brm44"),
    category: Optional[str] = Query(None, alias="categoria", description="Filtra por categoria. Ver GET /categorias."),
    limit: int = Query(SEARCH_LIMIT, alias="limite", ge=1, le=50, description="Maximo de modelos por tipo de aparelho."),
    con=Depends(connection),
):
    return servico.search_models(con, search_text, category, limit)


@app.get("/marcas", response_model=list[BrandSummary], tags=["Aparelhos"])
def list_brands(
    category: str = Query(..., alias="categoria", description="Tipo de aparelho. Ver GET /categorias."),
    con=Depends(connection),
):
    """Marcas de um tipo de aparelho, com a quantidade de modelos (tipo que nao existe: lista vazia)."""
    return servico.list_brands(con, category)


@app.get("/modelos", response_model=list[FoundAppliance], tags=["Aparelhos"])
def list_brand_models(
    category: str = Query(..., alias="categoria", description="Tipo de aparelho. Ver GET /categorias."),
    brand: str = Query(..., alias="marca", min_length=1, description="Marca, como veio do GET /marcas (sem diferenciar maiusculas)."),
    limit: int = Query(BRAND_MODEL_LIMIT, alias="limite", ge=1, le=500),
    con=Depends(connection),
):
    """Modelos de uma marca dentro de um tipo. total_categoria = quantos a marca tem nesse tipo."""
    return servico.brand_models(con, category, brand, limit)


@app.get("/aparelhos/{aparelho_id}/uso", response_model=UsageQuestion, tags=["Aparelhos"])
def usage_question(appliance_id: int = Path(alias="aparelho_id"), con=Depends(connection)):
    try:
        return servico.usage_data(con, appliance_id)
    except ValueError as error:
        raise service_error(error) from error


@app.get("/ufs", response_model=list[str], tags=["Distribuidoras"])
def list_ufs(con=Depends(connection)):
    return servico.list_ufs(con)


@app.get("/distribuidoras", response_model=list[Distributor], tags=["Distribuidoras"])
def list_distributors(
    uf: Optional[str] = Query(None, pattern="^[A-Za-z]{2}$", description="Sigla do estado. Ex.: PR"),
    search_text: Optional[str] = Query(None, alias="busca", description="Parte do nome. Ex.: copel"),
    con=Depends(connection),
):
    return servico.list_distributors(con, uf=uf, search_text=search_text)


@app.post("/calcular", response_model=Result, tags=["Calculo"])
def calculate(payload: CalculationInput, con=Depends(connection)):
    try:
        return servico.calculate(con, payload.appliance_id, register=payload.save_query, **payload.usage_and_tariff())
    except ValueError as error:
        raise service_error(error) from error


@app.post("/calcular/refrigerador-antigo", response_model=Result, tags=["Calculo"])
def calculate_old_refrigerator(payload: OldRefrigeratorInput, con=Depends(connection)):
    """Geladeira fora do catalogo: usa a etiqueta, se houver; senao estima por tipo, volume e ano de compra."""
    try:
        consumption = estimativa.estimated_refrigerator_consumption(
            payload.kind, payload.frost_free, payload.volume_total_l, payload.purchase_year,
            freezer_volume_l=payload.freezer_volume_l, kwh_label=payload.kwh_label)
        return servico.calculate_estimated(con, consumption, brand=payload.brand, model=payload.model,
                                         register=payload.save_query, **payload.tariff())
    except FileNotFoundError as error:
        raise HTTPException(status_code=503, detail=idioma.tr("modelo de estimativa indisponivel",
                                                              "estimation model unavailable")) from error
    except ValueError as error:
        raise service_error(error) from error


@app.get("/resistivos", response_model=list[Resistive], tags=["Calculo"])
def list_resistive(con=Depends(connection)):
    """Eletroportateis (tabela portateis) e os valores padrao usados quando o usuario nao informa."""
    return servico.list_small_appliances(con)


@app.post("/calcular/resistivo", response_model=Result, tags=["Calculo"])
def calculate_resistive(payload: ResistiveInput, con=Depends(connection)):
    """kWh/mes = potencia (W) / 1000 x horas por dia x dias de uso no mes."""
    try:
        default_value = servico.smallAppliance(con, payload.category)
        consumption = estimativa.resistive_consumption(default_value, payload.power_w, payload.daily_hours, payload.days_per_month)
        return servico.calculate_estimated(con, consumption, register=payload.save_query, **payload.tariff())
    except ValueError as error:
        raise service_error(error) from error


@app.get("/estimativa/categorias", response_model=list[EstimableCategory], tags=["Calculo"])
def list_estimable_categories(con=Depends(connection)):
    """Eletro pesado que da para estimar quando o modelo nao esta no catalogo, e o que perguntar de cada um."""
    return servico.estimable_categories(con)


@app.post("/calcular/estimado", response_model=Result, tags=["Calculo"])
def calculate_estimated(payload: EstimatedInput, con=Depends(connection)):
    """Aparelho fora do catalogo: valor da etiqueta, se houver; senao a mediana dos modelos parecidos."""
    try:
        consumption = servico.estimate_from_equivalents(
            con, payload.category, payload.kind, payload.measure, payload.label_value,
            payload.daily_hours, payload.monthly_cycles, payload.speed, payload.label_field)
        return servico.calculate_estimated(con, consumption, brand=payload.brand, model=payload.model,
                                         register=payload.save_query, **payload.tariff())
    except ValueError as error:
        raise service_error(error) from error


@app.post("/sugestoes/estimado", response_model=Suggestions, tags=["Economia"])
def suggest_for_estimated(payload: EstimatedSuggestionInput, con=Depends(connection)):
    """Modelos do catalogo que gastam menos que um aparelho estimado (mesmo criterio de POST /sugestoes)."""
    try:
        return servico.suggest_for_estimated(
            con, payload.category, payload.capacity, payload.monthly_kwh, kind=payload.kind, name=payload.name,
            limit=payload.limit, by_similar=payload.by_similar, **payload.usage_and_tariff())
    except ValueError as error:
        raise service_error(error) from error


@app.post("/comparar/estimado", response_model=Comparison, tags=["Economia"])
def compare_estimated(payload: EstimatedComparisonInput, con=Depends(connection)):
    """Economia e payback de trocar um aparelho estimado por um modelo do catalogo."""
    try:
        return servico.compare_estimated(
            con, payload.category, payload.monthly_kwh, payload.alternative_id, name=payload.name,
            new_price=payload.new_price, **payload.usage_and_tariff())
    except ValueError as error:
        raise service_error(error) from error


@app.post("/sugestoes", response_model=Suggestions, tags=["Economia"])
def suggest(payload: SuggestionInput, con=Depends(connection)):
    """Modelos equivalentes (mesmo servico) que gastam pelo menos 5% menos, com o mesmo uso e tarifa."""
    try:
        return servico.suggest_alternatives(con, payload.appliance_id, limit=payload.limit, **payload.usage_and_tariff())
    except ValueError as error:
        raise service_error(error) from error


@app.post("/comparar", response_model=Comparison, tags=["Economia"])
def compare(payload: ComparisonInput, con=Depends(connection)):
    """Economia de trocar o aparelho atual pelo novo e, com preco_novo, o payback (em meses)."""
    try:
        return servico.compare(con, payload.appliance_id, payload.alternative_id,
                                new_price=payload.new_price, **payload.usage_and_tariff())
    except ValueError as error:
        raise service_error(error) from error


@app.post("/classificar", response_model=Classification, tags=["Perfil (ML)"])
def classify(payload: ClassificationInput):
    """Perfil de consumo da casa (K-Means treinado com residencias sinteticas)."""
    try:
        return ml_pipeline.classify_residence(payload.model_dump(by_alias=True))
    except FileNotFoundError as error:
        raise HTTPException(status_code=503, detail=idioma.tr("modelo de perfil indisponivel",
                                                              "profile model unavailable")) from error
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error


# Eco-Coach (RAG + LLM) -------------------------------------------------------------------

class ItemEco(ConsumptionItem):
    monthly_cost: Optional[float] = Field(None, ge=0, description="R$/mes do aparelho (custo_mes de POST /calcular).")


class EvaluatedSwap(ApiModel):
    appliance: str = Field(..., description="Aparelho atual. Ex.: geladeira Brastemp BRM44")
    alternative: str = Field(..., description="Modelo sugerido. Ex.: geladeira Electrolux TF39")
    monthly_savings: float = Field(..., description="R$/mes economizados (de POST /comparar).")
    payback_months: Optional[float] = Field(None, ge=0, description="Meses para a troca se pagar (de /comparar).")


class EcoCoachInput(ApiModel):
    residents: int = Field(..., ge=1, le=20)
    items: list[ItemEco] = Field(..., min_length=1, description="Aparelhos da casa com consumo (e custo).")
    swaps: list[EvaluatedSwap] = Field(default_factory=list, max_length=5,
                                        description="Trocas ja calculadas no /comparar (opcional).")


class CitedSource(ApiModel):
    n: int
    document: str
    agency: str
    url: str
    section: Optional[str] = None
    page: Optional[int] = None


class LargestConsumption(ApiModel):
    category: str
    name: str
    monthly_kwh: float
    monthly_cost: Optional[float] = None
    percentage: float


class EcoCoach(ApiModel):
    profile: Literal["Consciente", "Moderado", "Ineficiente"]
    kwh_total: float
    total_cost: Optional[float] = None
    largest_consumptions: list[LargestConsumption]
    plan: str = Field(..., description="Texto em markdown; as citacoes [n] apontam para 'fontes'.")
    sources: list[CitedSource]
    model: str
    notice: str


@app.post("/eco-coach", response_model=EcoCoach, tags=["Eco-Coach (RAG)"])
def eco_coach(payload: EcoCoachInput, con=Depends(connection)):
    """Plano de acao em linguagem simples, com dicas oficiais citadas. Os numeros sao calculados
    pelo iamp; o LLM (Gemini) so escreve. Pode levar alguns segundos."""
    data = payload.model_dump(by_alias=True)  # rag_agent le as chaves do JSON (em portugues)
    try:
        return rag_agent.generate_plan(con, data, swaps=data.pop("trocas"))
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error
    except FileNotFoundError as error:
        raise HTTPException(status_code=503, detail=idioma.tr("modelo de perfil indisponivel",
                                                              "profile model unavailable")) from error
    except (LookupError, RuntimeError) as error:
        raise HTTPException(status_code=503, detail=idioma.tr(f"Eco-Coach indisponivel: {error}",
                                                              f"Eco-Coach unavailable: {error}")) from error


class TipsInput(ApiModel):
    category: str = Field(..., max_length=40)
    name: str = Field(..., max_length=120)
    monthly_kwh: float = Field(..., ge=0)
    monthly_cost: float = Field(..., ge=0)
    method: Optional[str] = Field(None, max_length=400, description="Texto 'metodo' de POST /calcular.")


class ApplianceTips(ApiModel):
    tips: str = Field(..., description="Texto em markdown; as citacoes [n] apontam para 'fontes'.")
    sources: list[CitedSource]
    model: str
    notice: str


@app.post("/eco-coach/aparelho", response_model=ApplianceTips, tags=["Eco-Coach (RAG)"])
def eco_coach_appliance(payload: TipsInput, con=Depends(connection)):
    """Dicas personalizadas para gastar menos com um aparelho (usado nos eletroportateis)."""
    try:
        return rag_agent.generate_appliance_tips(con, payload.model_dump(by_alias=True))
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error
    except (LookupError, RuntimeError) as error:
        raise HTTPException(status_code=503, detail=idioma.tr(f"Eco-Coach indisponivel: {error}",
                                                              f"Eco-Coach unavailable: {error}")) from error
