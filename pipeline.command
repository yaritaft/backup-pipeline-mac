#!/bin/bash
#
# PIPELINE COMPLETO de backup - doble click para ejecutar.
#
#   1) Clasifica los archivos en carpetas          (en esta ventana)
#   2) Filtra fotos/videos sensibles a _sensibles/ (en esta ventana)
#   3) Comprime imágenes  -> abre su propia ventana de Terminal ┐ en paralelo
#   4) Comprime videos    -> abre su propia ventana de Terminal ┘
#
# Debe estar junto a: clasificar_fotos.py, filtrar_sensibles.py,
#                     comprimir_imagenes.py, comprimir_videos.py

cd "$(dirname "$0")" || exit 1
CARPETA="$(pwd)"

echo "=============================================="
echo "  PIPELINE DE BACKUP"
echo "  Carpeta: $CARPETA"
echo "=============================================="
echo ""

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# ---- Chequeos previos (todo junto, antes de arrancar nada) ----
FALTA=0
for script in clasificar_fotos.py filtrar_sensibles.py devolver_sensibles.py comprimir_imagenes.py comprimir_videos.py; do
    if [ ! -f "$script" ]; then
        echo "ERROR: falta $script en esta carpeta."
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

echo "Pasos:"
echo "  1) Clasificar (mueve archivos a sus carpetas)"
echo "  2) Filtrar sensibles (mueve a _sensibles/)"
echo "  2.5) PAUSA: revisás _sensibles/ a mano, movés lo realmente sensible"
echo "       a sensibles-revision-humana/, y con tu OK el resto vuelve solo"
echo "       a su lugar con -filtered"
echo "  3 y 4) Comprimir imágenes y videos EN PARALELO, cada uno en su ventana"
echo "         (excluyen _sensibles/ y sensibles-revision-humana/)"
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
python3 clasificar_fotos.py . --mover || {
    echo "ERROR en el clasificador. Se corta acá para no seguir con datos a medias."
    read -r -p "Presioná Enter para cerrar..."
    exit 1
}

# ---- Paso 2: filtrar sensibles ----
echo ""
echo "== PASO 2/4: Filtrando contenido sensible (local) =="
python3 filtrar_sensibles.py . || {
    echo "ERROR en el filtro. Se corta acá: los compresores no deben correr"
    echo "hasta que el filtrado esté completo."
    read -r -p "Presioná Enter para cerrar..."
    exit 1
}

# ---- Paso 2.5: revisión humana de _sensibles/ ----
mkdir -p "sensibles-revision-humana"
echo ""
echo "== REVISIÓN HUMANA =="
echo "1) Mirá lo que el filtro detectó en _sensibles/ (te la abro en Finder)."
echo "2) Mové lo REALMENTE sensible a: sensibles-revision-humana/"
echo "3) El resto dejalo donde está: se devuelve solo a su lugar original."
echo ""
open "_sensibles" 2>/dev/null
open "sensibles-revision-humana" 2>/dev/null
read -r -p "Cuando termines la revisión, escribí s para continuar: " listo
while [ "$listo" != "s" ] && [ "$listo" != "S" ] && [ "$listo" != "si" ] && [ "$listo" != "Si" ]; do
    read -r -p "Escribí s cuando la revisión esté lista: " listo
done

echo ""
echo "== Devolviendo falsos positivos a su lugar =="
python3 devolver_sensibles.py . || {
    echo "ERROR en la devolución. Se corta acá."
    read -r -p "Presioná Enter para cerrar..."
    exit 1
}

# ---- Pasos 3 y 4: compresores en paralelo, cada uno en su ventana ----
echo ""
echo "== PASOS 3 y 4: Abriendo dos ventanas de Terminal =="

RUNNER_IMG="/tmp/pipeline-comprimir-imagenes.command"
cat > "$RUNNER_IMG" <<EOF
#!/bin/bash
cd "$CARPETA" || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:\$PATH"
echo "== COMPRESOR DE IMÁGENES =="
python3 comprimir_imagenes.py .
echo ""
read -r -p "Imágenes: listo. Presioná Enter para cerrar..."
EOF
chmod +x "$RUNNER_IMG"

RUNNER_VID="/tmp/pipeline-comprimir-videos.command"
cat > "$RUNNER_VID" <<EOF
#!/bin/bash
cd "$CARPETA" || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:\$PATH"
echo "== COMPRESOR DE VIDEOS =="
python3 comprimir_videos.py .
echo ""
read -r -p "Videos: listo. Presioná Enter para cerrar..."
EOF
chmod +x "$RUNNER_VID"

open "$RUNNER_IMG"
open "$RUNNER_VID"

echo ""
echo "Listo: clasificación y filtrado terminados."
echo "Los dos compresores están corriendo en sus propias ventanas."
echo "El destino es: ${CARPETA}-compressed"
echo ""
echo "Recordá revisar _sensibles/ por falsos positivos cuando termine todo."
read -r -p "Presioná Enter para cerrar esta ventana..."
