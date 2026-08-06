#!/usr/bin/env python3
"""
Compresor de imágenes (versión espejo, para pipeline de backup).

Qué hace:
  - Toma una carpeta de origen y crea una carpeta hermana "<origen>-compressed"
  - Replica adentro la misma estructura de subcarpetas
  - Comprime cada JPG/PNG/HEIC a calidad 75 (los HEIC salen como JPG)
  - Corrige la rotación según EXIF y preserva la metadata (fecha, GPS, cámara)
  - NO borra ni toca los originales
  - Excluye cualquier carpeta que contenga "-compressed" en el nombre
  - Es incremental: si la versión comprimida ya existe, la saltea

Requisitos:
  pip3 install Pillow Send2Trash pillow-heif

Uso:
  python3 comprimir_imagenes.py                    # comprime la carpeta actual
  python3 comprimir_imagenes.py "Hasta 06-08-2026" # comprime esa carpeta
                                                   # -> crea "Hasta 06-08-2026-compressed"
"""

from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image, ImageOps
except ImportError:
    print("Falta Pillow. Instalá las dependencias con:")
    print("  pip3 install Pillow pillow-heif")
    sys.exit(1)

try:
    from pillow_heif import register_heif_opener
    register_heif_opener()
    HEIC_DISPONIBLE = True
except ImportError:
    HEIC_DISPONIBLE = False

CALIDAD = 75
EXT_JPG = {".jpg", ".jpeg"}
EXT_PNG = {".png"}
EXT_HEIC = {".heic", ".heif"}


def ruta_destino(archivo: Path, origen: Path, destino_base: Path) -> Path:
    """Ruta espejo en la carpeta -compressed, con sufijo -compressed-75
    en el nombre para distinguirla de la original (HEIC pasa a .jpg).
    El sufijo -filtered del filtro de sensibles se quita del destino,
    así el espejo mantiene nombres estables y lo ya comprimido se respeta."""
    rel = archivo.relative_to(origen)
    ext = ".jpg" if archivo.suffix.lower() in EXT_HEIC else archivo.suffix
    stem = archivo.stem.replace("-filtered", "")
    nombre = f"{stem}-compressed-{CALIDAD}{ext}"
    return destino_base / rel.parent / nombre


def comprimir(archivo: Path, destino: Path) -> None:
    imagen = Image.open(archivo)
    imagen = ImageOps.exif_transpose(imagen)  # corrige rotación (los 8 casos EXIF)
    exif = imagen.info.get("exif")

    extras = {}
    if exif:
        extras["exif"] = exif

    destino.parent.mkdir(parents=True, exist_ok=True)

    if archivo.suffix.lower() in EXT_PNG:
        imagen.save(destino, "PNG", optimize=True)
    else:
        if imagen.mode != "RGB":
            imagen = imagen.convert("RGB")
        imagen.save(destino, "JPEG", optimize=True, quality=CALIDAD, **extras)


def main() -> None:
    origen = Path(sys.argv[1]).expanduser().resolve() if len(sys.argv) > 1 else Path.cwd()
    if not origen.is_dir():
        print(f"No existe la carpeta: {origen}")
        sys.exit(1)

    destino_base = origen.parent / f"{origen.name}-compressed"

    print(f"Origen:  {origen}")
    print(f"Destino: {destino_base}")
    if not HEIC_DISPONIBLE:
        print("AVISO: pillow-heif no está instalado, los HEIC se van a saltear.")
        print("       Para incluirlos:  pip3 install pillow-heif")
    print("")

    extensiones = EXT_JPG | EXT_PNG | (EXT_HEIC if HEIC_DISPONIBLE else set())
    candidatos = [
        p for p in sorted(origen.rglob("*"))
        if p.is_file()
        and p.suffix.lower() in extensiones
        and not any("-compressed" in parte for parte in p.parts)
        and "_sensibles" not in p.parts  # excluye lo filtrado por filtrar_sensibles.py
        and "sensibles-revision-humana" not in p.parts  # excluye lo apartado a mano
    ]

    if not candidatos:
        print("No se encontraron imágenes para comprimir.")
        return

    ok, salteadas, errores = 0, 0, 0
    total = len(candidatos)
    with open(origen / "errors.txt", "a+") as log:
        for i, archivo in enumerate(candidatos, 1):
            destino = ruta_destino(archivo, origen, destino_base)
            if destino.exists():
                salteadas += 1
                continue
            try:
                original_kb = archivo.stat().st_size // 1024
                comprimir(archivo, destino)
                final_kb = destino.stat().st_size // 1024
                ok += 1
                print(f"[{i}/{total}] {archivo.relative_to(origen)}  {original_kb} KB -> {final_kb} KB")
            except Exception as e:
                errores += 1
                log.write(f"ERROR: {archivo} Exception: {e}\n")
                print(f"[{i}/{total}] ERROR en {archivo.name} (logueado en errors.txt)")

    print(f"\nListo: {ok} comprimidas, {salteadas} ya existían (salteadas), {errores} errores.")
    print(f"Versiones comprimidas en: {destino_base}")
    print("Los originales quedaron intactos.")


if __name__ == "__main__":
    main()
