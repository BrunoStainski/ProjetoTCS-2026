"""
Idioma das respostas da API: portugues (padrao) ou ingles.

O app manda o cabecalho Accept-Language ("en" quando a pessoa escolhe o ingles no menu). Sem o
cabecalho, ou com outra lingua, a API responde em portugues, como sempre fez: o APK antigo, o
app_terminal.py, os scripts e os testes continuam iguais.

Como funciona:
  - main.py le o cabecalho em cada requisicao e guarda o idioma numa ContextVar. Cada requisicao
    tem o seu valor (mesmo com varias ao mesmo tempo); fora da API vale o portugues.
  - Texto montado na hora (com numeros): tr("consumo de {x}", "consumption of {x}"), as duas
    versoes lado a lado, para quem mudar uma ver a outra.
  - Texto fixo (constantes e configuracoes, como AVISO_PADRAO e ESTIMAVEIS): t(texto) procura a
    traducao no dicionario traducoes.EN. tests/test_idioma.py confere que todo texto fixo tem traducao.
  - O historico (tabela consultas) guarda o texto do jeito que a pessoa viu.
"""

import re
from contextlib import contextmanager
from contextvars import ContextVar

from traducoes import EN

IDIOMAS = ("pt", "en")
PADRAO = "pt"

_atual = ContextVar("idioma", default=PADRAO)


def do_cabecalho(valor):
    """Accept-Language -> "pt" ou "en". Ex.: "en-US,en;q=0.9,pt;q=0.8" -> "en".
    Vale a lingua conhecida com o maior peso (q); empate, a que veio primeiro."""
    opcoes = []
    for posicao, parte in enumerate((valor or "").split(",")):
        lingua, *parametros = parte.strip().split(";")
        peso = 1.0
        for parametro in parametros:
            chave, _, numero = parametro.strip().partition("=")
            if chave == "q":
                try:
                    peso = float(numero)
                except ValueError:
                    peso = 0.0
        codigo = lingua.strip().lower().split("-")[0]
        if codigo in IDIOMAS and peso > 0:
            opcoes.append((-peso, posicao, codigo))
    return min(opcoes)[2] if opcoes else PADRAO


def definir(idioma):
    """Usa o idioma ate restaurar(token). Lingua desconhecida vira o padrao."""
    return _atual.set(idioma if idioma in IDIOMAS else PADRAO)


def restaurar(token):
    _atual.reset(token)


@contextmanager
def usando(idioma):
    """with idioma.usando("en"): ...  (testes e scripts)."""
    token = definir(idioma)
    try:
        yield
    finally:
        restaurar(token)


def atual():
    return _atual.get()


def em_ingles():
    return _atual.get() == "en"


def tr(pt, en):
    """Texto montado na hora, nas duas linguas."""
    return en if em_ingles() else pt


def t(texto):
    """Texto fixo: a traducao de traducoes.EN em ingles; sem traducao (ou em portugues), o proprio texto."""
    if not em_ingles() or not isinstance(texto, str):
        return texto
    return EN.get(texto, texto)


def numero(valor, casas=1):
    """1234.5 -> "1.234,5" em portugues e "1,234.5" em ingles."""
    texto = f"{valor:,.{casas}f}"
    return texto if em_ingles() else texto.replace(",", "X").replace(".", ",").replace("X", ".")


_SEPARADOR = re.compile(r"(?<=\d)[.,](?=\d)")
_UNIDADES = [(re.compile(r"\bpolegadas\b"), "inches"), (re.compile(r"\bpol\b"), "in"),
             (re.compile(r"\blitros\b"), "liters"), (re.compile(r"\bcv\b"), "hp")]


def unidades(texto):
    """Unidades escritas em portugues -> ingles ("43 pol" -> "43 in", "1/2 cv" -> "1/2 hp").
    Nao mexe nos numeros: o detalhe do catalogo ja usa ponto decimal ("1.5 cv")."""
    if not em_ingles() or not isinstance(texto, str):
        return texto
    for padrao, troca in _UNIDADES:
        texto = padrao.sub(troca, texto)
    return texto


def medida(texto):
    """Medida escrita do jeito brasileiro ("7.500 BTU/h", "1,5 cv", "Ex.: 0,25") -> ingles
    ("7,500 BTU/h", "1.5 hp", "E.g.: 0.25"): troca os separadores dos numeros e as unidades."""
    if not em_ingles() or not isinstance(texto, str):
        return texto
    texto = _SEPARADOR.sub(lambda m: "," if m.group() == "." else ".", texto)
    return unidades(texto.replace("Ex.:", "E.g.:"))
