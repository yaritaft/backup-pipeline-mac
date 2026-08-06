#!/bin/bash
#
# PIPELINE COMPLETO de backup - doble click para ejecutar.
#
#   0) Te pide el nombre de la tanda (ej: hasta-06-08-2026) y mueve lo que
#      haya en raw/ hacia <nombre>/  (la bandeja de entrada se vacía)
#   1) Clasifica los archivos en carpetas          (en esta ventana)
#   2) Filtra fotos/videos sensibles a _sensibles/ (en esta ventana)
#   3) Comprime imágenes  -> abre su propia ventana de Terminal ┐ en paralelo
#   4) Comprime videos    -> abre su propia ventana de Terminal ┘
#
# Este .command va en la RAÍZ (carpeta madre), al lado de scripts/ y raw/:
#   carpeta-madre/
#   ├── pipeline.command  <- ACÁ, es lo que clickeás
#   ├── scripts/          <- los .py y los .command de cada paso
#   ├── raw/              <- tirás la descarga cruda de Image Capture
#   ├── <nombre>/            <- lo clasificado (hermano de scripts)
#   └── <nombre>-compressed/ <- el espejo comprimido (hermano de scripts)

cd "$(dirname "$0")" || exit 1
MADRE="$(pwd)"                         # carpeta madre (donde está este .command)
SCRIPTS="$MADRE/scripts"               # los .py viven acá
RAW="$MADRE/raw"

echo "=============================================="
echo "  PIPELINE DE BACKUP"
echo "  Scripts:       $SCRIPTS"
echo "  Carpeta madre: $MADRE"
echo "  Bandeja raw:   $RAW"
echo "=============================================="
echo ""

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# ---- Chequeos previos (todo junto, antes de arrancar nada) ----
FALTA=0
for script in clasificar_fotos.py filtrar_sensibles.py devolver_sensibles.py comprimir_imagenes.py comprimir_videos.py; do
    if [ ! -f "$SCRIPTS/$script" ]; then
        echo "ERROR: falta $script en la carpeta scripts/."
        FALTA=1
    fi
done
if ! command -v exiftool >/dev/null 2>&1; then
    echo "ERROR: falta exiftool (brew install exiftool)"
    FALTA=1
fi
if ! command -v HandBrakeCLI >/dev/null 2>&1 && ! command -v handbrakecli >/dev/null 2>&1; then
    echo "ERROR: falta HandBrakeCLI (brew install handbrake)"
    FALTA=1
fi
if ! python3 -c "import nudenet" 2>/dev/null; then
    echo "ERROR: faltan dependencias de Python (pip3 install -r requirements.txt)"
    FALTA=1
fi
if [ "$FALTA" = "1" ]; then
    echo ""
    read -r -p "Corregí lo de arriba y volvé a ejecutar. Enter para cerrar..."
    exit 1
fi

