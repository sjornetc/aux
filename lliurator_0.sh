#!/usr/bin/env bash
set -euo pipefail

# ===== CONFIG BÀSICA =====
REMOTE_USER="${REMOTE_USER:-u}"
REMOTE_HOST="${REMOTE_HOST:-62.151.14.128}"
# Identificadors de l'activitat (obligats per a l'enviament)
# STUDENT_ID="${STUDENT_ID:-${student_id:-}}"



# ===== PATH LOGS =====
BASEPATH="${BASEPATH:-$HOME/.local/lliurator/}"
BINPATH="$BASEPATH/bin"
ACTIVITY_CODE="$1"
ACTIVITY_PATH="$BASEPATH/$(sed -E "s/_/\//g" <<< "$ACTIVITY_CODE")"
mkdir -p -- "$BASEPATH" "$BINPATH" "$ACTIVITY_PATH"
chmod 700 -- "$BASEPATH" "$BINPATH" "$ACTIVITY_PATH"
umask 077

STAMP="$(date +%Y%m%dT%H%M%S).$$"

SSH_KEY_FILE="${BASEPATH}ssh_key"
STUDENT_ID_FILE="${BASEPATH}student_id"


TS_FILE="$ACTIVITY_PATH/typescript.$STAMP.log"
HIST_FILE="$ACTIVITY_PATH/hist.$STAMP"
TRACE_FILE="$ACTIVITY_PATH/trace.$STAMP.timing"
RC_FILE="$ACTIVITY_PATH/rc.$STAMP"
META_FILE="$ACTIVITY_PATH/.meta.$STAMP"   # guarda context per a retries d'este pack

wget -q -O $BINPATH/lipsumfiles https://raw.githubusercontent.com/sjornetc/aux/main/lipsumfiles_damaged.sh
chmod +x $BINPATH/lipsumfiles

# SSH client opts (no depenen del shell remot)
SSH_OPTS=( -o BatchMode=yes -o ConnectTimeout=12 -o ServerAliveInterval=10 -o ServerAliveCountMax=2 -o StrictHostKeyChecking=accept-new -i $SSH_KEY_FILE )

cat > "$SSH_KEY_FILE" <<'EOF'
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACBOOOLCSoytqSihaVIHG03PwEI2vGjMINzTNzMbBxnsygAAAJhVBxHIVQcR
yAAAAAtzc2gtZWQyNTUxOQAAACBOOOLCSoytqSihaVIHG03PwEI2vGjMINzTNzMbBxnsyg
AAAEBpT7ZBsY12TGipeLkwnuAmgM+fCDWO9mrgK2tPjJwvJU444sJKjK2pKKFpUgcbTc/A
Qja8aMwg3NM3MxsHGezKAAAAFXNqY0BzamMtY3lib3JnMTRhMTN2Zg==
-----END OPENSSH PRIVATE KEY-----
EOF


if [ -f "$STUDENT_ID_FILE" ]; then
    STUDENT_ID=$( cat "$STUDENT_ID_FILE" )
else
    echo "Introdueix l'usuàriï del teu correu itic -el que hi ha abans de l'@-"
    while true; do
        echo -ne "ID ITIC: \033[92m"
        read -r STUDENT_ID
        echo -ne "\033[0m"
        if [[ $STUDENT_ID =~ ^[[:digit:]]{4}_[[:alpha:]]+\.[[:alpha:]]+$ ]]; then
            break
        else
            echo -e "\033[91m\"$STUDENT_ID\"\033[m no és un ID correcte"
            echo -e " ╰─ \033[92m$(date +%Y)_sara.jornet\033[0;9;90m@iticbcn.cat\033[0m"
        fi
    done
    echo -ne "Vols recordar el teu ID per properes vegades? [nY] \033[92m"
    read -rn 1 ans
    case "ans" in
        [nN]) continue ;;
        *) echo $STUDENT_ID > $BASEPATH/student_id ;;
    esac
fi



# ===== rcfile mínim =====
cat >"$RC_FILE" <<RCEND
export PATH="$BINPATH:\$PATH"
PS1='\\033[1;36m\\w\\033[0m $ '
HISTSIZE=20000
HISTFILESIZE=20000
shopt -s histappend
PROMPT_COMMAND='history -a; history -n'
RCEND
printf 'export HISTFILE=%q\n' "$HIST_FILE" | cat - "$RC_FILE" > "$RC_FILE.tmp" && mv -- "$RC_FILE.tmp" "$RC_FILE"

