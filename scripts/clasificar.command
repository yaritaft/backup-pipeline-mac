#!/bin/bash
#
# Clasificador de fotos/videos de iPhone - doble click para ejecutar.
#
# Vive en scripts/. Te pide el nombre de la tanda, trae lo que haya en
# ../raw/ hacia ../<nombre>/ y clasifica esa carpeta (sin tocar los scripts).

cd "$(dirname "$0")" || exit 1
SCRIPTS="$(pwd)"
MADRE="$(dirname "$SCRIPTS")"
RAW="$MADRE/raw"

echo "=============================================="
echo "  Clasificador de fotos/videos de iPhone"
echo "  Carpeta madre: $MADRE"
echo "=============================================="
echo ""

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Chequeos previos
if ! command -v exiftool >/dev/null 2>&1; then
    echo "ERROR: no se encontró exiftool."
    echo "Instalalo con:  brew install exiftool"
    echo ""
    read -r -p "Presioná Enter para cerrar..."
    exit 1
fi
if [ ! -f "$SCRIPTS/clasificar_fotos.py" ]; then
    echo "ERROR: no se encontró clasificar_fotos.py en scripts/."
    read -r -p "Presioná Enter para cerrar..."
    exit 1
fi

# Elegir tanda (podés crear una nueva o seguir una existente)
mkdir -p "$RAW"
echo "Tandas que ya existen:"
for d in "$MADRE"/*/; do
    [ -d "$d" ] || continue
    nombre_d="$(basename "$d")"
    case "$nombre_d" in scripts|raw|*-compressed) continue ;; esac
    echo "  - $nombre_d"
done
echo ""
read -r -p "Nombre de la tanda (ej: hasta-06-08-2026): " NOMBRE
if [ -z "$NOMBRE" ]; then
    echo "No escribiste ningún nombre. Se corta acá."
    read -r -p "Presioná Enter para cerrar..."
    exit 1
fi
case "$NOMBRE" in
    */*|scripts|raw|*-compressed)
        echo "Nombre inválido (no uses barras ni 'scripts'/'raw'/'*-compressed')."
        read -r -p "Presioná Enter para cerrar..."
        exit 1 ;;
esac
DESTINO="$MADRE/$NOMBRE"

# Traer lo que haya en raw/ hacia la tanda
shopt -s nullglob
raw_items=("$RAW"/*)
shopt -u nullglob
if [ ${#raw_items[@]} -gt 0 ]; then
    echo "Moviendo ${#raw_items[@]} elemento(s) de raw/ hacia $NOMBRE/..."
    mkdir -p "$DESTINO"
    mv "${raw_items[@]}" "$DESTINO"/
elif [ ! -d "$DESTINO" ]; then
    echo "raw/ está vacía y la tanda '$NOMBRE' no existe: no hay nada para clasificar."
    echo "Tirá la descarga del iPhone en: $RAW"
    read -r -p "Presioná Enter para cerrar..."
    exit 1
fi

# Paso 1: dry-run (análisis sin mover nada)
echo ""
echo "Analizando (esto puede tardar varios minutos con muchos archivos)..."
echo ""
python3 "$SCRIPTS/clasificar_fotos.py" "$DESTINO"

echo ""
echo "----------------------------------------------"
read -r -p "¿Mover los archivos según este resumen? (s/n): " respuesta

if [ "$respuesta" = "s" ] || [ "$respuesta" = "S" ] || [ "$respuesta" = "si" ] || [ "$respuesta" = "Si" ]; then
    echo ""
    python3 "$SCRIPTS/clasificar_fotos.py" "$DESTINO" --mover
    echo ""
    echo "¡Listo!"
else
    echo ""
    echo "OK, no se movió nada."
fi

echo ""
read -r -p "Presioná Enter para cerrar..."
