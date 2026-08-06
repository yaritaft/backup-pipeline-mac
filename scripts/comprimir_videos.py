#!/usr/bin/env python3
"""
Compresor de videos (versión espejo, para pipeline de backup).
Réplica Mac de backup-scripts/video-compressor, con HandBrakeCLI.

Qué hace:
  - Toma una carpeta de origen y crea/usa la carpeta hermana "<origen>-compressed"
  - Replica adentro la misma estructura de subcarpetas
  - Comprime cada MP4/MOV/M4V con HandBrake (26RF, audio 160 kbps)
    y lo guarda como nombre-compressed-26RF.mp4
  - NO borra ni toca los originales
  - Excluye cualquier carpeta que contenga "-compressed" en el nombre
  - Es incremental: si la versión comprimida ya existe, la saltea
  - Si un video se corta a la mitad (Ctrl+C, apagón), no queda un archivo
    trunco haciéndose pasar por terminado: usa nombre temporal hasta el final

Calidad (misma escala que el original):
  22RF -> muy buena / 26RF -> buena (default) / 28RF -> suficiente

Requisitos:
  brew install handbrake

Uso:
  python3 comprimir_videos.py                    # comprime la carpeta actual
  python3 comprimir_videos.py "Hasta 06-08-2026" # -> "Hasta 06-08-2026-compressed"
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

AUDIO_BITRATE = "160"
CODE_QUALITY = "26RF"  # 22 REALLY GOOD / 26 VERY GOOD / 28 GOOD ENOUGH
QUALITY_VALUES = {
    "22RF": "22.0",
    "26RF": "26.0",
    "28RF": "28.0",
}
EXT_VIDEO = {".mp4", ".mov", ".m4v"}


def buscar_handbrake() -> str:
    for nombre in ("HandBrakeCLI", "handbrakecli"):
        ruta = shutil.which(nombre)
        if ruta:
            return ruta
    print("ERROR: no se encontró HandBrakeCLI.")
    print("Instalalo con:  brew install handbrake")
    sys.exit(1)


def ruta_destino(archivo: Path, origen: Path, destino_base: Path) -> Path:
    """Ruta espejo en -compressed, con sufijo -compressed-26RF (siempre .mp4).
    El sufijo -filtered del filtro de sensibles se quita del destino,
    así el espejo mantiene nombres estables y lo ya comprimido se respeta."""
    rel = archivo.relative_to(origen)
    stem = archivo.stem.replace("-filtered", "")
    nombre = f"{stem}-compressed-{CODE_QUALITY}.mp4"
    return destino_base / rel.parent / nombre


def comprimir(handbrake: str, archivo: Path, destino: Path) -> subprocess.CompletedProcess:
    destino.parent.mkdir(parents=True, exist_ok=True)
    # nombre temporal: recién al terminar OK se renombra al definitivo
    temporal = destino.parent / f".tmp-{destino.name}"
    if temporal.exists():
        temporal.unlink()

    comando = [
        handbrake,
        "-i", str(archivo),
        "-o", str(temporal),
        "--ab", AUDIO_BITRATE,
        "-q", QUALITY_VALUES[CODE_QUALITY],
    ]
    resultado = subprocess.run(comando, capture_output=True, text=True)

    if resultado.returncode == 0 and temporal.exists() and temporal.stat().st_size > 0:
        temporal.rename(destino)
    elif temporal.exists():
        temporal.unlink()  # limpiar el archivo trunco
    return resultado


def main() -> None:
    origen = Path(sys.argv[1]).expanduser().resolve() if len(sys.argv) > 1 else Path.cwd()
    if not origen.is_dir():
        print(f"No existe la carpeta: {origen}")
        sys.exit(1)

    handbrake = buscar_handbrake()
    destino_base = origen.parent / f"{origen.name}-compressed"

    print(f"Origen:  {origen}")
    print(f"Destino: {destino_base}")
    print(f"Calidad: {CODE_QUALITY}, audio {AUDIO_BITRATE} kbps")
    print("")

    candidatos = [
        p for p in sorted(origen.rglob("*"))
        if p.is_file()
        and p.suffix.lower() in EXT_VIDEO
        and not p.name.startswith(".")
        and not any("-compressed" in parte for parte in p.parts)
        and "_sensibles" not in p.parts  # excluye lo filtrado por filtrar_sensibles.py
        and "sensibles-revision-humana" not in p.parts  # excluye lo apartado a mano
    ]

    if not candidatos:
        print("No se encontraron videos para comprimir.")
        return

    ok, salteados, errores = 0, 0, 0
    total = len(candidatos)
    with open(origen / "errors.txt", "a+") as log:
        for i, archivo in enumerate(candidatos, 1):
            destino = ruta_destino(archivo, origen, destino_base)
            if destino.exists():
                salteados += 1
                continue

            if not archivo.exists():
                errores += 1
                log.write(json.dumps({
                    "archivo": str(archivo),
                    "error": "el archivo ya no existe (¿movido o borrado por otro proceso?)",
                }) + ",\n")
                print(f"[{i}/{total}] SALTEADO: {archivo.name} ya no está donde estaba (¿lo movió otro proceso?)")
                continue

            original_mb = archivo.stat().st_size / (1024 * 1024)
            print(f"[{i}/{total}] Comprimiendo {archivo.relative_to(origen)} ({original_mb:.1f} MB)...")

            resultado = comprimir(handbrake, archivo, destino)

            if resultado.returncode == 0 and destino.exists():
                final_mb = destino.stat().st_size / (1024 * 1024)
                ok += 1
                print(f"          -> {final_mb:.1f} MB")
            else:
                errores += 1
                log.write(json.dumps({
                    "archivo": str(archivo),
                    "returncode": resultado.returncode,
                    "stderr": (resultado.stderr or "")[-500:],
                }) + ",\n")
                print(f"          ERROR (logueado en errors.txt)")

    print(f"\nListo: {ok} comprimidos, {salteados} ya existían (salteados), {errores} errores.")
    print(f"Versiones comprimidas en: {destino_base}")
    print("Los originales quedaron intactos.")


if __name__ == "__main__":
    main()
