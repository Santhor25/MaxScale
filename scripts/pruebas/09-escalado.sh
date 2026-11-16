#!/usr/bin/env bash
# Plan de prueba 1 - Escalado horizontal con mas esclavos.
#  1. Levanta mariadb-slave3 y mariadb-slave4 (docker-compose.escalado.yml).
#  2. Los registra EN CALIENTE en MaxScale (sin reiniciarlo ni editar maxscale.cnf).
#  3. Verifica que replican y que MaxScale los detecta como Slave.
#  4. Mide el reparto de lecturas entre los 4 esclavos (reutiliza 07-balanceo.sh).
#   uso: 09-escalado.sh            -> agrega los esclavos y mide
#        09-escalado.sh --quitar   -> los saca de MaxScale y los elimina
source "$(dirname "$0")/comun.sh"
cd "$PROYECTO_DIR"
COMPOSE="docker compose -f docker-compose.yml -f docker-compose.escalado.yml"

if [ "${1:-}" = "--quitar" ]; then
  titulo "Quitando server4 y server5 de MaxScale"
  for s in server4 server5; do
    docker exec maxscale maxctrl unlink service RW-Split-Router "$s" 2>/dev/null
    docker exec maxscale maxctrl unlink monitor MariaDB-Monitor "$s" 2>/dev/null
    docker exec maxscale maxctrl destroy server "$s" 2>/dev/null
  done
  $COMPOSE rm -sfv mariadb-slave3 mariadb-slave4
  docker volume rm "$(basename "$PROYECTO_DIR" | tr '[:upper:]' '[:lower:]')_slave3-data" \
                   "$(basename "$PROYECTO_DIR" | tr '[:upper:]' '[:lower:]')_slave4-data" 2>/dev/null
  tabla_servidores
  exit 0
fi

if [ "$(maestro_actual)" != "server1" ]; then
  echo "El maestro actual no es server1 (mariadb-master). Ejecuta primero:"
  echo "  docker exec maxscale maxctrl call command mariadbmon switchover MariaDB-Monitor server1"
  exit 1
fi

titulo "Topologia ANTES (3 nodos)"
tabla_servidores

titulo "Levantando mariadb-slave3 y mariadb-slave4"
T0=$(ahora)
$COMPOSE up -d --wait mariadb-slave3 mariadb-slave4
for n in mariadb-slave3 mariadb-slave4; do sql_nodo "$n" -e "START SLAVE;" 2>/dev/null; done

titulo "Registrando los nuevos servidores en MaxScale (en caliente)"
docker exec maxscale maxctrl create server server4 mariadb-slave3 3306 \
  --services RW-Split-Router --monitors MariaDB-Monitor 2>&1 | tail -1
docker exec maxscale maxctrl create server server5 mariadb-slave4 3306 \
  --services RW-Split-Router --monitors MariaDB-Monitor 2>&1 | tail -1

titulo "Esperando a que los nuevos esclavos se pongan al dia"
GTID_M=$(sql_nodo mariadb-master -N -e "SELECT @@gtid_current_pos")
for i in $(seq 1 300); do
  g3=$(sql_nodo mariadb-slave3 -N -e "SELECT @@gtid_slave_pos" 2>/dev/null)
  g4=$(sql_nodo mariadb-slave4 -N -e "SELECT @@gtid_slave_pos" 2>/dev/null)
  printf "\r  maestro=%s  slave3=%s  slave4=%s   " "$GTID_M" "${g3:--}" "${g4:--}"
  [ "$g3" = "$GTID_M" ] && [ "$g4" = "$GTID_M" ] && break
  sleep 1
done
echo
printf ">> Esclavos nuevos sincronizados en %.1f s desde que se crearon\n" "$(echo "$(ahora) - $T0" | bc)"

for n in mariadb-slave3 mariadb-slave4; do
  titulo "$n: SHOW SLAVE STATUS"
  sql_nodo "$n" -e "SHOW SLAVE STATUS\G" | grep -E "Master_Host|Slave_IO_Running|Slave_SQL_Running:|Seconds_Behind_Master"
  sql_nodo "$n" -N -e "SELECT CONCAT('filas en demo.registros: ', COUNT(*)) FROM demo.registros"
done

sleep 3
titulo "Topologia DESPUES (5 nodos)"
tabla_servidores
echo
echo "Semisincrona: clientes conectados al maestro = $(sql_nodo mariadb-master -N -e "SHOW GLOBAL STATUS LIKE 'Rpl_semi_sync_master_clients'" | awk '{print $2}') (esperado: 4)"

titulo "Reparto de lecturas con 4 esclavos"
bash "$(dirname "$0")/07-balanceo.sh"
