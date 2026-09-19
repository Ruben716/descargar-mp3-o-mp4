"""Entrada compatible: python py.py URL."""
import os
import subprocess
import sys
from pathlib import Path

if __name__ == "__main__":
    relativo = "Scripts/python.exe" if os.name == "nt" else "bin/python"
    local_python = Path(__file__).parent / ".venv" / relativo
    if sys.prefix == sys.base_prefix and local_python.is_file():
        orden = [str(local_python), str(Path(__file__).resolve()), *sys.argv[1:]]
        try:
            codigo = subprocess.call(orden)
        except KeyboardInterrupt:
            codigo = 130
        raise SystemExit(codigo)

    from descargador.cli import main

    raise SystemExit(main())
