"""Sondeo de APIs candidatas: que devuelven de verdad, sin adornos."""
import json
from urllib.parse import urlencode
from urllib.request import Request, urlopen


def pedir(url, cabeceras=None):
    r = urlopen(Request(url, headers={"User-Agent": "tumbao/1.0 (proyecto academico)", **(cabeceras or {})}),
                timeout=30)
    return r.status, r.headers.get("Content-Type"), r.read()


def sondear(nombre, url, mostrar):
    print(f"\n===== {nombre}\n{url}")
    try:
        estado, tipo, cuerpo = pedir(url)
        print("estado", estado, tipo, len(cuerpo), "bytes")
        mostrar(cuerpo)
    except Exception as exc:  # noqa: BLE001 - es un sondeo
        print("FALLO", type(exc).__name__, exc)


def radio(c):
    for s in json.loads(c)[:6]:
        print("  ", s.get("name"), "|", s.get("codec"), s.get("bitrate"), "|", s.get("country"),
              "|", s.get("url_resolved"), "| votos", s.get("votes"))


sondear("RADIO lofi", "https://de1.api.radio-browser.info/json/stations/search?" + urlencode(
    {"name": "lofi", "limit": 6, "order": "votes", "reverse": "true", "hidebroken": "true"}), radio)
sondear("RADIO FLAC", "https://de1.api.radio-browser.info/json/stations/search?" + urlencode(
    {"codec": "FLAC", "limit": 6, "order": "votes", "reverse": "true", "hidebroken": "true"}), radio)
sondear("RADIO Peru", "https://de1.api.radio-browser.info/json/stations/search?" + urlencode(
    {"countrycode": "PE", "limit": 6, "order": "votes", "reverse": "true", "hidebroken": "true"}), radio)


def itunes(c):
    for p in json.loads(c).get("results", [])[:5]:
        print("  ", p.get("collectionName"), "|", p.get("artistName"), "|", p.get("feedUrl"),
              "|", p.get("artworkUrl600"))


sondear("PODCASTS", "https://itunes.apple.com/search?" + urlencode(
    {"term": "historia", "media": "podcast", "entity": "podcast", "limit": 5, "country": "PE"}), itunes)


def hearthis(c):
    datos = json.loads(c)
    print("   tipo", type(datos).__name__, (list(datos)[:20] if isinstance(datos, dict) else ""))
    for t in (datos if isinstance(datos, list) else [])[:5]:
        print("  ", t.get("title"), "|", (t.get("user") or {}).get("username"), "| dl:", t.get("download_url"),
              t.get("download_filename"), "| permalink", t.get("permalink_url"), "| dur", t.get("duration"))


sondear("HEARTHIS search", "https://api-v2.hearthis.at/search/?" + urlencode(
    {"t": "lofi", "page": 1, "count": 5}), hearthis)


def ccmixter(c):
    datos = json.loads(c)
    for u in datos[:4]:
        print("  ", u.get("upload_name"), "|", u.get("user_name"), "|", u.get("file_page_url"))
        for f in (u.get("files") or [])[:4]:
            info = f.get("file_format_info") or {}
            print("       ", f.get("file_nicname"), info.get("default-ext"), info.get("sr"), info.get("br"),
                  f.get("download_url"))


sondear("CCMIXTER", "https://ccmixter.org/api/query?" + urlencode(
    {"f": "json", "search": "lofi", "limit": 4, "sort": "rank"}), ccmixter)

# Podcasts: yt-dlp entiende el RSS como lista?
print("\n===== yt-dlp con un RSS de podcast")
try:
    from yt_dlp import YoutubeDL

    datos = json.loads(pedir("https://itunes.apple.com/search?" + urlencode(
        {"term": "historia", "media": "podcast", "limit": 1}))[2])
    feed = datos["results"][0]["feedUrl"]
    with YoutubeDL({"quiet": True, "extract_flat": "in_playlist"}) as motor:
        info = motor.extract_info(feed, download=False)
    print("tipo", info.get("_type"), "titulo", info.get("title"), "entradas", len(info.get("entries") or []))
    for e in (info.get("entries") or [])[:3]:
        print("  ", e.get("title"), "|", e.get("url"), "|", e.get("duration"))
except Exception as exc:  # noqa: BLE001
    print("FALLO", type(exc).__name__, exc)
