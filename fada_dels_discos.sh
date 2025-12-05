
#!/bin/bash
# fada_dels_discos.sh — la fada que dona vida a discos virtuals (.disk -> /dev/loopX)
#
# Create or reuse sparse virtual disk files and attach them to loop devices.
#
# First created in 2023. Current version updated in 2025.
#
# Version: 2.2.0
# Author:  Sara Jornet Calomarde <sjcedu@mp.me>
# License: GPLv3 or later
#
# This script follows a simple Unix philosophy:
#  - If NAME or NAME.disk does not exist -> create it as a sparse file
#  - Then attach it to a loop device and print the loop path on stdout
#  - Logs and messages go to stderr (unless -q)

set -euo pipefail

PROGNAME="fada_dels_discos.sh"
VERSION="2.2.1"
AUTHOR_NAME="Sara Jornet Calomarde"
AUTHOR_EMAIL="sjornet2@xtec.cat"
LICENSE_SHORT="GPLv3 or later"

# Defaults
SIZE="1G"
SIZE_EXPLICIT=0
QUIET=0


###############################################################################
# Utils
###############################################################################

log() {
    [[ $QUIET -eq 0 ]] || return 0

    if [[ "$1" == "-n" ]]; then
        shift
        echo -en "🧚‍♀️ $*" >&2
        return 0
    fi

    echo -e "🧚‍♀️ $*" >&2
}

log_error() {
    echo -e "fadaDiscos: $*" >&2
}

prog_name() {
    basename "$0"
}


###############################################################################
# Help (CA + EN)
###############################################################################

usage() {
    local prog
    prog="$(prog_name)"

    case "${LANG:-en}" in
        ca* ) show_help_ca "$prog" ;;
        *   ) show_help_en "$prog" ;;
    esac
    exit 0
}

show_help_ca() {
    local prog="$1"
    cat <<EOF
Forma d'ús: $prog [OPCIÓ]… NOM_DISC…

La fada dona vida a cada NOM_DISC: si no existeix, el crea com a fitxer dispers
(.disk) i després el lliga a un dispositiu loop. El camí del loop resultant
s'escriu a la sortida estàndard, un per línia.

Opcions:
  -s, --size=MIDA      Mida del disc si s'ha de crear (ex: 1G, 200M, 128k, 0.5G, 100).
                       Si la mida no porta unitat, s'assumeix M.
                       Si el disc ja existeix i uses -s, donarà un error: cal
                       esborrar manualment el .disk per recrear-lo.
  -q, --quiet          Silencia els missatges informatius (stderr).
                       stdout només conté els dispositius loop.
      --help           Mostra aquesta ajuda i ix.
      --version        Mostra informació de versió i ix.

Exemples:
  $prog unicorn
      Dona vida a «unicorn»; si no existeix, el crea com «unicorn.disk».

  sudo mount "\$($prog -q unicorn)" /mnt/unicorn
      Silencia logs i munta directament el loop retornat.

Written by $AUTHOR_NAME <$AUTHOR_EMAIL>.
License $LICENSE_SHORT.
Report bugs to <$AUTHOR_EMAIL>.
EOF
}

show_help_en() {
    local prog="$1"
    cat <<EOF
Usage: $prog [OPTION]... DISK_NAME...

For each DISK_NAME, the fairy ensures there is a sparse virtual disk file
(DISK_NAME or DISK_NAME.disk) and then attaches it to a loop device. The resulting
loop device path is written to standard output, one per line.

Options:
  -s, --size=SIZE      Disk size when creating a new virtual disk
                       (e.g. 1G, 200M, 128k, 0.5G, 100).
                       If SIZE has no unit, megabytes (M) are assumed.
                       If the disk file already exists and -s is given, this
                       is an error: remove the .disk file manually to recreate it.
  -q, --quiet          Do not print informational messages (stderr); stdout
                       will only contain loop device paths.
      --help           Display this help and exit.
      --version        Output version information and exit.

Examples:
  $prog unicorn
      Give life to “unicorn”: if it does not exist, create “unicorn.disk”.

  sudo mount "\$($prog -q unicorn)" /mnt/unicorn
      Silence logs and directly mount the returned loop device.

Written by $AUTHOR_NAME <$AUTHOR_EMAIL>.
License $LICENSE_SHORT.
Report bugs to <$AUTHOR_EMAIL>.
EOF
}


###############################################################################
# Version
###############################################################################

show_version() {
    cat <<EOF
$PROGNAME $VERSION
Copyright (C) 2025 $AUTHOR_NAME
License $LICENSE_SHORT <https://www.gnu.org/licenses/gpl-3.0.html>.
Written by $AUTHOR_NAME <$AUTHOR_EMAIL>.
EOF
    exit 0
}


###############################################################################
# Option parsing
###############################################################################

LONG_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)    LONG_ARGS+=("-h"); shift ;;
        --version) LONG_ARGS+=("-v"); shift ;;
        --size)
            [[ $# -lt 2 ]] && { log_error "--size requereix un valor"; exit 1; }
            LONG_ARGS+=("-s" "$2"); shift 2 ;;
        --quiet)   LONG_ARGS+=("-q"); shift ;;
        --*)
            log_error "Opció desconeguda: $1"
            exit 1
            ;;
        *)
            LONG_ARGS+=("$1"); shift ;;
    esac
done

set -- "${LONG_ARGS[@]:-}"

while getopts ":hvqs:" opt; do
    case "$opt" in
        h) usage ;;
        v) show_version ;;
        q) QUIET=1 ;;
        s) SIZE="$OPTARG"; SIZE_EXPLICIT=1 ;;
        :)
            log_error "L'opció -$OPTARG requereix un valor"
            exit 1
            ;;
        \?)
            log_error "Opció desconeguda: -$OPTARG"
            exit 1
            ;;
    esac
done

shift $((OPTIND - 1))

#
# echo $@
# # Handle --version explicitly
# for arg in "$@"; do
#     if [[ "$arg" == "--version" ]]; then
#         show_version
#     fi
# done

# Must have at least one operand
if [[ $# -lt 1 ]]; then
    log_error "Falta al menys un NOM_DISC.\nTry '$PROGNAME --help' for more information."
    exit 1
fi


###############################################################################
# Main loop
###############################################################################

EXIT_STATUS=0

for RAW in "$@"; do
    # Determine actual file: NAME or NAME.disk
    FILE=""
    if [[ -e "$RAW" ]]; then
        FILE="$RAW"
        EXISTS=1
    elif [[ -e "${RAW}.disk" ]]; then
        FILE="${RAW}.disk"
        EXISTS=1
    else
        FILE="${RAW}.disk"
        EXISTS=0
    fi

    # If exists + size explicit -> error
    if [[ $EXISTS -eq 1 && $SIZE_EXPLICIT -eq 1 ]]; then
        log_error "El disc «$FILE» ja existeix i no puc usar -s per canviar-li la mida.\nEsborra manualment el fitxer .disk per recrear-lo."
        EXIT_STATUS=1
        continue
    fi

    # If not exists -> create sparse file
    if [[ $EXISTS -eq 0 ]]; then
        truncate -s "$SIZE" "$FILE"
        log "Creat l'arxiu «$FILE» (mida $SIZE)"
    else
        log "Disc «$FILE» ja existeix; creant loop."
    fi

    # Give life -> losetup
    loopdev=$(losetup -fP --show "$FILE")
    log -n "Loop creat! $FILE -> "
    echo "$loopdev"
done

exit "$EXIT_STATUS"
