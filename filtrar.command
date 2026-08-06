#!/bin/bash
#
# Filtro de fotos/videos sensibles - doble click para ejecutar.
# Analiza la carpeta donde está este archivo (y subcarpetas) con un
# modelo LOCAL (nada sale de tu máquina) y mueve lo detectado a _sensibles/
# Cada movimiento queda registrado en _sensibles/movimientos.txt
# Debe estar junto a filtrar_sensibles.py

cd "$(dirname "$0")" || exit 1

echo "=============================================="
echo "  Filtro de contenido sensible (local)"
echo "  Carpeta: $(pwd)"
echo "=============================================="
echo ""
echo "Lo detectado se mueve a _sensibles/ y queda registrado"
echo "en _sensibles/movimientos.txt (origen -> destino) para"
echo "poder devolver falsos positivos a mano."
echo ""

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if [ ! -f "filtrar_sensibles.py" ]; then
    echo "ERROR: no se encontró filtrar_sensibles.py en esta carpeta."
    read -r -p "Presioná Enter para cerrar..."
    exit 1
fi

if ! python3 -c "import nudenet" 2>/dev/null; then
    echo "Faltan dependencias. Instalando (puede tardar unos minutos)..."
    pip3 install nudenet opencv-python-headless pillow-heif || {
        echo ""
        echo "Falló la instalación automática. Probá a mano:"
        echo "  pip3 install nudenet opencv-python-headless pillow-heif"
        read -r -p "Presioná Enter para cerrar..."
        exit 1
    }
fi

read -r -p "¿Analizar y mover lo sensible a _sensibles/? (s/n): " respuesta

if [ "$respuesta" = "s" ] || [ "$respuesta" = "S" ] || [ "$respuesta" = "si" ] || [ "$respuesta" = "Si" ]; then
    echo ""
    python3 filtrar_sensibles.py .
    echo ""
    echo "Revisá _sensibles/ por si hay falsos positivos."
else
    echo ""
    echo "OK, no se hizo nada."
fi

echo ""
read -r -p "Presioná Enter para cerrar..."