# ---- Paso 0: nombre de la tanda + traer lo de raw/ ----
mkdir -p "$RAW"
echo "Tandas que ya existen en la carpeta madre:"
hay_tandas=0
for d in "$MADRE"/*/; do
    [ -d "$d" ] || continue
    nombre_d="$(basename "$d")"
    case "$nombre_d" in
        scripts|raw|*-compressed) continue ;;
    esac
    echo "  - $nombre_d"
    hay_tandas=1
done
[ "$hay_tandas" = "0" ] && echo "  (ninguna todavía)"
echo ""
echo "Elegí el nombre de esta tanda. Podés escribir una que ya exista para"
echo "seguir procesándola (todo es incremental) o una nueva."
read -r -p "Nombre de la tanda (ej: hasta-06-08-2026): " NOMBRE

# Validaciones del nombre: no vacío y sin barras / nombres reservados
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

# Mover lo que haya en raw/ hacia la carpeta de la tanda (la bandeja se vacía)
shopt -s nullglob
raw_items=("$RAW"/*)
shopt -u nullglob
if [ ${#raw_items[@]} -gt 0 ]; then
    echo ""
    echo "Voy a mover ${#raw_items[@]} elemento(s) de raw/ hacia $NOMBRE/."
    mkdir -p "$DESTINO"
    mv "${raw_items[@]}" "$DESTINO"/
    echo "Bandeja raw/ vaciada."
elif [ ! -d "$DESTINO" ]; then
    echo ""
    echo "raw/ está vacía y la tanda '$NOMBRE' no existe: no hay nada para procesar."
    echo "Tirá la descarga del iPhone en: $RAW"
    read -r -p "Presioná Enter para cerrar..."
    exit 1
else
    echo ""
    echo "raw/ está vacía; sigo con lo que ya haya en $NOMBRE/ (modo incremental)."
fi

echo ""
echo "Pasos:"
echo "  1) Clasificar (mueve archivos a sus carpetas dentro de $NOMBRE/)"
echo "  2) Filtrar sensibles (mueve a $NOMBRE/_sensibles/)"
echo "  2.5) PAUSA: revisás _sensibles/ a mano, movés lo realmente sensible"
echo "       a sensibles-revision-humana/, y con tu OK el resto vuelve solo"
echo "       a su lugar con -filtered"
echo "  3 y 4) Comprimir imágenes y videos EN PARALELO, cada uno en su ventana"
echo "         (destino: $NOMBRE-compressed/)"
echo ""
read -r -p "¿Arrancar? (s/n): " respuesta
if [ "$respuesta" != "s" ] && [ "$respuesta" != "S" ] && [ "$respuesta" != "si" ] && [ "$respuesta" != "Si" ]; then
    echo "OK, no se hizo nada."
    read -r -p "Presioná Enter para cerrar..."
    exit 0
fi

# ---- Paso 1: clasificar ----
echo ""
echo "== PASO 1/4: Clasificando =="
python3 "$SCRIPTS/clasificar_fotos.py" "$DESTINO" --mover || {
    echo "ERROR en el clasificador. Se corta acá para no seguir con datos a medias."
    read -r -p "Presioná Enter para cerrar..."
    exit 1
}

# ---- Paso 2: filtrar sensibles ----
echo ""
echo "== PASO 2/4: Filtrando contenido sensible (local) =="
python3 "$SCRIPTS/filtrar_sensibles.py" "$DESTINO" || {
    echo "ERROR en el filtro. Se corta acá: los compresores no deben correr"
    echo "hasta que el filtrado esté completo."
    read -r -p "Presioná Enter para cerrar..."
    exit 1
}

# ---- Paso 2.5: revisión humana de _sensibles/ ----
mkdir -p "$DESTINO/sensibles-revision-humana"
echo ""
echo "== REVISIÓN HUMANA =="
echo "1) Mirá lo que el filtro detectó en $NOMBRE/_sensibles/ (te la abro en Finder)."
echo "2) Mové lo REALMENTE sensible a: $NOMBRE/sensibles-revision-humana/"
echo "3) El resto dejalo donde está: se devuelve solo a su lugar original."
echo ""
open "$DESTINO/_sensibles" 2>/dev/null
open "$DESTINO/sensibles-revision-humana" 2>/dev/null
read -r -p "Cuando termines la revisión, escribí s para continuar: " listo
while [ "$listo" != "s" ] && [ "$listo" != "S" ] && [ "$listo" != "si" ] && [ "$listo" != "Si" ]; do
    read -r -p "Escribí s cuando la revisión esté lista: " listo
done

echo ""
echo "== Devolviendo falsos positivos a su lugar =="
python3 "$SCRIPTS/devolver_sensibles.py" "$DESTINO" || {
    echo "ERROR en la devolución. Se corta acá."
    read -r -p "Presioná Enter para cerrar..."
    exit 1
}

# ---- Pasos 3 y 4: compresores en paralelo, cada uno en su ventana ----
echo ""
echo "== PASOS 3 y 4: Abriendo dos ventanas de Terminal =="

# Nombre único por corrida (incluye el PID). La compresión de video es larga;
# si otra corrida del pipeline usara el mismo /tmp lo pisaría mientras este
# runner todavía está leyéndose -> "unexpected EOF". Con $$ nunca se pisan.
RUNNER_IMG="/tmp/pipeline-comprimir-imagenes-$$.command"
cat > "$RUNNER_IMG" <<EOF
#!/bin/bash
cd "$SCRIPTS" || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:\$PATH"
echo "== COMPRESOR DE IMÁGENES =="
python3 "$SCRIPTS/comprimir_imagenes.py" "$DESTINO"
echo ""
read -r -p "Imágenes: listo. Presioná Enter para cerrar..."
EOF
chmod +x "$RUNNER_IMG"

RUNNER_VID="/tmp/pipeline-comprimir-videos-$$.command"
cat > "$RUNNER_VID" <<EOF
#!/bin/bash
cd "$SCRIPTS" || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:\$PATH"
echo "== COMPRESOR DE VIDEOS =="
python3 "$SCRIPTS/comprimir_videos.py" "$DESTINO"
echo ""
read -r -p "Videos: listo. Presioná Enter para cerrar..."
EOF
chmod +x "$RUNNER_VID"

open "$RUNNER_IMG"
open "$RUNNER_VID"

echo ""
echo "Listo: clasificación y filtrado terminados."
echo "Los dos compresores están corriendo en sus propias ventanas."
echo "El destino es: ${DESTINO}-compressed"
echo ""
echo "Recordá revisar $NOMBRE/_sensibles/ por falsos positivos cuando termine todo."
read -r -p "Presioná Enter para cerrar esta ventana..."