BASH_CMD=(bash --noprofile --rcfile "$RC_FILE" -i)

# ===== meta d'esta execució (per retries futurs) =====
{
  echo "STAMP=$STAMP"
  echo "STUDENT_ID=${STUDENT_ID:-}"
  echo "ACTIVITY_CODE=${ACTIVITY_CODE:-}"
  echo "CREATED_AT=$(date --iso-8601=seconds 2>/dev/null || date)"
} > "$META_FILE"
chmod 600 "$META_FILE"

# ===== helpers =====
build_machine_data() {
  {
    echo "### capture_meta"
    date --iso-8601=seconds 2>/dev/null || date
    echo "user=$(whoami) uid=$(id -u) gid=$(id -g)"
    echo "groups=$(id -nG 2>/dev/null || true)"
    echo "host=$(hostname 2>/dev/null || uname -n)"
    echo "uname=$(uname -a)"
    command -v hostnamectl >/dev/null 2>&1 && hostnamectl 2>/dev/null || true

    echo "### os_release"
    [ -r /etc/os-release ] && cat /etc/os-release || true

    echo "### machine_ids"
    [ -r /etc/machine-id ] && printf 'machine-id=' && cat /etc/machine-id || true
    [ -r /var/lib/dbus/machine-id ] && printf 'dbus-machine-id=' && cat /var/lib/dbus/machine-id || true

    echo "### dmi"
    for f in product_uuid board_serial product_name sys_vendor; do
      p="/sys/class/dmi/id/$f"; [ -r "$p" ] && echo "$f=$(tr -d '\0' < "$p")"
    done

    echo "### cpu/mem/disk"
    [ -r /proc/cpuinfo ] && awk -F: '/model name/{print "cpu=" $2;exit}' /proc/cpuinfo
    [ -r /proc/meminfo ] && awk '/MemTotal/{print "mem_kb=" $2}' /proc/meminfo
    command -v lsblk >/dev/null 2>&1 && lsblk -o NAME,SERIAL,UUID,TYPE,MOUNTPOINT -J 2>/dev/null || true
    command -v blkid  >/dev/null 2>&1 && blkid 2>/dev/null || true

    echo "### net"
    command -v ip >/dev/null 2>&1 && {
      ip -brief addr 2>/dev/null || true
      ip route 2>/dev/null || true
      for n in /sys/class/net/*; do
        [ -d "$n" ] || continue
        name=$(basename "$n")
        [ -r "$n/address" ] && echo "mac_$name=$(cat "$n/address")"
      done
    }

    echo "### env_min"
    echo "SHELL=$SHELL"
    echo "HOME=$HOME"
    echo "LANG=$LANG"
    echo "TERM=$TERM"

    echo "### basepath"
    echo "BASEPATH=$BASEPATH"
  } | sed -e 's/[ \t]*$//'
}

# extrau STAMP d’un filename conegut
extract_stamp() {
  # ex: typescript.20251104T011714.1234.log  -> 20251104T011714.1234
  #     hist.20251104T011714.1234           -> 20251104T011714.1234
  #     trace.20251104T011714.1234.timing   -> 20251104T011714.1234
  basename -- "$1" \
  | sed -E 's/^typescript\.([^.]+)\.log$/\1/; s/^hist\.([^.]+)$/\1/; s/^trace\.([^.]+)\.timing$/\1/'
}

load_meta_for() {
  # carrega STUDENT_ID/ACTIVITY_CODE a partir del .meta per a un STAMP
  local stamp="$1" mf="$BASEPATH/.meta.$stamp"
  if [ -r "$mf" ]; then
    # shellcheck disable=SC1090
    . "$mf"
    # exporta variables locals cap a fora
    META_STUDENT_ID="${STUDENT_ID:-}"
    META_ACTIVITY_CODE="${ACTIVITY_CODE:-}"
  else
    META_STUDENT_ID="${STUDENT_ID:-${STUDENT_ID:-}}"
    META_ACTIVITY_CODE="${ACTIVITY_CODE:-${ACTIVITY_CODE:-}}"
  fi
}

send_with_proto() {
  # stdin -> ssh u@host $student_id <label> $activity_code
  local sid="$1" label="$2" acode="$3"
  ssh "${SSH_OPTS[@]}" "$REMOTE_USER@$REMOTE_HOST" "$sid" "$label" "$acode"
}

try_send_file() {
  # $1=filepath ; $2=label (data/ts/hist/hist_per_trace)
  local f="$1" label="$2"
  [ -f "$f" ] || return 0
  local stamp; stamp="$(extract_stamp "$f")"
  load_meta_for "$stamp"
  local sid="${META_STUDENT_ID:-}"; local ac="${META_ACTIVITY_CODE:-}"
  if [ -z "$sid" ] || [ -z "$ac" ]; then
    echo "⚠️  Sense STUDENT_ID/ACTIVITY_CODE per $f — deixant per retry."
    return 1
  fi
  if send_with_proto "$sid" "$label" "$ac" < "$f"; then
    rm -f -- "$f"
    echo "✔ enviat i esborrat: $(basename "$f")"
    # esborra meta si ja no queda cap fitxer d’eixe STAMP
    if ! ls "$BASEPATH"/{typescript."$stamp".log,hist."$stamp",trace."$stamp".timing} >/dev/null 2>&1; then
      rm -f -- "$BASEPATH/.meta.$stamp" 2>/dev/null || true
    fi
    return 0
  else
    echo "✖ fallo enviant: $(basename "$f")"
    return 1
  fi
}

retry_pending() {
  echo "Reintentant pendents..."
  local any_fail=0
  # ordre coherent amb el teu protocol
  for f in "$BASEPATH"/hist.* "$BASEPATH"/typescript.*.log "$BASEPATH"/trace.*.timing; do
    [ -e "$f" ] || continue
    case "$f" in
      *hist.*)              try_send_file "$f" "hist" || any_fail=1 ;;
      *typescript.*.log)    try_send_file "$f" "ts"   || any_fail=1 ;;
      *trace.*.timing)      try_send_file "$f" "hist" || any_fail=1 ;;  # <-- tal com has indicat
    esac
  done
  return "$any_fail"
}

send_this_run() {
  local fail=0

  # 1) data (fingerprint) — usa meta d’esta execució
  if [ -n "${STUDENT_ID:-}" ] && [ -n "${ACTIVITY_CODE:-}" ]; then
    local data; data="$(build_machine_data)"
    if printf '%s' "$data" | send_with_proto "$STUDENT_ID" "data" "$ACTIVITY_CODE"; then
      echo "✔ data enviat"
    else
      echo "✖ data no enviat (es tornarà a provar a pròx execució)"
      fail=1
    fi
  else
    echo "⚠️  STUDENT_ID/ACTIVITY_CODE no definits — saltant data i fitxers d’esta execució (quedaran per retry)."
    return 1
  fi

  # 2) fitxers d’esta execució (amb el mateix STAMP)
  try_send_file "$HIST_FILE"  "hist" || fail=1
  try_send_file "$TS_FILE"    "ts"   || fail=1
  try_send_file "$TRACE_FILE" "hist" || fail=1  # <-- label 'hist' per al trace, segons el teu format

  return "$fail"
}

# ===== finalize: s'executa quan tanques la sessió =====
finalize() {
  set +e
  echo
  echo "Finalitzant: enviament per ssh + retries..."

  # intenta enviar el pack d’esta execució
  send_this_run

  # reintenta pendents anteriors
  retry_pending

  echo "✓ done. Si queda res pendent, romandrà a $BASEPATH i es provarà pròxima vegada."
}

trap finalize EXIT

# ===== llança sessió registrada amb `script` =====
HELP="$(script --help 2>&1 || true)"
if printf '%s' "$HELP" | grep -q -- '\-c'; then
  if printf '%s' "$HELP" | grep -q -- '\-t'; then
    script -q -f -t 2>"$TRACE_FILE" -c "${BASH_CMD[*]}" "$TS_FILE"
  else
    script -q -f -c "${BASH_CMD[*]}" "$TS_FILE"
  fi
else
  if printf '%s' "$HELP" | grep -q -- '\-t'; then
    script -q -f -t 2>"$TRACE_FILE" "$TS_FILE" -- "${BASH_CMD[@]}"
  else
    script -q -f "$TS_FILE" -- "${BASH_CMD[@]}"
  fi
fi
