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

FOLDER = config.ROOT / "datasets" / "raw" / "rag"
CHUNK_SIZE = 800
CEMIG_PAGES = range(2, 18)  # 2 a 17
MARKER = "•"  # •


def clear(text):
    return re.sub(r"\s+", " ", html.unescape(text)).strip()


# PDF da Cemig ----------------------------------------------------------------------------

# Titulo curto (sem marcador) que contem uma destas palavras muda a secao. Palavras soltas das
# ilustracoes ("METAL", "P L I N !") nao entram porque nao batem com nenhuma.
SECTIONS = [("CHUVEIRO", "Chuveiro elétrico"), ("SOLAR", "Aquecimento solar"),
          ("ILUMINA", "Iluminação / lâmpadas"), ("GELADEIRA", "Geladeira / freezer"),
          ("ARCONDICIONADO", "Ar-condicionado"), ("VENTILADOR", "Ventiladores"),
          ("MAQUINADELAVAR", "Máquina de lavar"), ("FERRO", "Ferro elétrico"),
          ("SECADORA", "Secadora de roupa"), ("FORNO", "Forno elétrico"), ("STANDBY", "Stand-by"),
          ("TELEVIS", "Televisores"), ("COMPUTADOR", "Computadores"), ("ELEVADOR", "Elevadores")]


def title_section(line):
    if len(line) > 40:  # anotacoes do ilustrador sao frases longas
        return None
    key = re.sub(r"[^A-Z]", "", line.upper().replace("Á", "A").replace("Ç", "C").replace("Ã", "A"))
    return next((name for word, name in SECTIONS if word in key), None)


# Secao no inicio de cada pagina (conferido lendo a cartilha): algumas paginas comecam um aparelho
# novo antes do titulo aparecer (ex.: a pagina 11 ja e de ar-condicionado, o titulo so vem na 12).
PAGE_SECTION = {2: "Dicas gerais", 5: "Iluminação / lâmpadas", 7: "Chuveiro elétrico",
                   8: "Aquecimento solar", 9: "Geladeira / freezer", 11: "Ar-condicionado",
                   13: "Máquina de lavar", 15: "Stand-by", 16: "Computadores", 17: "Elevadores"}


def pdf_items(path):
    """[(secao, pagina, texto_do_item)] com os itens de marcador da cartilha."""
    from pypdf import PdfReader
    items, section = [], "Dicas gerais"
    for number in CEMIG_PAGES:
        section = PAGE_SECTION.get(number, section)
        current = None
        for line in (PdfReader(path).pages[number - 1].extract_text() or "").splitlines():
            line = line.strip()
            if not line:
                continue
            if line.startswith(MARKER):
                if current:
                    items.append((section, number, clear(current)))
                current = line.lstrip(MARKER + " ")
            elif current and not re.search(r"[.!?:]$", current):
                current += " " + line  # continuacao do item (ainda sem ponto final)
            else:
                if current:
                    items.append((section, number, clear(current)))
                    current = None
                section = title_section(line) or section
        if current:
            items.append((section, number, clear(current)))
    return items


# HTML gov.br / Agencia Gov ---------------------------------------------------------------

def html_items(path):
    """[(secao, None, paragrafo)] com o corpo da pagina, usando os negritos como secao."""
    t = Path(path).read_text(encoding="utf-8", errors="ignore")
    m = (re.search(r'(?s)class="texto-conteudo"[^>]*>(.*?)<div[^>]*class="[^"]*(?:materia-original|compartilhar)', t)
         or re.search(r'(?s)id="(?:parent-fieldname-text|content-core)"[^>]*>(.*?)<div[^>]*id="(?:viewlet-below-content|footer)', t))
    body = m.group(1) if m else t
    body = re.sub(r"(?s)<(script|style).*?</\1>", "", body)
    items, section = [], None
    for block in re.findall(r"(?s)<(?:p|li|h2|h3)[^>]*>(.*?)</(?:p|li|h2|h3)>", body):
        bold_only = re.fullmatch(r"(?s)\s*<strong>(.*?)</strong>\s*", block)
        text = clear(re.sub(r"<br\s*/?>", " ", re.sub(r"<(?!br)[^>]+>", "", block)).replace("<br>", " "))
        text = clear(re.sub(r"<[^>]+>", " ", text))
        if not text:
            continue
        if bold_only and len(text) < 80:
            section = text
        elif len(text) > 30:
            items.append((section, None, text))
    return items


# Trechos ---------------------------------------------------------------------------------

def group_items(items):
    """Junta itens da mesma secao em trechos de ate ~TAMANHO_TRECHO caracteres."""
    chunks, current = [], None
    for section, page, text in items:
        if current and current["secao"] == section and len(current["texto"]) + len(text) < CHUNK_SIZE:
            current["texto"] += "\n" + text
        else:
            if current:
                chunks.append(current)
            current = {"secao": section, "pagina": page, "texto": text}
    if current:
        chunks.append(current)
    return chunks


def main():
    sources = list(csv.DictReader(open(FOLDER / "fontes.csv", encoding="utf-8")))
    lines = []
    for f in sources:
        path = FOLDER / f["arquivo"]
        items = pdf_items(path) if path.suffix == ".pdf" else html_items(path)
        chunks = group_items(items)
        print(f"{f['arquivo']}: {len(items)} itens -> {len(chunks)} trechos")
        for t in chunks:
            lines.append({**t, "documento": f["titulo"], "orgao": f["orgao"],
                           "tipo_fonte": f["tipo_fonte"], "url": f["url"], "arquivo": f["arquivo"]})

    print(f"\nGerando embeddings de {len(lines)} trechos ({rag.EMBEDDING_MODEL})...")
    # o titulo da secao entra no texto vetorizado: ajuda a achar "geladeira" em dicas sem a palavra
    vectors = rag.vectorize((f"{l['secao'] or ''}: {l['texto']}" for l in lines), task="RETRIEVAL_DOCUMENT")

    with banco.connect() as con:
        # recria a tabela: o tamanho do vetor depende do modelo (DIMENSION em rag.py)
        con.exec_driver_sql("DROP TABLE IF EXISTS trechos_rag")
        con.exec_driver_sql(rag.RAG_SCHEMA)
        for l, v in zip(lines, vectors):
            banco.run(con, "INSERT INTO trechos_rag (documento, orgao, tipo_fonte, url, arquivo, "
                                "secao, pagina, texto, embedding) VALUES (?, ?, ?, ?, ?, ?, ?, ?, CAST(? AS vector))",
                           (l["documento"], l["orgao"], l["tipo_fonte"], l["url"], l["arquivo"],
                            l["secao"], l["pagina"], l["texto"], rag.literal_vector(v)))
        for f in sources:
            n = sum(1 for l in lines if l["arquivo"] == f["arquivo"])
            banco.run(con, "INSERT INTO cargas (arquivo, linhas) VALUES (?, ?)", (f"rag/{f['arquivo']}", n))
        con.commit()
    print(f"{len(lines)} trechos gravados em trechos_rag")


if __name__ == "__main__":
    main()
