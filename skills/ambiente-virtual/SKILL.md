---
name: usar-venv
description: Use o ambiente virtual .venv (Python 3.12) da raiz do iamp para rodar Python, pip, pytest, scripts de limpeza e treino. Aplique sempre que executar ou instalar algo Python neste repositório, no Windows ou no Linux.
---

# Usar o ambiente virtual `.venv`

Use sempre o ambiente virtual `.venv` da raiz do projeto (`C:\iamp\.venv`) para qualquer tarefa Python. Ele é Python **3.12**, o mesmo da imagem Docker; não use o 3.14 nem o Python global.

## Regras

- No Windows, o interpretador é `.venv\Scripts\python.exe` (no Git Bash, `./.venv/Scripts/python.exe`). No Linux ou Mac, `./.venv/bin/python`. Os exemplos abaixo usam o Windows, que é a máquina do grupo.
- Execute o pip como `.venv\Scripts\python.exe -m pip`, nunca `pip` solto.
- Não use `python`, `python3`, `pip` ou ferramentas globais para executar, instalar, testar ou inspecionar nada do projeto. Com o `.venv` ativado (`.venv\Scripts\activate`), `python` já é o do ambiente; sem ativar, use o caminho completo.
- Dependências em três arquivos, instale só o que a tarefa precisa:
  - `requirements.txt`: API (pandas, SQLAlchemy, psycopg2, FastAPI, google-genai, pypdf).
  - `requirements-dev.txt`: testes (pytest, httpx).
  - `requirements-ml.txt`: treino (sdv, scikit-learn, matplotlib, jupyter). É pesado (instala torch) e fica fora da imagem Docker; não acrescente essas bibliotecas ao `requirements.txt`.
- Se o `.venv` não existir ou estiver incompleto, avise e crie na raiz com o Python 3.12 antes de continuar. Não troque silenciosamente pelo Python global.
- Rode os comandos a partir da raiz do projeto. Exceções já documentadas: `criar_banco.py` e `app_terminal.py` rodam de dentro de `src/`, e `uvicorn main:app --reload` também.
- Dentro dos containers (`api_iamp`, `iamp_tf_api`) o Python é o da imagem; não misture com o `.venv` do PC.
- O app Flutter não usa o `.venv`: use `flutter pub get`, `flutter analyze`, `flutter test`.

## Exemplos

```powershell
.venv\Scripts\python.exe -m pip install -r requirements.txt -r requirements-dev.txt
.venv\Scripts\python.exe -m pytest -m "not banco"
.venv\Scripts\python.exe scripts\executar_pipeline.py
.venv\Scripts\python.exe scripts\carregar_rag.py
cd src; ..\.venv\Scripts\python.exe criar_banco.py
```

```sh
# Git Bash
./.venv/Scripts/python.exe -m pytest
./.venv/Scripts/python.exe scripts/gerar_seed.py
```
