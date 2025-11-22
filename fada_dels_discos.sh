#!/bin/bash

# fadaDiscos.sh — la fada dels discos crea contenidors màgics per als teus bits 🧚‍♀️

set -euo pipefail

SIZE="100M"
EXT=".disk"
QUIET=0
INTERACTIVE=0
NO_CLOBBER=0

usage() {
    local prog
    prog="$(basename "$0")"

    case "${LANG:-en}" in
        ca* )
            cat <<EOF
Forma d'ús: $prog [OPCIÓ]… FITXER…

Crea un «disc» (fitxer dispers) per a cada FITXER indicat.

Els arguments obligatoris per a les opcions llargues també ho són per a les
opcions curtes corresponents.

  -s, --size=MIDA        Estableix la mida lògica del disc (ex: 1G, 200M, 128k, 0.5G, 100)
                         Si la mida no porta unitat, s'assumeix megabytes (M).

  -i, --interactive      Pregunta abans de sobreescriure un disc existent.
  -n, --no-clobber       No sobreescriu cap disc existent (salta'ls en silenci);
                         inhabilita una opció «-i» anterior.
  -q, --quiet            No mostra missatges informatius (només errors).
      --help             Mostra aquesta ajuda i surt.

Notes:
  - Si el FITXER no té extensió, s'hi afegeix «$EXT» per defecte.
  - Els discos creats són «dispersos» (sparse): tenen la mida indicada,
    però només ocupen espai real quan s'hi escriuen dades.
EOF
            ;;
        * )
            cat <<EOF
Usage: $prog [OPTION]... FILE...

Create a "disk" (sparse file) for each given FILE.

Mandatory arguments to long options are mandatory for the corresponding
short options as well.

  -s, --size=SIZE        Set the logical size of the disk (e.g. 1G, 200M, 128k, 0.5G, 100)
                         If SIZE has no unit, megabytes (M) are assumed.

  -i, --interactive      Prompt before overwriting an existing disk.
  -n, --no-clobber       Do not overwrite any existing disk (skip silently);
                         disables a previous -i option.
  -q, --quiet            Do not print informational messages (only errors).
      --help             Display this help and exit.

Notes:
  - If FILE has no extension, "$EXT" is appended by default.
  - Disks are created as sparse files: they report the requested size,
    but only consume real space as data is written.
EOF
            ;;
    esac
    exit 0
}

add_ext_if_needed() {
    local f="$1"
    if [[ "$f" == *.* ]]; then
        echo "$f"
    else
        echo "${f}${EXT}"
    fi
}

# Si no hi ha unitat, assumim M (megabytes)
normalize_size() {
    local v="$1"
    if [[ "$v" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "${v}M"
    else
        echo "$v"
    fi
}

# Preprocess: convertir opcions llargues a curtes per getopts
LONG_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)
            LONG_ARGS+=("-h")
            shift
            ;;
        --size)
            if [[ $# -lt 2 ]]; then
                echo "Error: falta valor per --size / --size requires an argument" >&2
                exit 1
            fi
            LONG_ARGS+=("-s" "$2")
            shift 2
            ;;
        --quiet)
            LONG_ARGS+=("-q")
            shift
            ;;
        --interactive)
            LONG_ARGS+=("-i")
            shift
            ;;
        --no-clobber)
            LONG_ARGS+=("-n")
            shift
            ;;
        --)
            shift
            while [[ $# -gt 0 ]]; do
                LONG_ARGS+=("$1")
                shift
            done
            break
            ;;
        --*)
            echo "Opció desconeguda / unknown option: $1" >&2
            exit 1
            ;;
        *)
            LONG_ARGS+=("$1")
            shift
            ;;
    esac
done

set -- "${LONG_ARGS[@]}"

# Flags curts (agrupables)
while getopts ":hqs:in" opt; do
    case "$opt" in
        h)
            usage
            ;;
        q)
            QUIET=1
            ;;
        s)
            SIZE="$OPTARG"
            ;;
        i)
            INTERACTIVE=1
            NO_CLOBBER=0   # com cp: -i inhabilita -n anterior
            ;;
        n)
            NO_CLOBBER=1
            INTERACTIVE=0  # com cp: -n sobreescriu un -i anterior
            ;;
        \?)
            echo "Opció desconeguda / unknown option: -$OPTARG" >&2
            exit 1
            ;;
        :)
            echo "L'opció -$OPTARG requereix un valor / option -$OPTARG requires an argument." >&2
            exit 1
            ;;
    esac
done

shift $((OPTIND - 1))

if [[ $# -lt 1 ]]; then
    echo "Error: cal especificar almenys un FITXER / missing FILE operand." >&2
    echo "Try '$0 --help' for more information." >&2
    exit 1
fi

NSIZE=$(normalize_size "$SIZE")

for OUT in "$@"; do
    FILE=$(add_ext_if_needed "$OUT")

    if [[ -e "$FILE" ]]; then
        # --no-clobber: salta silenciosament
        if [[ $NO_CLOBBER -eq 1 ]]; then
            if [[ $QUIET -eq 0 ]]; then
                case "${LANG:-en}" in
                    ca* )
                        echo "fadaDiscos: no s'ha sobreescrit «$FILE» (--no-clobber)."
                        ;;
                    * )
                        echo "fadaDiscos: not overwriting '$FILE' (--no-clobber)."
                        ;;
                esac
            fi
            continue
        fi

        # --interactive: preguntar abans de sobreescriure
        if [[ $INTERACTIVE -eq 1 ]]; then
            case "${LANG:-en}" in
                ca* )
                    printf "fadaDiscos: la fada pot sobreescriure el disc existent «%s»? [y/N] " "$FILE" >&2
                    ;;
                * )
                    printf "fadaDiscos: overwrite existing disk '%s'? [y/N] " "$FILE" >&2
                    ;;
            esac
            read -r answer
            case "$answer" in
                [yY])
                    # segueix i sobreescriu
                    ;;
                *)
                    if [[ $QUIET -eq 0 ]]; then
                        case "${LANG:-en}" in
                            ca* )
                                echo "fadaDiscos: s'ha mantingut el disc existent «$FILE»."
                                ;;
                            * )
                                echo "fadaDiscos: kept existing disk '$FILE'."
                                ;;
                        esac
                    fi
                    continue
                    ;;
            esac
        fi
    fi

    truncate -s "$NSIZE" "$FILE"

    if [[ $QUIET -eq 0 ]]; then
        case "${LANG:-en}" in
            ca* )
                echo "🧚‍♀️ fadaDiscos: creat disc «$FILE» de mida $NSIZE (fitxer dispers)."
                ;;
            * )
                echo "🧚‍♀️ fadaDiscos: created disk '$FILE' with size $NSIZE (sparse file)."
                ;;
        esac
    fi
done
