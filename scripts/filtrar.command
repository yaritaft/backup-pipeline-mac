#!/bin/bash
#
# Filtro de fotos/videos sensibles - doble click para ejecutar.
#
# Vive en scripts/. Te pide qué tanda analizar (../<nombre>/) con un modelo
# LOCAL (nada sale de tu máquina) y mueve lo detectado a <nombre>/_sensibles/.
# Cada movimiento queda registrado en _sensibles/movimientos.txt

cd "$(dirname "$0")" || exit 1
SCRIPTS="$(pwd)"
MADRE="$(dirname "$SCRIPTS")"

echo "=============================================="
echo "  Filtro de contenido sensible (local)"
echo "  Carpeta madre: $MADRE"
echo "=============================================="
echo ""
echo "Lo detectado se mueve a <tanda>/_sensibles/ y queda registrado en"
echo "_sensibles/movimientos.txt (origen -> destino) para poder devolver"
echo "falsos positivos a mano."
echo ""

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if [ ! -f "$SCRIPTS/filtrar_sensibles.py" ]; then
    echo "ERROR: no se encontró filtrar_sensibles.py en scripts/."
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

# Elegir tanda existente
echo "Tandas disponibles:"
for d in "$MADRE"/*/; do
    [ -d "$d" ] || continue
    nombre_d="$(basename "$d")"
    case "$nombre_d" in scripts|raw|*-compressed) continue ;; esac
    echo "  - $nombre_d"
done
echo ""
read -r -p "Nombre de la tanda a filtrar: " NOMBRE
DESTINO="$MADRE/$NOMBRE"
if [ -z "$NOMBRE" ] || [ ! -d "$DESTINO" ]; then
    echo "No existe la tanda '$NOMBRE' en $MADRE."
    read -r -p "Presioná Enter para cerrar..."
    exit 1
fi

read -r -p "¿Analizar y mover lo sensible a $NOMBRE/_sensibles/? (s/n): " respuesta

if [ "$respuesta" = "s" ] || [ "$respuesta" = "S" ] || [ "$respuesta" = "si" ] || [ "$respuesta" = "Si" ]; then
    echo ""
    python3 "$SCRIPTS/filtrar_sensibles.py" "$DESTINO"
    echo ""
    echo "Revisá $NOMBRE/_sensibles/ por si hay falsos positivos."
else
    echo ""
    echo "OK, no se hizo nada."
fi

echo ""
read -r -p "Presioná Enter para cerrar..."
