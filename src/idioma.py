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

LANGUAGES = ("pt", "en")
DEFAULT = "pt"

_current = ContextVar("idioma", default=DEFAULT)


def from_header(value):
    """Accept-Language -> "pt" ou "en". Ex.: "en-US,en;q=0.9,pt;q=0.8" -> "en".
    Vale a lingua conhecida com o maior peso (q); empate, a que veio primeiro."""
    options = []
    for position, piece in enumerate((value or "").split(",")):
        lang, *parameters = piece.strip().split(";")
        weight = 1.0
        for parameter in parameters:
            key, _, number = parameter.strip().partition("=")
            if key == "q":
                try:
                    weight = float(number)
                except ValueError:
                    weight = 0.0
        code = lang.strip().lower().split("-")[0]
        if code in LANGUAGES and weight > 0:
            options.append((-weight, position, code))
    return min(options)[2] if options else DEFAULT


def define(language):
    """Usa o idioma ate restaurar(token). Lingua desconhecida vira o padrao."""
    return _current.set(language if language in LANGUAGES else DEFAULT)


def restore(token):
    _current.reset(token)


@contextmanager
def using(language):
    """with idioma.usando("en"): ...  (testes e scripts)."""
    token = define(language)
    try:
        yield
    finally:
        restore(token)


def current():
    return _current.get()


def in_english():
    return _current.get() == "en"


def tr(pt, en):
    """Texto montado na hora, nas duas linguas."""
    return en if in_english() else pt


def t(text):
    """Texto fixo: a traducao de traducoes.EN em ingles; sem traducao (ou em portugues), o proprio texto."""
    if not in_english() or not isinstance(text, str):
        return text
    return EN.get(text, text)


def number(value, homes=1):
    """1234.5 -> "1.234,5" em portugues e "1,234.5" em ingles."""
    text = f"{value:,.{homes}f}"
    return text if in_english() else text.replace(",", "X").replace(".", ",").replace("X", ".")


_SEPARATOR = re.compile(r"(?<=\d)[.,](?=\d)")
_UNITS = [(re.compile(r"\bpolegadas\b"), "inches"), (re.compile(r"\bpol\b"), "in"),
             (re.compile(r"\blitros\b"), "liters"), (re.compile(r"\bcv\b"), "hp")]


def units(text):
    """Unidades escritas em portugues -> ingles ("43 pol" -> "43 in", "1/2 cv" -> "1/2 hp").
    Nao mexe nos numeros: o detalhe do catalogo ja usa ponto decimal ("1.5 cv")."""
    if not in_english() or not isinstance(text, str):
        return text
    for default_value, replacement in _UNITS:
        text = default_value.sub(replacement, text)
    return text


def measure(text):
    """Medida escrita do jeito brasileiro ("7.500 BTU/h", "1,5 cv", "Ex.: 0,25") -> ingles
    ("7,500 BTU/h", "1.5 hp", "E.g.: 0.25"): troca os separadores dos numeros e as unidades."""
    if not in_english() or not isinstance(text, str):
        return text
    text = _SEPARATOR.sub(lambda m: "," if m.group() == "." else ".", text)
    return units(text.replace("Ex.:", "E.g.:"))
