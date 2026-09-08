"""Entrada compatible: python py.py URL."""
import os
from pathlib import Path
import sys
import subprocess

if __name__ == "__main__":
    local_python = Path(__file__).parent / ".venv" / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
    if sys.prefix == sys.base_prefix and local_python.is_file():
        try:
            raise SystemExit(subprocess.call([str(local_python), str(Path(__file__).resolve()), *sys.argv[1:]]))
        except KeyboardInterrupt:
            raise SystemExit(130)
    from descargador.cli import main
    raise SystemExit(main())
