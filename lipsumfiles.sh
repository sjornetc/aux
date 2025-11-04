#!/usr/bin/env bash

set -euo pipefail

VERSION="1.0.0"

###########
## utils ##
###########
msg() { printf "%s\n" "$*"; }
err() { printf "error: %s\n" "$*" >&2; }
die() { err "$*"; exit 1; }

# Logging levels: quiet (-q) suppresses non-errors; verbose (-v) lists each file
QUIET=0
VERBOSE=0
OVERWRITE=0

log_info() { (( QUIET )) || msg "$*"; }
log_verbose() { (( VERBOSE )) && msg "$*"; }

# Safe mkdir -p with errors surfaced
mkoutdir() {
  local d="$1"
  if [[ -e "$d" && ! -d "$d" ]]; then
    die "el destí '$d' existeix però no és un directori"
  fi
  mkdir -p -- "$d"
}

# Write a file respecting overwrite flag
write_file() {
  local path="$1" content="${2:-}"
  if [[ -e "$path" && $OVERWRITE -eq 0 ]]; then
    log_info "saltant (ja existeix): $path"
    return 0
  fi
  # ensure parent exists
  mkdir -p -- "$(dirname -- "$path")"
  printf "%s" "$content" > "$path"
#   log_verbose "$path"
}

next_path() {
  local path="$1"

  # Si no existeix res amb aquest nom, el tornem tal qual
  [[ -e "$path" ]] || { echo "$path"; return; }

  # Si acaba amb "_<número>", incrementa’l
  if [[ "$path" =~ ^(.+)_([0-9]+)$ ]]; then
    local base="${BASH_REMATCH[1]}"
    local num="${BASH_REMATCH[2]}"
    echo "${base}_$((num + 1))"
  else
    # Si no acaba amb número, comença pel _0
    echo "${path}_0"
  fi
}

##########
## help ##
##########
print_help() {
cat <<'EOF'
Forma d’ús: lipsumfiles [OPCIÓ]... [DESTÍ]

Genera conjunts de fitxers amb contingut fictici per practicar amb el sistema
de fitxers, redireccions i pipes. El DESTÍ és el directori on es guardaran els
fitxers (per defecte, el directori actual).

Opcions generals:
  -c NUM               Quantitat de fitxers a generar (per defecte: 1)
                       Incompatible amb -D.
  -r                   Sobreescriu fitxers existents sense demanar confirmació.
  -q                   Mode silenciós (només errors).
  -v                   Mode verbós (mostra cada fitxer creat).
  -V, --version        Mostra la versió i surt.
  -h, --help           Mostra aquesta ajuda i surt.

Tipus de fitxers (mútuament excloents):
  -E NOM               Genera fitxers buits (NOM_#.EXT)
      -x EXT           Extensió dels arxius (per defecte: txt)

  -B NOM               Genera llibres (NOM_#.FMT) amb text "lorem ipsum"
      -f txt|md        Format de sortida (per defecte: txt)
      -n N             Nombre de capítols (per defecte: 8)

  -C NOM               Genera catàlegs (NOM_#.EXT) amb línies "<article><sep><categoria><sep><quantitat>"
      -x EXT           Extensió de sortida (per defecte: txt)
      -s SEP           Separador de cel·les (per defecte: ",")
      -n N             Nombre d’articles per fitxer (per defecte: 8)

  -D NOM               Genera fitxers datats (NOM_YY-MM.EXT)
                       Ignora -c.
      -x EXT           Extensió de sortida (per defecte: txt)
      -s YY/MM         Data d’inici (per defecte: 00/01)
      -e YY/MM         Data de fi (per defecte: mes actual)

  -U NOM               Genera fitxers d’usuaris (NOM_#.EXT)
                       Cada línia té el format "<id><sep><nom><sep><cognoms><sep><naixement>".
      -x EXT           Extensió de sortida (per defecte: txt)
      -s SEP           Separador de cel·les (per defecte: ":")
      -n N             Registres per fitxer (per defecte: 128)

  -O CATEGORIA         Genera fitxers d’objectes sense extensió.
                       Categories disponibles:
                         roba, inst_musicals, plantes, vaixella,
                         coberts, menjar, begudes, papereria

Exemples:
  lipsumfiles -E llibre -x md
  lipsumfiles -E llibre -x md -c 3
  lipsumfiles -E arxiu -c 5
  lipsumfiles -C revista -c 6 -n 10
  lipsumfiles -D factura -s 24/01 -e 25/06 -x bll
  lipsumfiles -O coberts -n 12
EOF
}

######################
## defaults / state ##
######################
DEST="."
declare -i COUNT=1

TYPE=""      # E|B|C|D|U|O
NAME=""
EXT="txt"
FMT="txt"
NVAL=""
SEP=""       # separator for -C/-U
START=""     # start date for -D (YY/MM)
END=""
CATEGORY=""

################
## parse argv ##
################
# manual long options & getopts combo
LONG=""
while (( $# )); do
  case "$1" in
    --help) print_help; exit 0 ;;
    --version) msg "$VERSION"; exit 0 ;;
    --) shift; break ;;
    -h|-V) LONG+=" $1"; shift ;;
    *) break ;;
  esac
done

OPTIND=1
while getopts ":c:rqvE:B:C:D:U:O:x:f:n:s:e:hV" opt; do
  case "$opt" in
    c) COUNT="$OPTARG" ;;
    r) OVERWRITE=1 ;;
    q) QUIET=1 ;;
    v) VERBOSE=1 ;;
    V) msg "$VERSION"; exit 0 ;;
    h) print_help; exit 0 ;;
    E) TYPE="E"; NAME="$OPTARG" ;;
    B) TYPE="B"; NAME="$OPTARG" ;;
    C) TYPE="C"; NAME="$OPTARG" ;;
    D) TYPE="D"; NAME="$OPTARG" ;;
    U) TYPE="U"; NAME="$OPTARG" ;;
    O) TYPE="O"; CATEGORY="$OPTARG" ;;
    x) EXT="$OPTARG" ;;
    f) FMT="$OPTARG" ;;
    n) NVAL="$OPTARG" ;;
    s)
      # si és -D, és START; si és -C/-U, és SEP
      case "$TYPE" in
        D) START="$OPTARG" ;;
        C|U) SEP="$OPTARG" ;;
        *) SEP="$OPTARG" ;; # fallback per quan l'ordre d’opcions varia
      esac
      ;;
    e) END="$OPTARG" ;;
    \?) die "opció invàlida: -$OPTARG (mira -h)" ;;
    :) die "l'opció -$OPTARG requereix un valor" ;;
  esac
