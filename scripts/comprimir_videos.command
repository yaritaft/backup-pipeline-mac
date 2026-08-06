#!/bin/bash
#
# Compresor de videos - doble click para ejecutar.
#
# Vive en scripts/. Te pide qué tanda comprimir (../<nombre>/) y genera el
# espejo hermano ../<nombre>-compressed/. NO borra ni toca los originales.

cd "$(dirname "$0")" || exit 1
SCRIPTS="$(pwd)"
MADRE="$(dirname "$SCRIPTS")"

echo "=============================================="
echo "  Compresor de videos (MP4 / MOV / M4V)"
echo "  Carpeta madre: $MADRE"
echo "=============================================="
echo ""
echo "AVISO: comprimir video es LENTO. Podés cortar con"
echo "Ctrl+C cuando quieras y retomar despues: sigue"
echo "desde donde quedó."
echo ""

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if [ ! -f "$SCRIPTS/comprimir_videos.py" ]; then
    echo "ERROR: no se encontró comprimir_videos.py en scripts/."
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

# Elegir tanda existente
echo "Tandas disponibles:"
for d in "$MADRE"/*/; do
    [ -d "$d" ] || continue
    nombre_d="$(basename "$d")"
    case "$nombre_d" in scripts|raw|*-compressed) continue ;; esac
    echo "  - $nombre_d"
done
echo ""
read -r -p "Nombre de la tanda a comprimir: " NOMBRE
DESTINO="$MADRE/$NOMBRE"
if [ -z "$NOMBRE" ] || [ ! -d "$DESTINO" ]; then
    echo "No existe la tanda '$NOMBRE' en $MADRE."
    read -r -p "Presioná Enter para cerrar..."
    exit 1
fi
echo "Destino: $NOMBRE-compressed/"
echo ""

read -r -p "¿Comprimir todos los videos? Los originales NO se tocan. (s/n): " respuesta

if [ "$respuesta" = "s" ] || [ "$respuesta" = "S" ] || [ "$respuesta" = "si" ] || [ "$respuesta" = "Si" ]; then
    echo ""
    python3 "$SCRIPTS/comprimir_videos.py" "$DESTINO"
else
    echo ""
    echo "OK, no se hizo nada."
fi

echo ""
read -r -p "Presioná Enter para cerrar..."
