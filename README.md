# Backup Pipeline para fotos/videos de iPhone (Mac)

Pipeline de 4 pasos para procesar descargas masivas de fotos y videos de iPhone
en Mac: clasifica por origen, filtra contenido sensible con un modelo local,
y genera una copia comprimida lista para subir a la nube — sin tocar jamás
los archivos originales.

Sucesor para Mac de [backup-scripts](https://github.com/yaritaft/backup-scripts)
(la versión Windows), con clasificación automática y filtrado de sensibles
agregados.

## El flujo completo

```
Descarga del iPhone (Captura de Imagen / Image Capture, por cable)
        |
        v
1) CLASIFICAR ─── mueve cada archivo a su carpeta según su origen
        |         (fotos propias, capturas, tiktok, whatsapp, etc.)
        v
2) FILTRAR ────── detecta desnudez/semidesnudez con un modelo LOCAL
        |         y aparta lo detectado a _sensibles/
        v
2.5) REVISIÓN ─── vos movés lo realmente sensible a
        |         sensibles-revision-humana/; el resto vuelve solo
        |         a su lugar (marcado con -filtered)
        v
3) + 4) COMPRIMIR (imágenes y videos EN PARALELO, cada uno en su
        |         ventana de Terminal)
        v
<carpeta>-compressed/   <- espejo comprimido, SIN lo sensible,
                           listo para subir a la nube
```

Los originales quedan intactos siempre. Ningún paso borra nada.

## Instalación

```bash
# Dependencias de sistema
brew install exiftool handbrake libheif

# Dependencias de Python (recomendado: Python 3.9+, ideal 3.12)
pip3 install -r requirements.txt

# Permisos de ejecución para los .command
chmod +x *.command
```

Nota: en Python <= 3.8, `pillow-heif` se compila desde el código fuente y
puede fallar. Con Python 3.9+ se instala precompilado. Si usás pyenv:
`pyenv install 3.12 && pyenv global 3.12`.

La primera vez que abras un `.command` descargado, macOS lo bloquea por
cuarentena: click derecho → Abrir → confirmar. Solo la primera vez.

## Uso

### Todo junto (recomendado)

1. Poné todos los archivos de este repo en la carpeta con las fotos/videos
   descargados del iPhone.
2. Doble click a **`pipeline.command`**.
3. El pipeline clasifica y filtra, después te abre `_sensibles/` en Finder:
   mové lo realmente sensible a `sensibles-revision-humana/` y escribí `s`.
   El resto vuelve solo a su carpeta original.
4. Se abren dos ventanas de Terminal con los compresores en paralelo.
   Cuando terminan, la carpeta hermana `<carpeta>-compressed/` tiene la
   copia lista para la nube.

### Paso por paso (opcional)

Cada paso tiene su propio `.command` (doble click) o se puede correr por consola:

| Paso | Doble click | Consola |
|------|-------------|---------|
| 1. Clasificar | `clasificar.command` | `python3 clasificar_fotos.py . --mover` |
| 2. Filtrar | `filtrar.command` | `python3 filtrar_sensibles.py .` |
| 2.5 Devolver post-revisión | (incluido en pipeline) | `python3 devolver_sensibles.py .` |
| 3. Comprimir imágenes | `comprimir.command` | `python3 comprimir_imagenes.py .` |
| 4. Comprimir videos | `comprimir_videos.command` | `python3 comprimir_videos.py .` |

El clasificador por consola tiene modo dry-run: sin `--mover` solo muestra
qué haría.

## Cómo clasifica (paso 1)

Usa la metadata real de cada archivo (via exiftool) más convenciones de
nombres de iOS:

| Carpeta | Regla |
|---------|-------|
| `fotos_propias/` | HEIC/HEIF/JPG/DNG con EXIF de cámara Apple |
| `videos_propios/` | MOV con metadata QuickTime de Apple |
| `capturas/` | PNG (iOS guarda las capturas de pantalla siempre en PNG) |
| `tiktok/` | MP4 con metadata de ByteDance/TikTok (confirmado) |
| `instagram/` | MP4 con rastros de Instagram (confirmado) |
| `instagram-tiktok/` | MP4 descargado sin fuente identificable |
| `whatsapp/` | JPG sin EXIF de cámara (fotos recibidas) |
| `videos_recibidos/` | MOV/QT sin metadata de Apple (videos que te pasaron) |
| `_revisar/` | lo que no encaja en nada de lo anterior |

Los `.AAE` (ediciones de Apple) acompañan automáticamente a su foto.
Los `.DAT` se clasifican por su contenido real, no por la extensión.
La carpeta `_revisar/` se re-analiza en cada corrida.

## Cómo filtra (paso 2)

- Modelo [NudeNet](https://github.com/notAI-tech/NudeNet) corriendo **100%
  local**: ninguna imagen sale de tu máquina.
- Detecta desnudez y semidesnudez (ropa interior / bikini). Configurable en
  `filtrar_sensibles.py`: `CLASES_SENSIBLES` (sacá las `_COVERED` si solo
  querés desnudez explícita) y `UMBRAL` (0.5 default; más bajo = más
  estricto, más falsos positivos).
- Videos: muestrea `CUADROS_POR_VIDEO` (8) cuadros repartidos a lo largo de
  la duración.
- Lo detectado va a `_sensibles/` conservando la subcarpeta de origen, y
  queda registrado en `_sensibles/movimientos.txt` (origen → destino →
  qué detectó y con qué confianza).
- Lo que pasa limpio se renombra con sufijo **`-filtered`** y no se vuelve
  a analizar nunca.
- Freno de emergencia: si el disco se desconecta o hay 25 errores
  consecutivos, corta limpio.

**No es infalible.** Puede haber falsos positivos (playa, gym) y falsos
negativos. La revisión humana del paso 2.5 existe por eso, y conviene
darle una mirada al espejo `-compressed` antes de subirlo.

## Revisión humana (paso 2.5)

Después del filtrado, tu único trabajo manual: mirar `_sensibles/` y mover
lo **realmente** sensible (suelen ser pocos archivos) a
`sensibles-revision-humana/`. Al confirmar, `devolver_sensibles.py`
devuelve todo lo demás (falsos positivos) a su ubicación original,
agregándole `-filtered` para inmunizarlo de futuras corridas. Lo de
`sensibles-revision-humana/` también se marca con `-filtered` y **queda
excluido para siempre de los compresores**: nunca llega a la nube.

## Cómo comprime (pasos 3 y 4)

- Crean la carpeta hermana `<origen>-compressed/` replicando la estructura
  de subcarpetas. Los originales no se tocan.
- Imágenes: calidad 75 (Pillow), HEIC sale convertido a JPG, corrige la
  rotación EXIF (los 8 casos) y preserva la metadata (fecha, GPS, cámara).
  Sufijo: `nombre-compressed-75.ext`.
- Videos: HandBrakeCLI, calidad 26RF (editable: 22 mejor / 28 más chico),
  audio 160 kbps, MOV sale convertido a MP4.
  Sufijo: `nombre-compressed-26RF.mp4`.
- El sufijo `-filtered` del original NO se propaga al espejo: los nombres
  comprimidos quedan estables entre corridas.
- Excluyen `_sensibles/`, `sensibles-revision-humana/` y cualquier carpeta
  `-compressed`.

## Incrementalidad (la propiedad clave)

Todo el pipeline es re-ejecutable sin trabajo duplicado:

- Clasificador: saltea lo ya clasificado
- Filtro: saltea lo `-filtered`
- Compresores: saltean lo que ya existe en el espejo (y ante un corte a
  mitad de un video, el archivo trunco se descarta solo: escriben a nombre
  temporal y renombran recién al terminar)

Podés cortar cualquier paso con Ctrl+C y retomar después. Cuando bajás una
tanda nueva de fotos del iPhone a la misma carpeta, corrés el pipeline y
solo se procesa lo nuevo.

## Consejos operativos

- **Orden estricto**: el filtro nunca en paralelo con los compresores (el
  filtro mueve archivos; los compresores necesitan que nada se mueva).
  El `pipeline.command` garantiza el orden solo.
- **Los dos compresores sí** pueden correr en paralelo entre ellos.
- **No dupliques instancias** del mismo compresor (dos doble clicks =
  choque de archivos temporales).
- Disco externo directo a la Mac, sin hub, para corridas largas.
- El espejo `-compressed` es la copia para la nube; los originales + el
  disco son tu copia maestra. Tené al menos una copia más de la maestra.

## Estructura resultante (ejemplo)

```
Hasta-06-08-2026/                        <- originales, intactos
├── fotos_propias/IMG_0001-filtered.HEIC
├── capturas/IMG_0002-filtered.PNG
├── tiktok/ ...
├── _sensibles/movimientos.txt           <- registro/auditoría
├── sensibles-revision-humana/           <- lo apartado a mano (excluido)
└── *.py + *.command

Hasta-06-08-2026-compressed/             <- para la nube
├── fotos_propias/IMG_0001-compressed-75.jpg
├── capturas/IMG_0002-compressed-75.png
└── tiktok/ ...
```

## Troubleshooting

| Síntoma | Causa | Solución |
|---------|-------|----------|
| `TypeError: 'type' object is not subscriptable` | Python < 3.9 sin el `from __future__` | Actualizá el script o usá Python 3.9+ |
| `pillow-heif` no compila | Python <= 3.8 fuerza compilación | `brew install libheif` o mejor Python 3.12 |
| `UnicodeDecodeError ... 0xb0` | Metadata GPS en Latin-1 | Ya resuelto en los scripts (decodificación tolerante) |
| Miles de `No such file or directory` + `Device not configured` | El disco externo se desconectó | Reconectar, Utilidad de Discos → Primeros Auxilios, re-correr |
| `.command` no abre | Cuarentena de macOS | Click derecho → Abrir (primera vez) o `xattr -d com.apple.quarantine archivo.command` |
| HEIC salteados en el filtro | Falta pillow-heif | `pip3 install pillow-heif` |

## Licencia

Uso personal. Basado en la idea original de
[backup-scripts](https://github.com/yaritaft/backup-scripts).
