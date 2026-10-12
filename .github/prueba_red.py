"""Prueba de punta a punta contra internet de lo que las pruebas normales no tocan."""
from pathlib import Path

from descargador.domain import DownloadOptions, DownloadRequest, SearchQuery
from descargador.infrastructure import YtDlpDownloader

motor = YtDlpDownloader()


def bajar(url: str, carpeta: str) -> None:
    calidad = motor.quality(DownloadRequest(url, Path("x")))
    print("   calidad en origen:", calidad)
    opciones = DownloadOptions(audio_only=True, audio_format="best")
    res = motor.download(DownloadRequest(url, Path(carpeta), opciones))
    for f in res.files:
        print("   BAJADO:", f.name, f.stat().st_size // 1024, "KB, empieza por", f.read_bytes()[:4])


print("===== PODCASTS")
programas = motor.search(SearchQuery("historia", limit=5, source="podcasts"))
for p in programas:
    print("  ", p.uploader, "-", p.title, "|", p.url)
lista = motor.playlist(programas[0].url)
print("episodios de", lista.title, ":", len(lista.items))
corto = min(lista.items, key=lambda e: e.duration or 10**9)
print("el mas corto:", corto.title, corto.duration, "s |", corto.url[:120])
bajar(corto.url, "podcast")

print("\n===== HEARTHIS")
pistas = motor.search(SearchQuery("chill", limit=10, source="hearthis"))
for p in pistas:
    print("  ", p.uploader, "-", p.title, p.duration, "|", p.url)
corta = min((p for p in pistas if p.duration), key=lambda p: p.duration or 0)
print("la mas corta:", corta.title, corta.duration)
bajar(corta.url, "hearthis")
