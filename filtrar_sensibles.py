#!/usr/bin/env python3
"""
Filtro de fotos/videos sensibles (paso 2 del pipeline de backup).
Procesamiento 100% LOCAL con NudeNet: ninguna imagen sale de tu máquina.

Qué hace:
  - Recorre la carpeta (y subcarpetas) buscando imágenes y videos
  - Detecta desnudez / semidesnudez con un modelo local
  - En los videos muestrea varios cuadros a lo largo de la duración
  - Lo detectado se mueve DIRECTAMENTE a "_sensibles/" (conservando la
    subcarpeta de origen), a medida que se analiza
  - Cada movimiento queda registrado en _sensibles/movimientos.txt
    (origen -> destino), para poder devolver falsos positivos a mano
  - Los compresores del pipeline excluyen "_sensibles/", así que nada de eso
    llega a la carpeta -compressed que va a la nube

NO es infalible: puede haber falsos positivos (playa, gym) y falsos
negativos. Revisá _sensibles/ después de correrlo; con movimientos.txt
sabés exactamente de dónde salió cada archivo.

Requisitos:
  pip3 install nudenet opencv-python-headless pillow-heif

Uso:
  python3 filtrar_sensibles.py .
"""

from __future__ import annotations

import datetime
import shutil
import sys
import tempfile
from pathlib import Path

try:
    from nudenet import NudeDetector
except ImportError:
    print("Falta nudenet. Instalá las dependencias con:")
    print("  pip3 install nudenet opencv-python-headless pillow-heif")
    sys.exit(1)

try:
    import cv2
    VIDEO_DISPONIBLE = True
except ImportError:
    VIDEO_DISPONIBLE = False

try:
    from pillow_heif import register_heif_opener
    from PIL import Image
    register_heif_opener()
    HEIC_DISPONIBLE = True
except ImportError:
    HEIC_DISPONIBLE = False

# Clases del modelo que se consideran sensibles.
# Las _EXPOSED son desnudez; las _COVERED son ropa interior / bikini
# (sacá las _COVERED de la lista si no querés filtrar semidesnudez).
CLASES_SENSIBLES = {
    "FEMALE_GENITALIA_EXPOSED",
    "FEMALE_BREAST_EXPOSED",
    "MALE_GENITALIA_EXPOSED",
    "BUTTOCKS_EXPOSED",
    "ANUS_EXPOSED",
    "FEMALE_GENITALIA_COVERED",
    "FEMALE_BREAST_COVERED",
    "BUTTOCKS_COVERED",
}
UMBRAL = 0.5          # confianza mínima (0 a 1). Más bajo = más estricto/más falsos positivos
CUADROS_POR_VIDEO = 8  # cuántos cuadros muestrear por video

EXT_IMAGEN = {".jpg", ".jpeg", ".png"}
EXT_HEIC = {".heic", ".heif"}
EXT_VIDEO = {".mp4", ".mov", ".m4v"}
CARPETA_SENSIBLES = "_sensibles"


def hay_sensible(detecciones: list) -> tuple[bool, str]:
    """Devuelve (True, detalle) si alguna detección supera el umbral."""
    for det in detecciones or []:
        clase = det.get("class", "")
        score = det.get("score", 0)
        if clase in CLASES_SENSIBLES and score >= UMBRAL:
            return True, f"{clase} ({score:.0%})"
    return False, ""


def analizar_imagen(detector: NudeDetector, ruta: Path) -> tuple[bool, str]:
    if ruta.suffix.lower() in EXT_HEIC:
        if not HEIC_DISPONIBLE:
            return False, "HEIC salteado (falta pillow-heif)"
        with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tmp:
            temporal = Path(tmp.name)
        try:
            img = Image.open(ruta)
            if img.mode != "RGB":
                img = img.convert("RGB")
            img.save(temporal, "JPEG", quality=85)
            return hay_sensible(detector.detect(str(temporal)))
        finally:
            temporal.unlink(missing_ok=True)
    return hay_sensible(detector.detect(str(ruta)))


