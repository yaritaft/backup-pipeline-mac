#!/bin/bash
#
# Compresor de imágenes - doble click para ejecutar.
# Comprime las imágenes de la carpeta donde está este archivo (y subcarpetas)
# hacia una carpeta hermana "<carpeta>-compressed". NO borra originales.
# Debe estar junto a comprimir_imagenes.py

cd "$(dirname "$0")" || exit 1

echo "=============================================="
echo "  Compresor de imágenes (JPG / PNG / HEIC)"
echo "  Origen:  $(pwd)"
echo "  Destino: $(pwd)-compressed"
echo "=============================================="
echo ""

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if [ ! -f "comprimir_imagenes.py" ]; then
    echo "ERROR: no se encontró comprimir_imagenes.py en esta carpeta."
    read -r -p "Presioná Enter para cerrar..."
    exit 1
fi

if ! python3 -c "import PIL" 2>/dev/null; then
    echo "Faltan dependencias. Instalando..."
    pip3 install Pillow pillow-heif || {
        echo ""
        echo "Falló la instalación automática. Probá a mano:"
        echo "  pip3 install Pillow pillow-heif"
        read -r -p "Presioná Enter para cerrar..."
        exit 1
    }
fi

read -r -p "¿Comprimir? Los originales NO se tocan. (s/n): " respuesta

if [ "$respuesta" = "s" ] || [ "$respuesta" = "S" ] || [ "$respuesta" = "si" ] || [ "$respuesta" = "Si" ]; then
    echo ""
    python3 comprimir_imagenes.py .
else
    echo ""
    echo "OK, no se hizo nada."
fi

echo ""
read -r -p "Presioná Enter para cerrar..."