done
shift $((OPTIND-1))

# Remaining arg is destination (optional)
if (( $# > 0 )); then DEST="$1"; fi

#################
## validations ##
#################
[[ -n "$TYPE" ]] || die "has d'indicar un tipus (-E|-B|-C|-D|-U|-O)"
[[ -n "$NAME" || "$TYPE" == "O" ]] || die "has de donar un nom base per al tipus seleccionat"

# -c incompatible amb -D
if [[ "$TYPE" == "D" && "$COUNT" != "1" ]]; then
  die "-c és incompatible amb -D (la quantitat es determina pel rang de dates)"
fi

# format & ext checks
if [[ "$TYPE" == "B" ]]; then
  case "$FMT" in txt|md) :;; *) die "format no vàlid per -B: $FMT (usa txt|md)";; esac
fi

# N defaults per tipus
case "$TYPE" in
  B) : "${NVAL:=8}" ;;
  C) : "${NVAL:=8}"; : "${SEP:=","}" ;;
  U) : "${NVAL:=32}"; : "${SEP:=":"}" ;;
esac

# D defaults (dates YY/MM)
current_yy_mm="$(date +%y)/$(date +%m)"
if [[ "$TYPE" == "D" ]]; then
  : "${START:=00/01}"
  : "${END:=$current_yy_mm}"
  : "${EXT:=txt}"
fi

mkoutdir "$DEST"

################
## generators ##
################

lipsum_sentence() {
  local wcount="${1:-0}"
  if (( wcount <= 0 )); then
    wcount=$((6 + RANDOM % 10))
  fi
  local sentence=""
  for ((i=0; i<wcount; i++)); do
    local word="${lipsum_words[RANDOM % ${#lipsum_words[@]}]}"
    sentence+="$word "
  done
  sentence="$(tr '[:lower:]' '[:upper:]' <<< "${sentence:0:1}")${sentence:1:-1}"
  echo "${sentence}."
}


lipsum_paragraph() {
  local fcount=$((3 + RANDOM % 5))
  local p=""
  for ((i=0; i<fcount; i++)); do
    p+="$(lipsum_sentence) "
  done
  echo "${p::-1}"
}