def analizar_video(detector: NudeDetector, ruta: Path) -> tuple[bool, str]:
    if not VIDEO_DISPONIBLE:
        return False, "video salteado (falta opencv)"
    cap = cv2.VideoCapture(str(ruta))
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    if total <= 0:
        cap.release()
        return False, ""
    paso = max(total // CUADROS_POR_VIDEO, 1)
    with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tmp:
        temporal = Path(tmp.name)
    try:
        for n in range(0, total, paso):
            cap.set(cv2.CAP_PROP_POS_FRAMES, n)
            ok, cuadro = cap.read()
            if not ok:
                continue
            cv2.imwrite(str(temporal), cuadro)
            sensible, detalle = hay_sensible(detector.detect(str(temporal)))
            if sensible:
                cap.release()
                return True, f"{detalle} en cuadro {n}"
        return False, ""
    finally:
        cap.release()
        temporal.unlink(missing_ok=True)


def mover_a_sensibles(archivo: Path, base: Path) -> Path:
    """Mueve el archivo a _sensibles/ conservando la subcarpeta de origen."""
    rel = archivo.relative_to(base)
    destino = base / CARPETA_SENSIBLES / rel
    destino.parent.mkdir(parents=True, exist_ok=True)
    i = 1
    while destino.exists():
        destino = destino.with_name(f"{destino.stem}_{i}{destino.suffix}")
        i += 1
    shutil.move(str(archivo), str(destino))
    return destino


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    base = Path(sys.argv[1]).expanduser().resolve()
    if not base.is_dir():
        print(f"No existe la carpeta: {base}")
        sys.exit(1)

    print(f"Analizando {base} (procesamiento local, nada sale de esta máquina)...")
    if not VIDEO_DISPONIBLE:
        print("AVISO: falta opencv, los videos se van a saltear.")
    if not HEIC_DISPONIBLE:
        print("AVISO: falta pillow-heif, los HEIC se van a saltear.")
    print("")

    detector = NudeDetector()

    extensiones = EXT_IMAGEN | EXT_HEIC | EXT_VIDEO
    candidatos = [
        p for p in sorted(base.rglob("*"))
        if p.is_file()
        and p.suffix.lower() in extensiones
        and not p.name.startswith(".")
        and "-filtered" not in p.stem  # ya analizado en una corrida anterior
        and not any("-compressed" in parte for parte in p.parts)
        and CARPETA_SENSIBLES not in p.parts
        and "sensibles-revision-humana" not in p.parts
    ]

    if not candidatos:
        print("No se encontraron archivos para analizar.")
        return

    carpeta_log = base / CARPETA_SENSIBLES
    carpeta_log.mkdir(exist_ok=True)
    ruta_log = carpeta_log / "movimientos.txt"

    movidos, errores = 0, 0
    errores_seguidos = 0
    total = len(candidatos)
    with open(ruta_log, "a") as log:
        log.write(f"\n# Corrida {datetime.datetime.now():%Y-%m-%d %H:%M:%S}\n")
        log.flush()
        for i, archivo in enumerate(candidatos, 1):
            if i % 50 == 0 or i == total:
                print(f"  ... {i}/{total} analizados, {movidos} movidos")
            try:
                if archivo.suffix.lower() in EXT_VIDEO:
                    sensible, detalle = analizar_video(detector, archivo)
                else:
                    sensible, detalle = analizar_imagen(detector, archivo)
                errores_seguidos = 0
                if sensible:
                    origen_rel = archivo.relative_to(base)
                    destino = mover_a_sensibles(archivo, base)
                    destino_rel = destino.relative_to(base)
                    movidos += 1
                    log.write(f"{origen_rel} -> {destino_rel}  [{detalle}]\n")
                    log.flush()
                    print(f"  MOVIDO: {origen_rel}  [{detalle}]")
                else:
                    # limpio: marcar con -filtered para no re-analizarlo nunca más
                    nuevo = archivo.with_name(f"{archivo.stem}-filtered{archivo.suffix}")
                    j = 1
                    while nuevo.exists():
                        nuevo = archivo.with_name(f"{archivo.stem}-filtered_{j}{archivo.suffix}")
                        j += 1
                    archivo.rename(nuevo)
            except Exception as e:
                errores += 1
                errores_seguidos += 1
                print(f"  ERROR analizando {archivo.name}: {e}")
                if not base.exists() or errores_seguidos >= 25:
                    print("")
                    print("FRENO DE EMERGENCIA: demasiados errores consecutivos o la")
                    print("carpeta base desapareció. ¿Se desconectó el disco externo?")
                    print("Reconectalo, verificalo con Utilidad de Discos y volvé a")
                    print("correr: lo ya analizado (-filtered) no se re-analiza.")
                    break

    print(f"\nListo: {movidos} archivos movidos a _sensibles/, {errores} errores.")
    print(f"Registro de movimientos: {ruta_log}")
    print("Si hay falsos positivos, el txt te dice de qué carpeta salió cada uno")
    print("para devolverlo a mano.")


if __name__ == "__main__":
    main()
