#!/usr/bin/env bash
# Muestra que un nodo que estuvo apagado se pone al dia solo al volver.
#  1. Apaga un esclavo.
#  2. Escribe 500.000 filas a traves de MaxScale mientras esta apagado.
#  3. Lo enciende y muestra segundo a segundo como alcanza al maestro.
#   uso: 08-ponerse-al-dia.sh [contenedor]   (por defecto mariadb-slave2)
source "$(dirname "$0")/comun.sh"
NODO=${1:-mariadb-slave2}
LOTES=${LOTES:-10}; FILAS=${FILAS:-50000}
MAESTRO=$(direccion_de "$(maestro_actual)")
[ "$NODO" = "$MAESTRO" ] && { echo "$NODO es el maestro actual; elige un esclavo"; exit 1; }

filas() { sql_nodo "$1" -N -e "SELECT COUNT(*) FROM demo.registros" 2>/dev/null; }
retraso() { sql_nodo "$1" -e "SHOW SLAVE STATUS\G" 2>/dev/null | awk '/Seconds_Behind_Master/{print $2}'; }

titulo "Estado inicial (maestro: $MAESTRO)"
for n in mariadb-master mariadb-slave1 mariadb-slave2; do printf "%-16s filas=%s\n" "$n" "$(filas "$n")"; done

titulo "Apagando $NODO"
docker stop "$NODO" >/dev/null
sleep 4
tabla_servidores

titulo "Escribiendo $LOTES lotes de $FILAS filas via MaxScale con $NODO apagado"
for i in $(seq 1 "$LOTES"); do
  sql_maxscale -e "INSERT INTO demo.registros(nodo) SELECT 'lote-$i' FROM demo.seq_1_to_$FILAS;"
  printf "lote %2d/%d escrito  -> filas en el maestro: %s\n" "$i" "$LOTES" "$(filas "$MAESTRO")"
done
OBJETIVO=$(filas "$MAESTRO")
echo ">> $NODO quedo atrasado $((LOTES * FILAS)) filas"

titulo "Encendiendo $NODO y midiendo como se pone al dia"
T0=$(ahora)
docker start "$NODO" >/dev/null
printf "%6s  %12s  %12s  %22s\n" "t(s)" "MAESTRO" "$NODO" "Seconds_Behind_Master"
for i in $(seq 1 300); do
  t=$(printf '%.1f' "$(echo "$(ahora) - $T0" | bc)")
  f=$(filas "$NODO")
  if [ -z "$f" ]; then printf "%6s  %12s  %12s\n" "$t" "$OBJETIVO" "(arrancando)"; sleep 1; continue; fi
  printf "%6s  %12s  %12s  %22s\n" "$t" "$OBJETIVO" "$f" "$(retraso "$NODO")"
  [ "$f" = "$OBJETIVO" ] && break
  sleep 1
done
printf ">> %s se puso al dia en %.1f s desde que se encendio\n" "$NODO" "$(echo "$(ahora) - $T0" | bc)"

titulo "GTID de cada servidor (iguales = misma posicion de replicacion)"
sleep 2
tabla_servidores
