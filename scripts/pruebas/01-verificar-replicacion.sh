#!/usr/bin/env bash
# Parte 1: verifica la topologia de replicacion (SHOW SLAVE STATUS),
# la replicacion semisincrona y la propagacion de datos.
source "$(dirname "$0")/comun.sh"

titulo "Maestro: estado del binlog y replicacion semisincrona"
sql_nodo mariadb-master -e "SELECT @@hostname AS nodo, @@server_id AS server_id, @@gtid_current_pos AS gtid, @@read_only AS read_only;
SHOW GLOBAL VARIABLES LIKE 'rpl_semi_sync_master_enabled';
SHOW GLOBAL STATUS LIKE 'Rpl_semi_sync_master_status';
SHOW GLOBAL STATUS LIKE 'Rpl_semi_sync_master_clients';
SHOW SLAVE HOSTS;"

for nodo in mariadb-slave1 mariadb-slave2; do
  titulo "$nodo: SHOW SLAVE STATUS"
  sql_nodo "$nodo" -e "SHOW SLAVE STATUS\G" | grep -E "Master_Host|Slave_IO_Running|Slave_SQL_Running:|Seconds_Behind_Master|Using_Gtid|Gtid_IO_Pos|Last_IO_Error|Last_SQL_Error"
  sql_nodo "$nodo" -e "SHOW GLOBAL STATUS LIKE 'Rpl_semi_sync_slave_status'; SELECT @@read_only AS read_only;"
done

titulo "Propagacion: INSERT en el maestro y lectura en los esclavos"
marca="prueba-replicacion-$(date +%s)"
sql_nodo mariadb-master -e "INSERT INTO demo.registros(nodo) VALUES ('$marca');"
sleep 1
for nodo in mariadb-slave1 mariadb-slave2; do
  n=$(sql_nodo "$nodo" -N -e "SELECT COUNT(*) FROM demo.registros WHERE nodo='$marca';")
  echo "$nodo -> filas con la marca '$marca': $n  $([ "$n" = "1" ] && echo OK || echo FALLO)"
done
