"""Executa todos os scripts de limpeza (raw -> processed) em sequência.

Uso:  python scripts/executar_pipeline.py

A carga no PostgreSQL é feita pelo src/criar_banco.py.
"""

import subprocess
import sys
from pathlib import Path

SCRIPTS_FOLDER = Path(__file__).resolve().parent


def main() -> int:
    scripts = sorted(SCRIPTS_FOLDER.glob("tratar_dados_*.py"))

    failures = []
    for script in scripts:
        print(f"\n===== {script.name} =====")
        result = subprocess.run([sys.executable, str(script)], cwd=SCRIPTS_FOLDER)
        if result.returncode != 0:
            failures.append(script.name)

    print("\n" + ("✓ Pipeline concluído sem erros." if not failures else f"❌ Falharam: {', '.join(failures)}"))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
