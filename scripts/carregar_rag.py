"""
Carrega os documentos do Eco-Coach na base vetorial (tabela trechos_rag, pgvector).

Le datasets/raw/rag/ + fontes.csv (origem de cada arquivo), extrai o texto, limpa, divide em
trechos de ~800 caracteres por secao, gera os embeddings localmente e grava no PostgreSQL.
Rodar de novo apaga e recarrega os trechos (os documentos sao a unica fonte).

Limpeza:
- Cartilha Cemig (PDF): so as paginas 2 a 17 (dicas); as demais sao seguranca eletrica e ficha
  tecnica. Ficam so os itens com marcador (•): titulos e anotacoes para o ilustrador que vieram
  no PDF ("Foco na borracha de vedacao...") nao tem marcador e sao descartados.
- Paginas gov.br / Agencia Gov (HTML): so o corpo da noticia (sem menu do site).

Uso (na raiz, com o .venv ativo e o PostgreSQL no ar):
  python scripts/carregar_rag.py
"""

import csv
import html
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
import banco  # noqa: E402
import config  # noqa: E402
import rag  # noqa: E402

PASTA = config.RAIZ / "datasets" / "raw" / "rag"
TAMANHO_TRECHO = 800
PAGINAS_CEMIG = range(2, 18)  # 2 a 17
MARCADOR = "•"  # •


def limpar(texto):
    return re.sub(r"\s+", " ", html.unescape(texto)).strip()


# PDF da Cemig ----------------------------------------------------------------------------

# Titulo curto (sem marcador) que contem uma destas palavras muda a secao. Palavras soltas das
# ilustracoes ("METAL", "P L I N !") nao entram porque nao batem com nenhuma.
SECOES = [("CHUVEIRO", "Chuveiro elétrico"), ("SOLAR", "Aquecimento solar"),
          ("ILUMINA", "Iluminação / lâmpadas"), ("GELADEIRA", "Geladeira / freezer"),
          ("ARCONDICIONADO", "Ar-condicionado"), ("VENTILADOR", "Ventiladores"),
          ("MAQUINADELAVAR", "Máquina de lavar"), ("FERRO", "Ferro elétrico"),
          ("SECADORA", "Secadora de roupa"), ("FORNO", "Forno elétrico"), ("STANDBY", "Stand-by"),
          ("TELEVIS", "Televisores"), ("COMPUTADOR", "Computadores"), ("ELEVADOR", "Elevadores")]


def secao_do_titulo(linha):
    if len(linha) > 40:  # anotacoes do ilustrador sao frases longas
        return None
    chave = re.sub(r"[^A-Z]", "", linha.upper().replace("Á", "A").replace("Ç", "C").replace("Ã", "A"))
    return next((nome for palavra, nome in SECOES if palavra in chave), None)


# Secao no inicio de cada pagina (conferido lendo a cartilha): algumas paginas comecam um aparelho
# novo antes do titulo aparecer (ex.: a pagina 11 ja e de ar-condicionado, o titulo so vem na 12).
SECAO_DA_PAGINA = {2: "Dicas gerais", 5: "Iluminação / lâmpadas", 7: "Chuveiro elétrico",
                   8: "Aquecimento solar", 9: "Geladeira / freezer", 11: "Ar-condicionado",
                   13: "Máquina de lavar", 15: "Stand-by", 16: "Computadores", 17: "Elevadores"}


def itens_pdf(caminho):
    """[(secao, pagina, texto_do_item)] com os itens de marcador da cartilha."""
    from pypdf import PdfReader
    itens, secao = [], "Dicas gerais"
    for numero in PAGINAS_CEMIG:
        secao = SECAO_DA_PAGINA.get(numero, secao)
        atual = None
        for linha in (PdfReader(caminho).pages[numero - 1].extract_text() or "").splitlines():
            linha = linha.strip()
            if not linha:
                continue
            if linha.startswith(MARCADOR):
                if atual:
                    itens.append((secao, numero, limpar(atual)))
                atual = linha.lstrip(MARCADOR + " ")
            elif atual and not re.search(r"[.!?:]$", atual):
                atual += " " + linha  # continuacao do item (ainda sem ponto final)
            else:
                if atual:
                    itens.append((secao, numero, limpar(atual)))
                    atual = None
                secao = secao_do_titulo(linha) or secao
        if atual:
            itens.append((secao, numero, limpar(atual)))
    return itens