# iterate months inclusive between YY/MM .. YY/MM
iter_months() {
  local start="$1" end="$2"
  [[ "$start" =~ ^([0-9]{2})/([0-9]{2})$ ]] || die "format de data d'inici no vàlid (YY/MM): $start"
  [[ "$end" =~ ^([0-9]{2})/([0-9]{2})$ ]] || die "format de data de fi no vàlid (YY/MM): $end"
  local sy=${BASH_REMATCH[1]} sm=${BASH_REMATCH[2]}
  [[ "$end" =~ ^([0-9]{2})/([0-9]{2})$ ]]
  local ey=${BASH_REMATCH[1]} em=${BASH_REMATCH[2]}

  local s=$((10#$sy * 12 + 10#$sm))
  local e=$((10#$ey * 12 + 10#$em))
  (( s<=e )) || die "rang de dates invertit ($start..$end)"

  local i
  for (( i=s; i<=e; ++i )); do
    local y=$(( i/12 ))
    local m=$(( i%12 ))
    (( m==0 )) && { m=12; y=$(( y-1 )); }
    printf "%02d-%02d\n" "$y" "$m"
  done
}

rand_in() { # rand_in item1 item2 ...
  local items=("$@")
  local idx=$(( RANDOM % ${#items[@]} ))
  printf "%s" "${items[$idx]}"
}

# Data pools
articles=(revista llibre poster fullet targeta guia cataleg llista quadern bloc etiqueta)
categories=(A B C premium eco basic pro)
obj_roba=(samarreta dessuadora pantalons jaqueta mitjons barret bufanda faldilla vestit)
obj_inst_musicals=(violi guitarra baix bateria piano flauta saxo clarinet)
obj_plantes=(aloe cactus ficus falguera suculenta monstera ficus_elastica pothos)
obj_vaixella=(plat got tassa bol safata)
obj_coberts=(ganivet forquilla cullera cullereta cullera_de_postres cullera_de_cafe)
obj_menjar=(poma pera pa arròs pasta galeta sopa)
obj_begudes=(aigua te cafe suc refresc)
obj_papereria=(llapis bolígraf retolador llibreta carpeta goma tisores)

lipsum_words=(
  "a" "ac" "accumsan" "ad" "adipiscing" "aenean"
  "aliquam" "aliquet" "amet" "ante" "aptent" "arcu"
  "at" "auctor" "augue" "bibendum" "blandit" "class"
  "commodo" "condimentum" "congue" "consectetur" "consequat" "conubia"
  "convallis" "cras" "cubilia" "curabitur" "curae" "cursus"
  "dapibus" "diam" "dictum" "dictumst" "dignissim" "dis"
  "dolor" "donec" "dui" "duis" "efficitur" "egestas"
  "eget" "eleifend" "elementum" "elit" "enim" "erat"
  "eros" "est" "et" "etiam" "eu" "euismod"
  "ex" "facilisi" "facilisis" "fames" "faucibus" "felis"
  "fermentum" "feugiat" "finibus" "fringilla" "fusce" "gravida"
  "habitant" "habitasse" "hac" "hendrerit" "himenaeos" "iaculis"
  "id" "imperdiet" "in" "inceptos" "integer" "interdum"
  "ipsum" "justo" "lacinia" "lacus" "laoreet" "lectus"
  "leo" "libero" "ligula" "litora" "lobortis" "lorem"
  "luctus" "maecenas" "magna" "magnis" "malesuada" "massa"
  "mattis" "mauris" "maximus" "metus" "mi" "molestie"
  "mollis" "montes" "morbi" "mus" "nam" "nascetur"
  "natoque" "nec" "neque" "netus" "nibh" "nisi"
  "nisl" "non" "nostra" "nulla" "nullam" "nunc"
  "odio" "orci" "ornare" "parturient" "pellentesque" "penatibus"
  "per" "pharetra" "phasellus" "placerat" "platea" "porta"
  "porttitor" "posuere" "potenti" "praesent" "pretium" "primis"
  "proin" "pulvinar" "purus" "quam" "quis" "quisque"
  "rhoncus" "ridiculus" "risus" "rutrum" "sagittis" "sapien"
  "scelerisque" "sed" "sem" "semper" "senectus" "sit"
  "sociosqu" "sodales" "sollicitudin" "suscipit" "suspendisse" "taciti"
  "tellus" "tempor" "tempus" "tincidunt" "torquent" "tortor"
  "tristique" "turpis" "ullamcorper" "ultrices" "ultricies" "urna"
  "ut" "varius" "vehicula" "vel" "velit" "venenatis"
  "vestibulum" "vitae" "vivamus" "viverra" "volutpat" "vulputate"
)


lipsum_names=(
  "aaron" "abdelaziz" "abdelkader" "abdellah" "abdul" "abdullah"
  "abel" "abigail" "abraham" "abril" "ada" "adam" "adela" "adelaida"
  "adelina" "adil" "adnan" "adolfo" "adoracion" "adria" "adrian"
  "adriana" "adriano" "africa" "agata" "agnes" "agueda" "agusti"
  "agustin" "agustina" "ahmad" "ahmed" "aicha" "aida" "aina" "ainara"
  "ainhoa" "ainoa" "aitana" "aitor" "alan" "alba" "albert" "alberto"
  "aleix" "alejandra" "alejandro" "alejandro jose" "alejo" "aleksandr"
  "aleksandra" "aleksei" "alessandra" "alessandro" "alessia" "alessio"
  "alex" "alexander" "alexandra" "alexandre" "alexia" "alexis"
  "alfons" "alfonso" "alfred" "alfredo" "ali" "alice" "alicia"
  "alina" "alisa" "alma" "almudena" "alonso" "alvaro" "amadeo"
  "amador" "amaia" "amalia" "amanda" "amelia" "amina" "amir"
  "amparo" "ana" "ana belen" "ana carolina" "ana cristina"
  "ana isabel" "ana lucia" "ana maria" "ana paula" "ana rosa"
  "anabel" "anais" "anas" "anastasia" "ander" "andre" "andrea"
  "andres" "andres felipe" "andreu" "angel" "angel luis" "angela"
  "angeles" "angelica" "angelina" "angelo" "angels" "anna"
  "anton" "antonella" "antoni" "antonia" "antonio" "antonio jose"
  "araceli" "aran" "arantxa" "ariadna" "ariana" "arnau" "aroa"
  "artur" "arturo" "asier" "astrid" "augusto" "aurora" "axel" "aya"
  "ayoub" "barbara" "beatriz" "belen" "benjamin" "bernardo"
  "berta" "bianca" "biel" "blai" "blanca" "borja" "bruna" "bruno"
  "camila" "candela" "carla" "carles" "carlos" "carmen" "carolina"
  "catalina" "cecilia" "celia" "cesar" "chiara" "chloe" "christian"
  "clara" "claudia" "cristian" "cristina" "daniel" "daniela"
  "dario" "david" "diana" "didac" "diego" "dolors" "dunia" "dylan"
  "eduard" "eduardo" "elena" "elias" "elisa" "elisabet" "eloi"
  "elsa" "emili" "emilia" "emilio" "emma" "enric" "enrique"
  "eric" "erik" "ernest" "estel" "estela" "ester" "eva"
  "fabio" "fabiola" "fatima" "felipe" "fernando" "ferran" "flavia"
  "francesc" "francisca" "francisco" "gabriel" "gabriela" "gael"
  "gala" "gema" "gemma" "genis" "gerard" "german" "giovanni"
  "gisela" "gloria" "gonzalo" "gorka" "greta" "guillermo" "gustavo"
  "hector" "helena" "hugo" "ian" "ignasi" "iker" "ines" "irene"
  "isaac" "isabel" "ismael" "ivan" "ivette" "izan" "jaime"
  "jan" "jana" "jaume" "javier" "jesus" "joan" "joana" "joaquim"
  "joaquin" "joel" "jofre" "jon" "jordina" "jordi" "jorge" "jose"
  "josep" "juan" "julia" "julian" "julieta" "julio" "karim" "kevin"
  "laia" "lara" "laura" "leire" "leo" "leonardo" "lia" "lluc"
  "lluis" "lola" "lorena" "lourdes" "luca" "lucas" "lucia" "luis"
  "luisa" "luna" "macarena" "maria" "maria jose" "marc" "marcel"
  "marcela" "marco" "margarita" "marina" "mario" "mariona" "marta"
  "marti" "martina" "mateo" "matias" "mauro" "max" "melissa"
  "merce" "meritxell" "mia" "miguel" "miquel" "mireia" "miriam"
  "mohamed" "monica" "montserrat" "nabil" "nadia" "naia" "natalia"
  "nerea" "neus" "nico" "nicolas" "nil" "nina" "noa" "noah" "noel"
  "noelia" "nora" "nuria" "olga" "olivia" "omar" "ona" "oriol"
  "oscar" "pablo" "paola" "patricia" "pau" "paula" "pedro"
  "pere" "pilar" "pol" "rafael" "raquel" "raul" "rebeca"
  "ricard" "ricardo" "rita" "robert" "roberto" "rocio" "roger"
  "rosa" "roser" "ruben" "ruth" "sabrina" "salma" "samuel"
  "sandra" "sara" "saul" "sebastia" "sergi" "sergio" "silvia"
  "sofia" "sonia" "susana" "tamara" "tania" "teo" "teresa"
  "thomas" "tomas" "toni" "unai" "ursula" "valentin" "valentina"
  "valeria" "vanesa" "vera" "veronica" "vicent" "vicente" "victor"
  "victoria" "vincenzo" "virginia" "xavi" "xavier" "yaiza"
  "yasmin" "youssef" "zoe"
)

lipsum_lastnames=(
  "garcia" "martinez" "lopez" "rodriguez" "sanchez" "fernandez"
  "perez" "gonzalez" "gomez" "ruiz" "jimenez" "martin"
  "hernandez" "moreno" "muñoz" "diaz" "romero" "alvarez"
  "navarro" "torres" "ramirez" "gutierrez" "molina" "serrano"
  "morales" "ramos" "gil" "marin" "ortiz" "ortega"
  "flores" "alonso" "dominguez" "castillo" "delgado" "castro"
  "rubio" "gimenez" "ferrer" "vazquez" "vila" "medina"
  "soler" "cortes" "serra" "vidal" "singh" "cruz"
  "guerrero" "nuñez" "cano" "puig" "aguilar" "marti"
  "blanco" "lozano" "roca" "reyes" "duran" "mendez"
  "marquez" "garrido" "vargas" "rojas" "herrera" "casas"
  "leon" "campos" "carmona" "fuentes" "carrasco" "pascual"
  "font" "santos" "peña" "caballero" "sanz" "costa"
  "gallego" "segura" "suarez" "hidalgo" "pujol" "mora"
  "cabrera" "calvo" "moya" "rovira" "aguilera" "ibañez"
  "arias" "mas" "gallardo" "montero" "chen" "pons"
  "prieto" "sala" "soto" "riera" "iglesias" "parra"
  "sole" "nieto" "vega" "luque" "mendoza" "rivera"
  "benitez" "vera" "santiago" "sola" "lara" "grau"
  "valls" "silva" "franco" "carrillo" "bosch" "soriano"
  "roig" "roman" "bravo" "salvador" "contreras" "vicente"
  "domenech" "rios" "valero" "sierra" "saez" "velasco"
  "prat" "tomas" "casado" "gracia" "herrero" "pastor"
  "robles" "kaur" "montes" "jurado" "padilla" "ali"
  "exposito" "espinosa" "guzman" "pardo" "rivas" "mateo"
  "camacho" "guillen" "ros" "salazar" "ventura" "esteban"
  "izquierdo" "beltran" "miranda" "crespo" "avila" "codina"
  "luna" "alarcon" "roldan" "ahmed" "martos" "aranda"
  "macias" "zamora" "coll" "merino" "paredes" "oliva"
  "villanueva" "heredia" "galvez" "escobar" "calderon" "wang"
  "carbonell" "palacios" "domingo" "vives" "diez" "andreu"
  "amaya" "ribas" "arroyo" "maldonado" "simon" "salas"
  "bernal" "hurtado" "zhang" "redondo" "andres" "murillo"
  "vasquez" "acosta" "esteve" "bueno" "lorenzo" "galan"
  "casanovas" "lin" "planas" "pacheco" "cuevas" "valverde"
  "lorente" "valencia" "abad" "cardenas" "pereira" "bautista"
  "asensio" "blasco" "mata" "casals" "millan" "ordoñez"
  "ponce" "bermudez" "hussain" "plaza" "guerra" "rueda"
  "ramon" "lazaro" "pla" "carreras" "camps" "barrera"
  "sancho" "manzano" "cardona" "gimeno" "farre" "quesada"
  "borras" "quintana" "garriga" "prats" "escudero" "linares"
  "aparicio" "marcos" "estrada" "collado" "montoya" "arenas"
  "badia" "comas" "ayala" "mesa" "pozo" "castaño"
  "zapata" "capdevila" "valle" "alba" "bonilla" "alcaraz"
  "valles" "navas" "zambrano" "miro" "requena" "pineda"
  "mejia" "mateu" "bertran" "benito" "khan" "villar"
  "rey" "de la cruz" "bonet" "torras" "cabello" "rico"
  "caceres" "galindo" "salinas" "soria" "burgos" "cuenca"
  "reina" "liu" "trujillo" "castells" "sans" "egea"
  "chavez" "figueras" "li" "oliver" "mena" "peralta"
  "camara" "juarez" "santamaria" "ferre" "marco" "pulido"
  "noguera" "rius" "catalan" "villegas" "chacon" "miguel"
  "miralles" "belmonte" "granados" "rivero" "palau" "ribera"
  "ye" "polo" "rosa" "correa" "wu" "palma"
  "moral" "caro" "santana" "alsina" "mateos" "ballesteros"
  "alvarado" "villalba" "amador" "valenzuela" "salguero" "juan"
  "baena" "tapia" "canals" "arjona" "carrera" "llorens"
  "cordoba" "espinoza" "rosell" "pinto" "corral" "duarte"
  "latorre" "carvajal" "sabate" "olivares" "estevez" "xu"
  "viñas" "vallejo" "barba" "salgado" "anton" "lucas"
  "cabezas" "navarrete" "varela" "cuesta" "cobo" "osorio"
  "conde" "velasquez" "gamez" "diallo" "alcantara" "solis"
  "toro" "marques" "vela" "porras" "blazquez" "royo"
  "pallares" "castilla" "colomer" "saavedra" "paz" "naranjo"
  "carrion" "aguirre" "pino" "cervera" "casanova" "pages"
  "julia" "romera" "muhammad" "dalmau" "villa" "da silva"
  "riba" "cordero" "velez" "leal" "carretero" "otero"
  "nicolas" "armengol" "caparros" "de la torre" "clemente" "zhou"
  "arevalo" "leiva" "mir" "rosales" "perea" "boix"
  "moyano" "morera" "moran" "sosa" "barroso" "espejo"
  "llobet" "bermejo" "pizarro" "godoy" "amat" "busquets"
  "matas" "blanch" "calero" "del rio" "ferreira" "aviles"
  "vilchez" "alcaide" "figueroa" "parera" "iqbal" "nadal"
  "de la fuente" "vendrell" "galera" "ojeda" "montserrat" "barragan"
  "torrents" "mestres" "escribano" "gordillo" "becerra" "cantero"
  "ballester" "guevara" "batlle" "haro" "oliveras" "paez"
  "pelaez" "alfonso" "barrios" "orellana" "pares" "ochoa"
  "llamas" "quintero" "rodrigo" "madrid" "sevilla" "sandoval"
  "gascon" "corominas" "olle" "jordan" "cobos" "ariza"
  "alcala" "segarra" "carbo" "aznar" "salmeron" "tena"
  "arnau" "fabregas" "vilalta" "oller" "piñol" "morillo"
  "cazorla" "solano" "alegre" "carreño" "hernando" "farres"
  "andrade" "vergara" "canovas" "osuna" "zhu" "torrent"
  "molero" "raventos" "rincon" "fajardo" "batista" "borrego"
  "portillo" "cuadrado" "olive" "frias" "raya" "pareja"
  "angulo" "porta" "garces" "palomino" "mestre" "vilar"
  "bou" "teruel" "barcelo" "yang" "castellano" "huertas"
  "macia" "castella" "duque" "toledo" "zafra" "orozco"
  "giralt" "aragon" "gonzales" "miquel" "teixido" "giner"
  "elias" "pou" "hinojosa" "ahmad" "balde" "ripoll"
  "gibert" "ocaña" "vilanova" "tamayo" "melero" "cervantes"
  "de la rosa" "pavon" "artigas" "rojo" "balaguer" "berenguer"
  "jara" "alcazar" "guardia" "cid" "catala" "urbano"
  "romeu" "palomo" "araujo" "cerezo" "puertas" "borrell"
  "conesa" "velazquez" "alemany" "tejada" "abril" "serrat"
  "olmo" "mellado" "llado" "zheng" "masip" "morillas"
  "giraldo" "montilla" "llorente" "prado" "verdaguer" "vilaseca"
  "roura" "guasch" "vizcaino" "jin" "arcos" "tort"
  "tirado" "jaramillo" "campillo" "castello" "aguado" "verges"
  "baños" "segovia" "coma" "moron" "sales" "jane"
  "coca" "garzon" "martorell" "dos santos" "alcalde" "plana"
  "alfaro" "cañas" "saiz" "pujadas" "salcedo" "carballo"
  "recio" "castellanos" "castañeda" "zaragoza" "mejias" "valiente"
  "cebrian" "querol" "llopart" "casellas" "chamorro" "moreira"
  "quispe" "bellido" "abellan" "lafuente" "barranco" "corrales"
  "calvet" "ricart" "heras" "comellas" "davila" "guijarro"
  "cespedes" "barbero" "checa" "fabregat" "mañas" "bello"
  "morcillo" "prados" "pont" "dorado" "agudo" "lucena"
  "bustos" "pi" "guitart" "boada" "pedrosa" "hervas"
  "valera" "montesinos" "acevedo" "amoros" "murcia" "valdivia"
  "lloret" "campoy" "tello" "feliu" "subirana" "cañadas"
  "machado" "cedeño" "laguna" "cabeza" "losada" "chaves"
  "piñero" "vivas" "huguet" "serna" "canal" "bustamante"
  "herranz" "camprubi" "coronado" "vico" "calle" "gonzalo"
  "olmedo" "molins" "mosquera" "solsona" "folch" "montoro"
  "huang" "kumar" "arribas" "carranza" "poveda" "jerez"
  "lobato" "creus" "guirao" "rocha" "real" "perales"
  "colom" "ferreras" "montaño" "guell" "ferrando" "viñals"
  "quiros" "tejero" "colome" "morato" "pueyo" "llopis"
  "fuster" "canales" "mercader" "baro" "bejarano" "arce"
  "rebollo" "campo" "maya" "soldevila" "baez" "paniagua"
  "abbas" "olivera" "peiro" "barea" "espin" "poch"
  "galvan" "jorda" "manrique" "fuste" "olivella" "jiang"
  "menendez" "albert" "jove" "quiroga" "balcells" "miras"
  "ledesma" "pique" "maestre" "puente" "narvaez" "sabater"
  "matos" "medrano" "milan" "vilches" "acedo" "barrero"
  "zurita" "lluch" "ruano" "rodrigues" "ji" "grande"
  "torne" "silvestre" "guardiola" "marimon" "reig" "ureña"
  "criado" "montenegro" "vegas" "mercado" "huerta" "saldaña"
  "porcel" "sanjuan" "tortosa" "patiño" "enriquez" "cirera"
  "sastre" "valdes" "cañete" "ortuño" "julian" "de los santos"
  "peris" "puerto" "riu" "akhtar" "arranz" "rosado"
  "rosello" "sevillano" "espada" "suñe" "cabanillas" "olmos"
  "rosas" "aragones" "sarmiento" "vilardell" "funes" "reche"
  "marmol" "monge" "arteaga" "nebot" "cuellar" "nogales"
  "barahona" "villena" "franch" "agusti" "adell" "guirado"
  "jorba" "benavides" "tovar" "fuertes" "triviño" "valdez"
  "carpio" "ubeda" "vall" "palomares" "rodenas" "gual"
  "tellez" "fonseca" "ndiaye" "alves" "jodar" "homs"
  "saura" "moliner" "del valle" "tudela" "vilaro" "manzanares"
  "el harrak" "anglada" "del pino" "montiel" "jaen" "ferran"
  "peinado" "hu" "de haro" "peñalver" "simo" "barbera"
  "fortuny" "padros" "palomar" "valderrama" "mauri" "climent"
  "vaca" "pellicer" "ibarra" "mera" "bibi" "ceballos"
  "qiu" "sebastian" "gras" "mayor" "torralba" "llop"
  "saenz" "quero" "abella" "gavilan" "baeza" "meza"
  "claramunt" "sun" "sarda" "ruz" "torra" "cifuentes"
  "yuste" "cabre" "isern" "dueñas" "infante" "cañizares"
  "almirall" "roma" "tarres" "francisco" "aguila" "edo"
  "shahzad" "pedraza" "cantos" "palacio" "melendez" "escalante"
  "bel" "jover" "yañez" "gea" "avalos" "castellvi"
  "pradas" "espinal" "salvado" "lujan" "cerda" "toribio"
  "gilabert" "argemi" "mansilla" "piera" "batalla" "monfort"
  "gines" "mehmood" "barrio" "bartolome" "buendia" "company"
  "cots" "begum" "bernabe" "bayo" "mari" "sepulveda"
  "sanchis" "pan" "mota" "quiroz" "cubero" "luis"
  "granado" "queralt" "priego" "cordova" "hassan" "antunez"
  "acuña" "talavera" "gallart" "mur" "tejedor" "lora"
  "andujar" "briones" "jaime" "luengo" "yu" "freixas"
  "chica" "matamoros" "miret" "adan" "junyent" "paris"
  "barrientos" "feliz" "gisbert" "trinidad" "merchan" "españa"
  "siles" "jorge" "del pozo" "roque" "amigo" "trias"
  "jose" "quiñones" "fontanet" "cordon" "giron" "oriol"
  "torrico" "pina" "espinar" "portero" "arellano" "gazquez"
  "morell" "fraile" "roda" "amores" "munne" "valladares"
  "llanos" "quevedo" "mila" "anguita" "zuñiga" "raza"
  "baron" "daza" "torrecillas" "compte" "chaparro" "dieguez"
  "centeno" "samper" "brunet" "cisse" "sanabria" "mira"
  "encinas" "molist" "morata" "campaña" "traore" "mamani"
  "gargallo" "merida" "lopera" "aguayo" "zhao" "carol"
  "gomes" "oviedo" "aymerich" "canton"
)

###################
## type handlers ##
###################

gen_empty() { # -E
  local base="$1" ext="$2" count="$3"
  if (( count <= 0 )); then return 0; fi
  if (( count == 1 )); then
    write_file "${DEST}/${base}.${ext}" ""
    return
  fi
  local i
  for i in $(seq 0 $((count-1))); do
    write_file "${DEST}/${base}_${i}.${ext}" ""
  done
}

gen_book() { # -B
  log_verbose "Genereting books [...]"
  local base="$1" fmt="$2" chapters="$3" count="$4"
  for ((f=0; f<count; f++)); do
    log_verbose "  Genereting book $f [...]"
    local idx=""; (( count>1 )) && idx="_$f"
    local ext="$fmt"
    local path="${DEST}/${base}${idx}.${ext}"
    {
      for ((c=1; c<=chapters; c++)); do
        echo "    Genereting charapter $c of book $f [...]" >&2
        if [[ "$fmt" == "md" ]]; then
          echo -n "# "
        fi
        echo "$c. $(lipsum_sentence $((2 + RANDOM % 2)))"
        echo
        local pcount=$((4 + RANDOM % 2))
        local p
        for ((p=0; p<pcount; p++)); do
          echo "      Genereting paragraph $p if charapter $c of book $f [...]" >&2
          lipsum_paragraph
          echo
        done
        echo
        echo
      done
    } | write_file "$path" "$(cat)"
  done
}

gen_catalog() { # -C
  local base="$1" ext="$2" sep="$3" nlines="$4" count="$5"
  for ((f=0; f<count; f++)); do
    local idx=""; (( count>1 )) && idx="_$f"
    local path="${DEST}/${base}${idx}.${ext}"
    {
      for ((i=0;i<nlines;i++)); do
        local art="$(rand_in "${articles[@]}")"
        local cat="$(rand_in "${categories[@]}")"
        local qty=$(( (RANDOM % 9) + 1 ))
        printf "%s%s%s%s%d\n" "$art" "$sep" "$cat" "$sep" "$qty"
      done
    } | write_file "$path" "$(cat)"
  done
}

gen_dated() { # -D
  local base="$1" ext="$2" start="$3" end="$4"
  local months
  months="$(iter_months "$start" "$end")"
  while IFS= read -r mm; do
    local path="${DEST}/${base}_${mm}.${ext}"
    write_file "$path" ""
  done <<< "$months"
}

# simple pools per categoria
pick_pool() {
  case "$1" in
    roba) echo "${obj_roba[*]}" ;;
    inst_musicals) echo "${obj_inst_musicals[*]}" ;;
    plantes) echo "${obj_plantes[*]}" ;;
    vaixella) echo "${obj_vaixella[*]}" ;;
    coberts) echo "${obj_coberts[*]}" ;;
    menjar) echo "${obj_menjar[*]}" ;;
    begudes) echo "${obj_begudes[*]}" ;;
    papereria) echo "${obj_papereria[*]}" ;;
    *) die "categoria no reconeguda per -O: $1" ;;
  esac
}

