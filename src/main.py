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
import servico
from calculadora_residencial import LIMITE_BUSCA


def esperar_banco(tentativas=30, pausa=2):
    for numero in range(1, tentativas + 1):
        try:
            return banco.conectar()
        except ConnectionError:
            print(f"aguardando o PostgreSQL ({numero}/{tentativas})...", flush=True)
            time.sleep(pausa)
    raise RuntimeError("PostgreSQL nao respondeu a tempo")


def banco_carregado(con):
    sql = ("SELECT to_regclass('public.aparelhos') IS NOT NULL "
           "AND to_regclass('public.vw_tarifa_vigente') IS NOT NULL")
    if not banco.executar(con, sql).scalar_one():
        return False
    return banco.executar(con, "SELECT COUNT(*) FROM aparelhos").scalar_one() > 0


def carregar_dados(con):
    from criar_banco import carregar_aparelhos, carregar_distribuidoras_e_tarifas

    con.exec_driver_sql(banco.ESQUEMA)
    aparelhos = carregar_aparelhos(con)
    distribuidoras, tarifas = carregar_distribuidoras_e_tarifas(con)
    con.commit()
    print(f"dados carregados: {aparelhos} aparelhos, {distribuidoras} distribuidoras, {tarifas} tarifas", flush=True)


@asynccontextmanager
async def ciclo_de_vida(app):
    con = esperar_banco()
    try:
        if os.getenv("RECARREGAR_BANCO") == "1" or not banco_carregado(con):
            print("banco vazio, carregando os dados...", flush=True)
            carregar_dados(con)
    finally:
        con.close()
    yield


app = FastAPI(
    title="iamp API",
    description="Estima o consumo e o custo mensal de energia de aparelhos eletricos residenciais.",
    version="0.1.0",
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


class PerguntaDeUso(BaseModel):
    pergunta: Optional[Literal["velocidade", "ciclos", "horas"]] = Field(
        None, description="O que o app precisa perguntar. null = nada, o consumo ja vem do Inmetro."
    )
    opcoes: Optional[list[str]] = Field(None, description="Opcoes de velocidade, quando a pergunta e velocidade.")
    padrao: Union[float, str, None] = Field(None, description="Valor sugerido. null = o usuario precisa informar.")
    opcional: bool = Field(False, description="true = o usuario pode deixar em branco e fica o valor do Inmetro.")


class Distribuidora(BaseModel):
    id: int
    nome: str
    uf: Optional[str] = None
    tarifa_kwh: float
    vigencia_inicio: Optional[date] = None
    fonte: Optional[str] = None


class CalculoEntrada(BaseModel):
    aparelho_id: int
    distribuidora_id: Optional[int] = Field(None, description="Id vindo de GET /distribuidoras.")
    tarifa_manual: Optional[float] = Field(None, gt=0, description="R$/kWh da conta de luz do usuario.")
    horas_dia: Optional[float] = Field(None, ge=0, le=24)
    ciclos_mes: Optional[float] = Field(None, ge=0)
    velocidade: Optional[Literal["baixa", "media", "alta"]] = None
    registrar: bool = Field(True, description="Grava o calculo no historico (tabela consultas).")

    @model_validator(mode="after")
    def exigir_uma_tarifa(self):
        if (self.distribuidora_id is None) == (self.tarifa_manual is None):
            raise ValueError("informe distribuidora_id ou tarifa_manual (apenas um dos dois)")
        return self


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


@app.get("/aparelhos", response_model=list[AparelhoResumo], tags=["Aparelhos"])
def buscar_aparelhos(
    busca: str = Query(..., min_length=2, description="Marca e/ou modelo. Ex.: brastemp brm44"),
    categoria: Optional[str] = Query(None, description="Filtra por categoria. Ver GET /categorias."),
    limite: int = Query(LIMITE_BUSCA, ge=1, le=50),
    con=Depends(conexao),
):
    return servico.buscar_modelos(con, busca, categoria, limite)


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
        return servico.calcular(
            con,
            entrada.aparelho_id,
            distribuidora_id=entrada.distribuidora_id,
            tarifa_manual=entrada.tarifa_manual,
            horas_dia=entrada.horas_dia,
            ciclos_mes=entrada.ciclos_mes,
            velocidade=entrada.velocidade,
            registrar=entrada.registrar,
        )
    except ValueError as erro:
        raise erro_do_servico(erro) from erro
