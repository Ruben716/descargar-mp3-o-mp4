"""Convierte los fallos de `flutter test --reporter json` en anotaciones de GitHub.

Las anotaciones se leen sin iniciar sesion; los registros de la compilacion no.
"""
import json
import sys

pruebas: dict[int, str] = {}
# Flutter escribe el detalle de un fallo (la excepcion, el «Expected/Actual»)
# antes del aviso de error, que solo dice «mira arriba»: se guarda todo.
escrito: dict[int, list[str]] = {}
# Lo que Flutter escribe fuera del JSON, como el volcado de una excepcion.
suelto: list[str] = []
errores: dict[int, list[str]] = {}
try:
    with open(sys.argv[1], encoding="utf-8") as archivo:
        lineas = archivo.readlines()
except OSError:
    print("::notice title=Pruebas::No hay resultados: las pruebas no llegaron a ejecutarse.")
    sys.exit(0)

for linea in lineas:
    try:
        evento = json.loads(linea)
    except ValueError:
        suelto.append(linea)
        continue
    tipo = evento.get("type")
    if tipo == "testStart":
        pruebas[evento["test"]["id"]] = evento["test"]["name"]
    elif tipo == "print":
        escrito.setdefault(evento.get("testID", -1), []).append(evento.get("message", ""))
    elif tipo == "error":
        errores.setdefault(evento["testID"], []).append(evento.get("error", ""))

# Lo que importa de un volcado de Flutter, sin la pila entera.
CLAVES = ("Expected", "Actual", "Which", "Exception", "Error", "reason", "was thrown",
          "The following", "Bad state", "RangeError", "Null check")

for ident, mensajes in errores.items():
    utiles = [
        " ".join(linea.split())
        for texto in escrito.get(ident, []) + mensajes
        for linea in texto.splitlines()
        if any(clave in linea for clave in CLAVES)
    ]
    texto = " | ".join(dict.fromkeys(utiles))[:1500] or " ".join(" ".join(mensajes).split())[:900]
    # Las comas y los dos puntos rompen el formato de la anotacion.
    titulo = pruebas.get(ident, f"prueba {ident}").replace(",", " ").replace(":", " ")
    print(f"::error title={titulo}::{texto}")

if errores:
    utiles = [" ".join(linea.split()) for linea in suelto if any(c in linea for c in CLAVES)]
    if utiles:
        print("::error title=Detalle de la excepcion::" + " | ".join(dict.fromkeys(utiles))[:3000])

print(f"::notice title=Pruebas::{len(pruebas)} pruebas leidas, {len(errores)} con error.")
