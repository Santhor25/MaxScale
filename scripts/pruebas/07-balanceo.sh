#!/usr/bin/env bash
# Muestra si la carga de LECTURA queda nivelada entre los esclavos.
# Cuenta los SELECT que ejecuto cada nodo (Com_select) antes y despues de una
# carga Sysbench de solo lectura enviada a traves de MaxScale.
#   uso: 07-balanceo.sh            (30 s de carga)
#        DURACION=60 07-balanceo.sh
source "$(dirname "$0")/comun.sh"
DUR=${DURACION:-30}
NODOS="mariadb-master mariadb-slave1 mariadb-slave2"
MAESTRO=$(direccion_de "$(maestro_actual)")

selects() { sql_nodo "$1" -N -e "SHOW GLOBAL STATUS LIKE 'Com_select'" | awk '{print $2}'; }

# Datos para Sysbench (se crean si no existen, p. ej. tras un 'docker compose down -v')
TABLAS=$(sql_nodo "$MAESTRO" -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='sbtest'")
if [ "${TABLAS:-0}" -lt 4 ]; then
  titulo "Preparando tablas sbtest en $MAESTRO"
  docker exec sysbench sysbench oltp_read_only --db-driver=mysql --mysql-host="$MAESTRO" --mysql-port=3306 \
    --mysql-user="$APP_USER" --mysql-password="$APP_PASSWORD" --mysql-db=sbtest --tables=4 --table-size=20000 prepare | tail -1
  sleep 3
fi

declare -A ANTES
for n in $NODOS; do ANTES[$n]=$(selects "$n"); done

titulo "Carga de solo lectura via MaxScale: 16 hilos durante $DUR s"
docker exec sysbench sysbench oltp_read_only --db-driver=mysql --mysql-host=maxscale --mysql-port=4006 \
  --mysql-user="$APP_USER" --mysql-password="$APP_PASSWORD" --mysql-db=sbtest --tables=4 --table-size=20000 \
  --threads=16 --time="$DUR" --skip_trx=on --db-ps-mode=disable --report-interval=10 run \
  | grep -E "^\[|transactions:|queries:"

titulo "SELECT ejecutados por cada nodo durante la carga"
TOTAL=0; declare -A DELTA
for n in $NODOS; do DELTA[$n]=$(( $(selects "$n") - ANTES[$n] )); TOTAL=$(( TOTAL + DELTA[$n] )); done
printf "%-16s %-8s %12s %8s\n" NODO ROL SELECTS "%"
for n in $NODOS; do
  rol=$([ "$n" = "$MAESTRO" ] && echo maestro || echo esclavo)
  printf "%-16s %-8s %12d %7.1f%%\n" "$n" "$rol" "${DELTA[$n]}" "$(echo "scale=4; 100*${DELTA[$n]}/$TOTAL" | bc)"
done
echo
echo "Si el balanceo funciona, los dos esclavos quedan con un porcentaje parecido y el maestro casi en 0."

titulo "Lo mismo visto por MaxScale (acumulado desde que arranco MaxScale)"
api services/RW-Split-Router | jq -r '.data.attributes.router_diagnostics.server_query_statistics[] | "\(.id): lecturas=\(.read)  escrituras=\(.write)  total=\(.total)"'
