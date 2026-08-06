#!/bin/bash
#
# Compresor de imágenes - doble click para ejecutar.
#
# Vive en scripts/. Te pide qué tanda comprimir (../<nombre>/) y genera el
# espejo hermano ../<nombre>-compressed/. NO borra ni toca los originales.

cd "$(dirname "$0")" || exit 1
SCRIPTS="$(pwd)"
MADRE="$(dirname "$SCRIPTS")"

echo "=============================================="
echo "  Compresor de imágenes (JPG / PNG / HEIC)"
echo "  Carpeta madre: $MADRE"
echo "=============================================="
echo ""

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if [ ! -f "$SCRIPTS/comprimir_imagenes.py" ]; then
    echo "ERROR: no se encontró comprimir_imagenes.py en scripts/."
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

read -r -p "¿Comprimir? Los originales NO se tocan. (s/n): " respuesta

if [ "$respuesta" = "s" ] || [ "$respuesta" = "S" ] || [ "$respuesta" = "si" ] || [ "$respuesta" = "Si" ]; then
    echo ""
    python3 "$SCRIPTS/comprimir_imagenes.py" "$DESTINO"
else
    echo ""
    echo "OK, no se hizo nada."
fi

echo ""
read -r -p "Presioná Enter para cerrar..."
