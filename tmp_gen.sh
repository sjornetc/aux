#!/bin/bash

ROOT_PATH="/tmp/exemples/"

nums(){
    echo $RANDOM$RANDOM$RANDOM$RANDOM| head -c$1
}

create(){
    touch $ROOT_PATH$1
    echo "  Creat $ROOT_PATH$1"
}

echo "📂 Carpeta $ROOT_PATH"
mkdir $ROOT_PATH
echo "  Creat $ROOT_PATH"
echo ""
echo "📄 Arxius"
create page
create pag

for i in $(seq 8)
do
    # pag??
    create pag$(nums 2)
    # pag??.txt
    create pag$(nums 2).txt
    # pag-??
    create pag-$(nums 2)
    # .pag??
    create .pag$(nums 2)
    # page??
    create page$(nums 2)
done
echo ""

echo "Estructura creada. Quan acabis l'activitat, presiona qualsevol tecla per esborrar l'estructura!"
read -n1
echo "🗑 Esborrant"
rm -r $ROOT_PATH
