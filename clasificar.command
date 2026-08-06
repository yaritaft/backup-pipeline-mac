#!/bin/bash
#
# Clasificador de fotos/videos de iPhone - doble click para ejecutar.
# Debe estar en la MISMA carpeta que clasificar_fotos.py y que los
# archivos a clasificar.

# Pararse en la carpeta donde está este archivo
cd "$(dirname "$0")" || exit 1

echo "=============================================="
echo "  Clasificador de fotos/videos de iPhone"
echo "  Carpeta: $(pwd)"
echo "=============================================="
echo ""

# Asegurar que brew esté en el PATH (Apple Silicon e Intel)
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Chequeos previos
if ! command -v exiftool >/dev/null 2>&1; then
    echo "ERROR: no se encontró exiftool."
    echo "Instalalo con:  brew install exiftool"
    echo ""
    read -r -p "Presioná Enter para cerrar..."
    exit 1
fi

if [ ! -f "clasificar_fotos.py" ]; then
    echo "ERROR: no se encontró clasificar_fotos.py en esta carpeta."
    echo "Este .command tiene que estar junto al script de Python."
    echo ""
    read -r -p "Presioná Enter para cerrar..."
    exit 1
fi

# Paso 1: dry-run (análisis sin mover nada)
echo "Analizando (esto puede tardar varios minutos con muchos archivos)..."
echo ""
python3 clasificar_fotos.py .

echo ""
echo "----------------------------------------------"
read -r -p "¿Mover los archivos según este resumen? (s/n): " respuesta

if [ "$respuesta" = "s" ] || [ "$respuesta" = "S" ] || [ "$respuesta" = "si" ] || [ "$respuesta" = "Si" ]; then
    echo ""
    python3 clasificar_fotos.py . --mover
    echo ""
    echo "¡Listo!"
else
    echo ""
    echo "OK, no se movió nada."
fi

echo ""
read -r -p "Presioná Enter para cerrar..."
