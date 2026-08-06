#!/usr/bin/env python3
"""
Devolución post-revisión humana (paso intermedio del pipeline).

Se corre DESPUÉS de que revisaste _sensibles/ a mano y moviste lo
realmente sensible a sensibles-revision-humana/.

Qué hace:
  - Todo lo que quedó en _sensibles/ (= falsos positivos) vuelve a su
    ubicación original (la subcarpeta espejo dice de dónde salió),
    agregándole -filtered al nombre para que el filtro no lo vuelva
    a tocar en futuras corridas
  - A lo que moviste a sensibles-revision-humana/ también le agrega
    -filtered (por si algún día devolvés algo de ahí a mano)
  - Registra todo en _sensibles/movimientos.txt
  - Limpia las subcarpetas vacías que queden en _sensibles/

Uso:
  python3 devolver_sensibles.py .
"""

from __future__ import annotations

import datetime
import shutil
import sys
from pathlib import Path

CARPETA_SENSIBLES = "_sensibles"
CARPETA_REVISION = "sensibles-revision-humana"


def con_sufijo_filtered(ruta: Path) -> str:
    """Nombre del archivo con -filtered agregado (si no lo tiene ya)."""
    if "-filtered" in ruta.stem:
        return ruta.name
    return f"{ruta.stem}-filtered{ruta.suffix}"


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    base = Path(sys.argv[1]).expanduser().resolve()
    if not base.is_dir():
        print(f"No existe la carpeta: {base}")
        sys.exit(1)

    sensibles = base / CARPETA_SENSIBLES
    revision = base / CARPETA_REVISION
    revision.mkdir(exist_ok=True)

    if not sensibles.is_dir():
        print(f"No existe {CARPETA_SENSIBLES}/ — nada para devolver.")
        return

    ruta_log = sensibles / "movimientos.txt"
    devueltos, marcados_revision = 0, 0

    with open(ruta_log, "a") as log:
        log.write(f"\n# Devolución post-revisión {datetime.datetime.now():%Y-%m-%d %H:%M:%S}\n")

        # 1) Devolver los falsos positivos que quedaron en _sensibles/
        archivos = [
            p for p in sorted(sensibles.rglob("*"))
            if p.is_file() and p.name != "movimientos.txt" and not p.name.startswith(".")
        ]
        for archivo in archivos:
            rel = archivo.relative_to(sensibles)
            destino = base / rel.parent / con_sufijo_filtered(archivo)
            destino.parent.mkdir(parents=True, exist_ok=True)
            i = 1
            while destino.exists():
                destino = destino.with_name(f"{destino.stem}_{i}{destino.suffix}")
                i += 1
            shutil.move(str(archivo), str(destino))
            devueltos += 1
            log.write(f"DEVUELTO: {CARPETA_SENSIBLES}/{rel} -> {destino.relative_to(base)}\n")
            print(f"  DEVUELTO: {rel} -> {destino.relative_to(base)}")

        # 2) Marcar con -filtered lo que quedó en sensibles-revision-humana/
        for archivo in sorted(revision.rglob("*")):
            if not archivo.is_file() or archivo.name.startswith("."):
                continue
            if "-filtered" in archivo.stem:
                continue
            nuevo = archivo.with_name(con_sufijo_filtered(archivo))
            j = 1
            while nuevo.exists():
                nuevo = archivo.with_name(f"{archivo.stem}-filtered_{j}{archivo.suffix}")
                j += 1
            archivo.rename(nuevo)
            marcados_revision += 1
            log.write(f"REVISION HUMANA (marcado): {nuevo.relative_to(base)}\n")

        # 3) Limpiar subcarpetas vacías de _sensibles/
        for carpeta in sorted(sensibles.rglob("*"), reverse=True):
            if carpeta.is_dir() and not any(carpeta.iterdir()):
                carpeta.rmdir()

    print(f"\nListo: {devueltos} archivos devueltos a su ubicación original,")
    print(f"{marcados_revision} marcados en {CARPETA_REVISION}/.")
    print("Todos quedaron con -filtered: el filtro no los vuelve a analizar.")


if __name__ == "__main__":
    main()