gen_objects() { # -O
  local category="$1" n="$2"
  local pool_str; pool_str="$(pick_pool "$category")"
  # shellcheck disable=SC2206
  local pool=($pool_str)
  for ((i=0;i<n;i++)); do
    local obj; obj="$(rand_in "${pool[@]}")"
    local suffix=""
    # afegeix variacions “_k” de tant en tant
#     if (( RANDOM % 3 == 0 )); then suffix="_$((RANDOM%3))"; fi
#     local name="${obj}${suffix}"
#     local idx=""; (( n>1 )) && idx="_$i"
    local path=$( next_path "${DEST}/${obj}" )
    write_file "$path" ""
  done
}

rand_name() {
  rand_in "${lipsum_names[@]}"
}

rand_surname() {
  rand_in "${lipsum_lastnames[@]}"
}
rand_birth() { # YYYY-MM-DD
  local y=$(( $(( $(date +%Y) - 40 )) + RANDOM % 20 )) #Year between 40 and 20 years ago
  local m=$(( 1 + RANDOM % 12 ))
  local d=$(( 1 + RANDOM % 28 )) #This is laaaaaaaazy xD
  printf "%04d-%02d-%02d" "$y" "$m" "$d"
}

gen_users() { # -U
  local base="$1" ext="$2" sep="$3" nlines="$4" count="$5"
  for ((f=0; f<count; f++)); do
    local idx=""; (( count>1 )) && idx="_$f"
    local path="${DEST}/${base}${idx}.${ext}"
    {
      local i
      for ((i=1;i<=nlines;i++)); do
        local id name lastname birth
        id="000000$RANDOM$RANDOM"
        id="${id: -8}"
        name="$(rand_name)"
        lastname="$(rand_surname)"
        birth="$(rand_birth)"
        printf "%s%s%s%s%s%s%s\n" "$id" "$sep" "$name" "$sep" "$lastname" "$sep" "$birth"
      done
    } | write_file "$path" "$(cat)"
  done
}


###########
## drive ##
###########

case "$TYPE" in
  E) gen_empty "$NAME" "$EXT" "$COUNT" ;;
  B) gen_book "$NAME" "$FMT" "${NVAL:-8}" "$COUNT" ;;
  C) gen_catalog "$NAME" "$EXT" "${SEP:-,}" "${NVAL:-8}" "$COUNT" ;;
  D) gen_dated "$NAME" "$EXT" "$START" "$END" ;;
  U) gen_users "$NAME" "$EXT" "${SEP:-:}" "${NVAL:-32}" "$COUNT" ;;
  O) gen_objects "$CATEGORY" "${COUNT:-12}" ;;
  *) die "tipus desconegut: $TYPE" ;;
esac

exit 0
