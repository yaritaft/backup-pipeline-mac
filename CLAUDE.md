# CLAUDE.md — Contexto del proyecto

## Qué es esto

Pipeline de backup de fotos/videos de iPhone para Mac, desarrollado en conjunto
con Claude (chat) en agosto 2026. Procesa descargas masivas (via Captura de
Imagen / Image Capture, por cable) en 4 pasos: clasificar → filtrar sensibles →
revisión humana → comprimir (imágenes y videos en paralelo). Es el sucesor Mac
del repo `yaritaft/backup-scripts` (versión Windows).

El dueño del proyecto es Yari (@yaritaft). Idioma del proyecto: español
rioplatense (voseo) en comentarios, docstrings y mensajes al usuario.

## Arquitectura

Scripts standalone de Python (sin paquetes propios, solo stdlib + deps de
requirements.txt), cada uno con su `.command` para doble click en macOS, más
un `pipeline.command` maestro que orquesta todo.

**Estructura en disco (agosto 2026):** los scripts viven separados de lo
clasificado, en su propia carpeta `scripts/`. La descarga cruda se tira en
`raw/` (hermano de `scripts/`). El pipeline pide un nombre de tanda, mueve lo
de `raw/` a `../<nombre>/` (hermano de scripts) y procesa ahí; el espejo cae
en `../<nombre>-compressed/`. Los `.py` NO cambiaron: ya reciben la carpeta
como `sys.argv[1]` y calculan el espejo como `origen.parent/<name>-compressed`,
así que todo el trabajo de rutas vive en los `.command`. Los `.command` hacen
`SCRIPTS="$(dirname "$0")"`, `MADRE="$(dirname "$SCRIPTS")"`, y le pasan
`$MADRE/$NOMBRE` a los scripts.

```
carpeta-madre/           (ej: /Volumes/T7 Shield/BackupScript)
├── scripts/             <- .py + .command (este repo va acá adentro)
├── raw/                 <- bandeja de entrada; el pipeline la vacía
├── <nombre>/            <- tanda clasificada (hermano de scripts)
└── <nombre>-compressed/ <- espejo (hermano de scripts)
```

| Archivo (en `scripts/`) | Rol |
|---------|-----|
| `clasificar_fotos.py` | Paso 1: mueve archivos a carpetas por origen usando exiftool |
| `filtrar_sensibles.py` | Paso 2: NudeNet local; mueve detectados a `_sensibles/`, marca limpios con `-filtered` |
| `devolver_sensibles.py` | Paso 2.5: tras revisión humana, devuelve falsos positivos a su lugar |
| `comprimir_imagenes.py` | Paso 3: Pillow, calidad 75, espejo en `<carpeta>-compressed/` |
| `comprimir_videos.py` | Paso 4: HandBrakeCLI, 26RF, audio 160kbps, espejo idem |
| `pipeline.command` | Orquestador: 0 (pide nombre de tanda + vacía `raw/` a `../<nombre>/`) → 1 → 2 → pausa revisión → devolución → (3 ‖ 4 en ventanas de Terminal separadas) |

## Decisiones de diseño (NO romper sin consultar)

1. **Los originales nunca se tocan/borran.** La versión Windows original
   mandaba originales a la papelera tras comprimir; acá se abandonó ese
   diseño por el modelo espejo: `<carpeta>-compressed/` replica la
   estructura al lado de la original.
2. **Todo es incremental y re-ejecutable**: clasificador saltea carpetas ya
   clasificadas (pero re-analiza `_revisar/`), filtro saltea `-filtered`,
   compresores saltean destinos existentes. Cortar con Ctrl+C es seguro.
3. **Sufijos**:
   - `-filtered` en el ORIGINAL = ya analizado por el filtro (limpio o
     revisado por humano). El filtro no lo vuelve a tocar.
   - `-compressed-75` (imágenes) y `-compressed-26RF` (videos) en el espejo.
   - El compresor QUITA `-filtered` al armar el nombre destino (nombres del
     espejo estables entre corridas; no romper esto o se recomprime todo).
4. **Carpetas especiales** (excluidas de filtro y compresores):
   `_sensibles/` (staging del filtro, con `movimientos.txt` como registro),
   `sensibles-revision-humana/` (lo apartado a mano, NUNCA llega al espejo),
   cualquier `*-compressed*`.
5. **Orden estricto**: el filtro jamás en paralelo con los compresores
   (mueve archivos → FileNotFoundError en los compresores; pasó en
   producción). Los dos compresores sí pueden correr en paralelo entre sí.
6. **Clasificación por metadata real** (exiftool -json, SIN -fast2 porque
   los videos tienen la metadata al final), con reglas acordadas con Yari:
   - PNG → capturas; HEIC/HEIF/JPG/DNG con Make Apple → fotos_propias
   - MOV con metadata Apple → videos_propios; MOV/QT sin Apple → videos_recibidos
   - MP4 con keywords bytedance/tiktok → tiktok; instagram → instagram;
     MP4 sin fuente → instagram-tiktok; JPG sin EXIF cámara → whatsapp
   - .AAE acompaña a su foto (match por stem); .DAT se clasifica por
     contenido real; resto → _revisar
7. **Compatibilidad Python 3.8+** via `from __future__ import annotations`
   (la Mac de Yari tuvo pyenv 3.8; se recomendó migrar a 3.12 por
   pillow-heif precompilado). No usar sintaxis 3.9+ sin ese import.
8. **Robustez aprendida en producción**: decodificación tolerante de la
   salida de exiftool (bytes 0xb0 de GPS), archivos temporales `.tmp-` en
   HandBrake renombrados solo al éxito, skip de archivos que desaparecen
   mid-run, freno de emergencia en el filtro (25 errores consecutivos o
   carpeta base ausente = disco desconectado).

## Convenciones

- Nombres de funciones/variables en español, snake_case.
- Cada script: docstring largo arriba con qué hace / requisitos / uso.
- Los `.command` hacen `cd "$(dirname "$0")"`, exportan
  PATH=/opt/homebrew/bin:..., chequean dependencias, piden confirmación
  s/n, y terminan con `read -p "Presioná Enter para cerrar..."`.
- Errores por archivo se loguean y se sigue; nunca abortar por un archivo.

## Estado actual y pendientes

- Los 4 pasos + orquestador: funcionando, probados en la colección real
  (~3500+ archivos en `/Volumes/T7 Shield/BackupScript`).
- Pendiente conocido: en Python 3.8 pillow-heif no compila → los HEIC se
  saltean en el filtro con aviso. Solución: migrar a Python 3.12.
- Ideas mencionadas no implementadas: candado anti-doble-ejecución de un
  mismo compresor; muestreo de video adaptativo (cuadro cada X segundos en
  vez de 8 fijos); `caffeinate` en los `.command` para corridas largas;
  script que borre del espejo lo comprimido antes de un filtrado tardío
  (leyendo `movimientos.txt`).
- Tarea inmediata típica: crear el repo en GitHub (`gh repo create
  backup-pipeline-mac --public --source=. --push`).
