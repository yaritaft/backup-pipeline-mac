#!/bin/bash
#
# Compresor de videos - doble click para ejecutar.
# Comprime los videos de la carpeta donde está este archivo (y subcarpetas)
# hacia la carpeta hermana "<carpeta>-compressed". NO borra originales.
# Debe estar junto a comprimir_videos.py

cd "$(dirname "$0")" || exit 1

echo "=============================================="
echo "  Compresor de videos (MP4 / MOV / M4V)"
echo "  Origen:  $(pwd)"
echo "  Destino: $(pwd)-compressed"
echo "=============================================="
echo ""
echo "AVISO: comprimir video es LENTO. Podés cortar con"
echo "Ctrl+C cuando quieras y retomar despues: sigue"
echo "desde donde quedó."
echo ""

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if [ ! -f "comprimir_videos.py" ]; then
    echo "ERROR: no se encontró comprimir_videos.py en esta carpeta."
    read -r -p "Presioná Enter para cerrar..."
    exit 1
fi

if ! command -v HandBrakeCLI >/dev/null 2>&1 && ! command -v handbrakecli >/dev/null 2>&1; then
    echo "ERROR: no se encontró HandBrakeCLI."
    echo "Instalalo con:  brew install handbrake"
    echo ""
    read -r -p "Presioná Enter para cerrar..."
    exit 1
fi

read -r -p "¿Comprimir todos los videos? Los originales NO se tocan. (s/n): " respuesta

if [ "$respuesta" = "s" ] || [ "$respuesta" = "S" ] || [ "$respuesta" = "si" ] || [ "$respuesta" = "Si" ]; then
    echo ""
    python3 comprimir_videos.py .
else
    echo ""
    echo "OK, no se hizo nada."
fi

echo ""
read -r -p "Presioná Enter para cerrar..."
