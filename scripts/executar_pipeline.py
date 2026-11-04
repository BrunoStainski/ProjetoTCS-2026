"""Executa todos os scripts de limpeza (raw -> processed) em sequência.

Uso:  python scripts/executar_pipeline.py            # só limpeza
      python scripts/executar_pipeline.py --importar # limpeza + carga no PostgreSQL
"""

import subprocess
import sys
from pathlib import Path

PASTA_SCRIPTS = Path(__file__).resolve().parent


def main() -> int:
    scripts = sorted(PASTA_SCRIPTS.glob("tratar_dados_*.py"))
    if "--importar" in sys.argv:
        scripts.append(PASTA_SCRIPTS / "importar_datasets.py")

    falhas = []
    for script in scripts:
        print(f"\n===== {script.name} =====")
        resultado = subprocess.run([sys.executable, str(script)], cwd=PASTA_SCRIPTS)
        if resultado.returncode != 0:
            falhas.append(script.name)

    print("\n" + ("✓ Pipeline concluído sem erros." if not falhas else f"❌ Falharam: {', '.join(falhas)}"))
    return 1 if falhas else 0


if __name__ == "__main__":
    sys.exit(main())
