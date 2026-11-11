"""
Gera o PDF da documentacao do projeto (entregavel da banca) a partir do Markdown.

  docs/documento_processo.md  ->  docs/documento_processo.pdf

Converte o Markdown em HTML (pacote "markdown"), embute as imagens (BPMN em SVG/PNG e graficos da EDA) e
imprime em PDF com o Chrome ou o Edge em modo headless. Sem pandoc nem LaTeX.

O BPMN e muito largo para uma pagina A4 em pe: ele vai numa pagina paisagem e, no lugar do
marcador <!-- BPMN_PARTES --> do Markdown, entra cortado em PARTES_BPMN (Pillow), uma por pagina.
Se o diagrama mudar de layout, confira os cortes (fracoes da largura) no PDF gerado.

Uso (na raiz, com o .venv ativo; pip install -r requirements-dev.txt):
  python scripts/gerar_pdf_documento.py
"""

import base64
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import io

import markdown
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
INPUT = ROOT / "docs" / "documento_processo.md"
OUTPUT = ROOT / "docs" / "documento_processo.pdf"
BPMN = INPUT.parent / "bpmn_processo.png"

# (inicio, fim) como fracao da largura do diagrama; a sobreposicao evita tarefa cortada ao meio
BPMN_PARTS = [
    (0.00, 0.37, "Parte 1 de 3: cálculo do consumo e do custo; preparação de dados e treino (offline)"),
    (0.34, 0.67, "Parte 2 de 3: sugestão de troca e payback"),
    (0.64, 1.00, "Parte 3 de 3: perfil de consumo (K-Means) e Eco-Coach (RAG + Gemini)"),
]
Image.MAX_IMAGE_PIXELS = None  # o PNG do BPMN tem ~88 milhoes de pixels

NAVIGATORS = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "google-chrome", "chromium", "chromium-browser", "microsoft-edge",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
]

STYLE = """
@page { size: A4; margin: 18mm 16mm; }
body { font-family: "Segoe UI", Arial, sans-serif; font-size: 10.5pt; line-height: 1.45; color: #1a1a1a; }
h1 { font-size: 22pt; margin: 0 0 4pt; }
h2 { font-size: 15pt; border-bottom: 2px solid #FFD000; padding-bottom: 3pt; margin-top: 22pt;
     page-break-after: avoid; }
h3, h4 { page-break-after: avoid; margin-top: 14pt; }
table { border-collapse: collapse; width: 100%; margin: 8pt 0; font-size: 9.5pt; page-break-inside: avoid; }
th, td { border: 1px solid #c8c8c8; padding: 4pt 6pt; vertical-align: top; text-align: left; }
th { background: #f3f3f3; }
pre { background: #f6f6f6; border: 1px solid #e0e0e0; padding: 8pt; font-size: 8.5pt;
      white-space: pre-wrap; page-break-inside: avoid; }
code { font-family: Consolas, "Courier New", monospace; font-size: 9pt; }
img { max-width: 100%; display: block; margin: 8pt auto; page-break-inside: avoid; }
blockquote { border-left: 4px solid #FFD000; margin: 8pt 0; padding: 4pt 10pt; background: #fffbe6; }
hr { border: none; border-top: 1px solid #ddd; margin: 14pt 0; }
@page paisagem { size: A4 landscape; margin: 10mm; }
.paisagem { page: paisagem; break-before: page; break-after: page; text-align: center; }
.paisagem img { max-width: 100%; max-height: 165mm; width: auto; margin: 0 auto; }
.paisagem.dupla img { max-height: 76mm; }
.paisagem h3 { margin: 2pt 0 4pt; text-align: left; }
.paisagem p { margin: 0 0 4pt; font-size: 9pt; color: #555; }
"""


def embed_images(html, folder):
    """Troca src="arquivo.png" pelo conteudo em base64 (o PDF fica autocontido)."""
    def replace(m):
        path = (folder / m.group(1)).resolve()
        kind = "svg+xml" if path.suffix == ".svg" else "png"
        if not path.exists():
            print(f"aviso: imagem nao encontrada: {path}")
            return m.group(0)
        data = base64.b64encode(path.read_bytes()).decode()
        return f'src="data:image/{kind};base64,{data}"'
    return re.sub(r'src="([^"]+\.(?:png|svg))"', replace, html)


def bpmn_parts():
    """HTML com o BPMN cortado em partes, cada uma numa pagina paisagem."""
    image = Image.open(BPMN)
    width, height = image.size
    blocks = []
    for start, end, legend in BPMN_PARTS:
        cutoff = image.crop((int(start * width), 0, int(end * width), height))
        buffer = io.BytesIO()
        cutoff.save(buffer, format="PNG", optimize=True)
        data = base64.b64encode(buffer.getvalue()).decode()
        blocks.append(f'<div class="paisagem"><p>BPMN, {legend}</p>'
                      f'<img alt="BPMN, {legend}" src="data:image/png;base64,{data}"></div>')
    return "\n".join(blocks)


def find_navigator():
    for n in NAVIGATORS:
        path = n if Path(n).exists() else shutil.which(n)
        if path:
            return path
    sys.exit("Chrome ou Edge nao encontrado: instale um deles para gerar o PDF.")


def main():
    text = INPUT.read_text(encoding="utf-8")
    text = text.replace("<!-- BPMN_PARTES -->", "\n" + bpmn_parts() + "\n")
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)  # outros marcadores internos
    body = markdown.markdown(text, extensions=["tables", "fenced_code", "sane_lists", "md_in_html"])
    # visao geral do BPMN tambem numa pagina paisagem
    body = re.sub(r'<p>(<img [^>]*src="bpmn_processo\.png"[^>]*>)</p>',
                   r'<div class="paisagem"><p>BPMN 2.0, diagrama completo</p>\1</div>', body)
    body = embed_images(body, INPUT.parent)
    html = (f'<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">'
            f"<title>iamp - Documentacao do Projeto</title><style>{STYLE}</style></head>"
            f"<body>{body}</body></html>")

    with tempfile.TemporaryDirectory() as tmp:
        file = Path(tmp) / "documento.html"
        file.write_text(html, encoding="utf-8")
        subprocess.run([find_navigator(), "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
                        f"--print-to-pdf={OUTPUT}", file.as_uri()],
                       check=True, capture_output=True, timeout=120)
    print(f"PDF gerado: {OUTPUT.relative_to(ROOT)} ({OUTPUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
