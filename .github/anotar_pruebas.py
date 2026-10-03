"""Convierte los fallos de `flutter test --reporter json` en anotaciones de GitHub.

Las anotaciones se leen sin iniciar sesion; los registros de la compilacion no.
"""
import json
import sys

try:
    archivo = open(sys.argv[1], encoding="utf-8")
except OSError:
    print("::notice title=Pruebas::No hay resultados: las pruebas no llegaron a ejecutarse.")
    sys.exit(0)

pruebas: dict[int, str] = {}
errores: dict[int, list[str]] = {}
with archivo:
    for linea in archivo:
        try:
            evento = json.loads(linea)
        except ValueError:
            continue
        tipo = evento.get("type")
        if tipo == "testStart":
            pruebas[evento["test"]["id"]] = evento["test"]["name"]
        elif tipo == "error":
            errores.setdefault(evento["testID"], []).append(evento.get("error", ""))
        elif tipo == "print" and evento.get("testID") in errores:
            errores[evento["testID"]].append(evento.get("message", ""))

for ident, mensajes in errores.items():
    texto = " | ".join(" ".join(m.split()) for m in mensajes if m.strip())[:900]
    # Las comas y los dos puntos rompen el formato de la anotacion.
    titulo = pruebas.get(ident, f"prueba {ident}").replace(",", " ").replace(":", " ")
    print(f"::error title={titulo}::{texto}")

print(f"::notice title=Pruebas::{len(pruebas)} pruebas leidas, {len(errores)} con error.")
