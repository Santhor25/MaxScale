#!/usr/bin/env bash
# Parte 3: reconecta el maestro original y verifica que MaxScale lo
# reintegra como ESCLAVO (auto_rejoin). Opcional: switchover de regreso.
#   uso: 05-reintegrar-maestro.sh [--switchover]
source "$(dirname "$0")/comun.sh"

CAIDO=$(cat "$RESULTADOS/.maestro_caido" 2>/dev/null || echo mariadb-master)
ID=$(api servers | jq -r --arg a "$CAIDO" '.data[] | select(.attributes.parameters.address==$a) | .id')

titulo "Arrancando de nuevo $CAIDO ($ID)"
T0=$(ahora)
docker start "$CAIDO" >/dev/null
until [ "$(docker inspect -f '{{.State.Health.Status}}' "$CAIDO")" = "healthy" ]; do sleep 1; done
echo "Contenedor healthy en $(printf '%.1f' "$(echo "$(ahora) - $T0" | bc)") s"

ESTADO=""
for i in $(seq 1 120); do
  ESTADO=$(api "servers/$ID" | jq -r '.data.attributes.state')
  [[ "$ESTADO" == *Slave* ]] && break
  sleep 1
done
printf ">> %s reintegrado con estado '%s' en %.1f s\n" "$ID" "$ESTADO" "$(echo "$(ahora) - $T0" | bc)"

titulo "Topologia tras la reintegracion"
tabla_servidores

titulo "$CAIDO: SHOW SLAVE STATUS (ahora replica del nuevo maestro)"
sql_nodo "$CAIDO" -e "SHOW SLAVE STATUS\G" | grep -E "Master_Host|Slave_IO_Running|Slave_SQL_Running:|Seconds_Behind_Master|Using_Gtid|Last_IO_Error"
sql_nodo "$CAIDO" -e "SELECT COUNT(*) AS filas_failover_recibidas FROM demo.registros WHERE nodo LIKE 'failover:%'; SELECT @@read_only AS read_only;"

if [ "${1:-}" = "--switchover" ]; then
  titulo "Switchover controlado: devolver el rol de maestro a $ID"
  docker exec maxscale maxctrl call command mariadbmon switchover MariaDB-Monitor "$ID"
  sleep 3
  tabla_servidores
fi
rm -f "$RESULTADOS/.maestro_caido"