# HTML gov.br / Agencia Gov ---------------------------------------------------------------

def itens_html(caminho):
    """[(secao, None, paragrafo)] com o corpo da pagina, usando os negritos como secao."""
    t = Path(caminho).read_text(encoding="utf-8", errors="ignore")
    m = (re.search(r'(?s)class="texto-conteudo"[^>]*>(.*?)<div[^>]*class="[^"]*(?:materia-original|compartilhar)', t)
         or re.search(r'(?s)id="(?:parent-fieldname-text|content-core)"[^>]*>(.*?)<div[^>]*id="(?:viewlet-below-content|footer)', t))
    corpo = m.group(1) if m else t
    corpo = re.sub(r"(?s)<(script|style).*?</\1>", "", corpo)
    itens, secao = [], None
    for bloco in re.findall(r"(?s)<(?:p|li|h2|h3)[^>]*>(.*?)</(?:p|li|h2|h3)>", corpo):
        so_negrito = re.fullmatch(r"(?s)\s*<strong>(.*?)</strong>\s*", bloco)
        texto = limpar(re.sub(r"<br\s*/?>", " ", re.sub(r"<(?!br)[^>]+>", "", bloco)).replace("<br>", " "))
        texto = limpar(re.sub(r"<[^>]+>", " ", texto))
        if not texto:
            continue
        if so_negrito and len(texto) < 80:
            secao = texto
        elif len(texto) > 30:
            itens.append((secao, None, texto))
    return itens


# Trechos ---------------------------------------------------------------------------------

def agrupar(itens):
    """Junta itens da mesma secao em trechos de ate ~TAMANHO_TRECHO caracteres."""
    trechos, atual = [], None
    for secao, pagina, texto in itens:
        if atual and atual["secao"] == secao and len(atual["texto"]) + len(texto) < TAMANHO_TRECHO:
            atual["texto"] += "\n" + texto
        else:
            if atual:
                trechos.append(atual)
            atual = {"secao": secao, "pagina": pagina, "texto": texto}
    if atual:
        trechos.append(atual)
    return trechos


def main():
    fontes = list(csv.DictReader(open(PASTA / "fontes.csv", encoding="utf-8")))
    linhas = []
    for f in fontes:
        caminho = PASTA / f["arquivo"]
        itens = itens_pdf(caminho) if caminho.suffix == ".pdf" else itens_html(caminho)
        trechos = agrupar(itens)
        print(f"{f['arquivo']}: {len(itens)} itens -> {len(trechos)} trechos")
        for t in trechos:
            linhas.append({**t, "documento": f["titulo"], "orgao": f["orgao"],
                           "tipo_fonte": f["tipo_fonte"], "url": f["url"], "arquivo": f["arquivo"]})

    print(f"\nGerando embeddings de {len(linhas)} trechos ({rag.MODELO_EMBEDDING})...")
    # o titulo da secao entra no texto vetorizado: ajuda a achar "geladeira" em dicas sem a palavra
    vetores = rag.vetorizar(f"{l['secao'] or ''}: {l['texto']}" for l in linhas)

    with banco.conectar() as con:
        con.exec_driver_sql(rag.ESQUEMA_RAG)
        banco.executar(con, "DELETE FROM trechos_rag")
        for l, v in zip(linhas, vetores):
            banco.executar(con, "INSERT INTO trechos_rag (documento, orgao, tipo_fonte, url, arquivo, "
                                "secao, pagina, texto, embedding) VALUES (?, ?, ?, ?, ?, ?, ?, ?, CAST(? AS vector))",
                           (l["documento"], l["orgao"], l["tipo_fonte"], l["url"], l["arquivo"],
                            l["secao"], l["pagina"], l["texto"], rag.literal_vetor(v)))
        for f in fontes:
            n = sum(1 for l in linhas if l["arquivo"] == f["arquivo"])
            banco.executar(con, "INSERT INTO cargas (arquivo, linhas) VALUES (?, ?)", (f"rag/{f['arquivo']}", n))
        con.commit()
    print(f"{len(linhas)} trechos gravados em trechos_rag")


if __name__ == "__main__":
    main()
