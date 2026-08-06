#!/usr/bin/env python3
"""
Clasificador de fotos/videos de iPhone por origen.

Categorías:
  fotos_propias/      -> HEIC/JPG/DNG con EXIF de cámara Apple
  videos_propios/     -> MOV con metadata QuickTime de Apple (grabados por vos)
  capturas/           -> PNG (screenshots de iOS)
  tiktok/             -> MP4 con metadata de ByteDance/TikTok (confirmado)
  instagram/          -> MP4 con rastros de Instagram (confirmado)
  instagram-tiktok/   -> MP4 descargado sin fuente identificable (puede ser cualquiera de las dos)
  whatsapp/           -> JPG sin EXIF de cámara (fotos recibidas)
  videos_recibidos/   -> MOV / QT movie sin metadata de Apple (videos que te pasaron)
  _revisar/           -> lo que no encaja en nada de lo anterior

Nota: si existe una carpeta _revisar/ de una corrida anterior, también se
re-analiza y se saca de ahí lo que ahora sí se puede clasificar.

Requisitos (en Mac):
  brew install exiftool

Uso:
  python3 clasificar_fotos.py /ruta/a/carpeta            # dry-run: solo muestra qué haría
  python3 clasificar_fotos.py /ruta/a/carpeta --mover    # mueve los archivos de verdad
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

EXTENSIONES = {".heic", ".heif", ".jpg", ".jpeg", ".png", ".dng", ".mov", ".mp4", ".m4v", ".gif", ".webp", ".aae", ".dat"}

CATEGORIAS = [
    "fotos_propias",
    "videos_propios",
    "capturas",
    "tiktok",
    "instagram",
    "instagram-tiktok",
    "whatsapp",
    "videos_recibidos",
    "_revisar",
]


def correr_exiftool(rutas: list) -> list[dict]:
    """Corre exiftool una sola vez sobre las rutas dadas y devuelve la metadata en JSON."""
    try:
        salida = subprocess.run(
            ["exiftool", "-json", "-G", "-charset", "UTF8"] + [str(r) for r in rutas],
            capture_output=True,
            check=False,
        )
        # decodificamos a mano con tolerancia: si queda algún byte raro
        # (símbolos ° de GPS, etc.) lo reemplaza en vez de explotar
        resultado_stdout = salida.stdout.decode("utf-8", errors="replace")
    except FileNotFoundError:
        print("ERROR: no se encontró exiftool. Instalalo con:  brew install exiftool")
        sys.exit(1)

    if not resultado_stdout.strip():
        print("exiftool no devolvió nada. ¿La carpeta tiene archivos?")
        sys.exit(1)

    return json.loads(resultado_stdout)


def texto_completo(meta: dict) -> str:
    """Toda la metadata como un solo string en minúsculas, para buscar keywords."""
    return json.dumps(meta, ensure_ascii=False).lower()


def clasificar(meta: dict) -> str:
    archivo = meta.get("SourceFile", "")
    nombre = Path(archivo).name.lower()
    ext = Path(archivo).suffix.lower()
    tipo = str(meta.get("File:FileType", "")).upper()
    make = str(meta.get("EXIF:Make", "") or meta.get("QuickTime:Make", "")).lower()
    todo = texto_completo(meta)

    # --- Capturas de pantalla: iOS las guarda siempre en PNG ---
    if tipo == "PNG" or ext == ".png":
        return "capturas"

    # --- TikTok: casi siempre deja huella de ByteDance ---
    if any(k in todo for k in ("tiktok", "bytedance", "aigc")):
        return "tiktok"

    # --- Instagram: a veces deja rastros ---
    if "instagram" in todo:
        return "instagram"

    # --- WhatsApp: por nombre de archivo (si vino via Files/export) ---
    if "whatsapp" in nombre or nombre.startswith(("img-", "vid-")) and "-wa" in nombre:
        return "whatsapp"

    # --- Foto sacada por vos: EXIF de cámara Apple ---
    # (usa el tipo REAL detectado por exiftool, así los .DAT que en realidad
    # son fotos también se clasifican bien)
    if tipo in ("HEIC", "HEIF", "JPEG", "DNG") and "apple" in make:
        return "fotos_propias"

    # --- Video grabado por vos: MOV con metadata de Apple ---
    if tipo in ("MOV", "QUICKTIME") and "apple" in make:
        return "videos_propios"

    # MOV sin make pero con datos típicos de cámara de iPhone
    if tipo in ("MOV", "QUICKTIME") and "com.apple.quicktime" in todo:
        return "videos_propios"

    # --- Todo otro MOV / QT movie: video que te pasaron ---
    # (incluye los que tienen extensión .mov aunque el contenedor interno sea MP4)
    if tipo in ("MOV", "QUICKTIME") or ext == ".mov":
        return "videos_recibidos"

    # --- JPG sin EXIF de cámara: foto recibida por WhatsApp ---
    if tipo == "JPEG":
        return "whatsapp"

    # --- MP4 sin fuente identificable: puede ser IG o TikTok ---
    if tipo in ("MP4", "M4V"):
        return "instagram-tiktok"

    return "_revisar"


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    carpeta = Path(sys.argv[1]).expanduser().resolve()
    mover = "--mover" in sys.argv

    if not carpeta.is_dir():
        print(f"No existe la carpeta: {carpeta}")
        sys.exit(1)

    print(f"Analizando {carpeta} ...")
    rutas = [carpeta]
    if (carpeta / "_revisar").is_dir():
        rutas.append(carpeta / "_revisar")
    metadatos = correr_exiftool(rutas)

    conteo = {c: 0 for c in CATEGORIAS}
    plan: list[tuple[Path, str]] = []
    pendientes_aae: list[Path] = []

    for meta in metadatos:
        origen = Path(meta["SourceFile"])
        if origen.suffix.lower() not in EXTENSIONES:
            continue
        # saltear archivos ya clasificados en carpetas definitivas
        # (_revisar sí se re-analiza)
        if origen.parent.name in CATEGORIAS and origen.parent.name != "_revisar":
            continue
        if origen.suffix.lower() == ".aae":
            pendientes_aae.append(origen)
            continue
        categoria = clasificar(meta)
        conteo[categoria] += 1
        if origen.parent == carpeta / categoria:
            continue  # ya está donde tiene que estar
        plan.append((origen, categoria))

    # Los .AAE (ediciones de Apple) van a la misma carpeta que su foto.
    # IMG_6856.AAE o IMG_O6856.AAE acompañan a IMG_6856.*
    destino_por_stem = {origen.stem.lower(): cat for origen, cat in plan}
    for aae in pendientes_aae:
        stem = aae.stem.lower().replace("img_o", "img_")
        categoria = destino_por_stem.get(stem, "_revisar")
        conteo[categoria] += 1
        if aae.parent == carpeta / categoria:
            continue
        plan.append((aae, categoria))

    print("\nResumen:")
    for cat in CATEGORIAS:
        print(f"  {cat:16} {conteo[cat]}")

    # Desglose de _revisar por extensión, para entender qué quedó sin clasificar
    por_ext: dict = {}
    for origen, cat in plan:
        if cat == "_revisar":
            por_ext[origen.suffix.lower()] = por_ext.get(origen.suffix.lower(), 0) + 1
    if por_ext:
        print("\n  _revisar por extensión:")
        for ext, n in sorted(por_ext.items(), key=lambda x: -x[1]):
            print(f"    {ext:8} {n}")

    if not mover:
        print("\n(Dry-run: no se movió nada. Ejecutá con --mover para mover los archivos.)")
        print("Ejemplos de lo que haría:")
        for origen, cat in plan[:15]:
            print(f"  {origen.name}  ->  {cat}/")
        if len(plan) > 15:
            print(f"  ... y {len(plan) - 15} más")
        return

    for cat in CATEGORIAS:
        (carpeta / cat).mkdir(exist_ok=True)

    movidos = 0
    for origen, cat in plan:
        destino = carpeta / cat / origen.name
        # evitar pisar archivos con el mismo nombre
        i = 1
        while destino.exists():
            destino = carpeta / cat / f"{origen.stem}_{i}{origen.suffix}"
            i += 1
        shutil.move(str(origen), str(destino))
        movidos += 1

    print(f"\nListo: {movidos} archivos movidos a sus carpetas.")


if __name__ == "__main__":
    main()
