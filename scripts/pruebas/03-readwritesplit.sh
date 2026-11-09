#!/usr/bin/env bash
# Parte 2: demuestra ReadWriteSplit conectandose SOLO a MaxScale (puerto 4006).
#  - SELECT fuera de transaccion -> esclavos (balanceados)
#  - INSERT                      -> maestro
#  - SELECT dentro de transaccion -> maestro
source "$(dirname "$0")/comun.sh"

titulo "20 lecturas 'SELECT @@hostname' (conexiones nuevas a MaxScale)"
for i in $(seq 1 20); do sql_maxscale -N -e "SELECT @@hostname;"; done | sort | uniq -c

titulo "Lecturas dentro de UNA misma sesion (10 SELECT seguidos)"
sql_maxscale -N -e "$(for i in $(seq 1 10); do echo 'SELECT @@hostname;'; done)" | sort | uniq -c

titulo "10 escrituras INSERT ... VALUES (@@hostname) via MaxScale"
for i in $(seq 1 10); do sql_maxscale -e "INSERT INTO demo.registros(nodo) VALUES (CONCAT('rws:', @@hostname));"; done
sql_maxscale -e "SELECT nodo AS ejecutado_en, COUNT(*) AS inserts FROM demo.registros WHERE nodo LIKE 'rws:%' GROUP BY nodo;"

titulo "Mix en una sesion: SELECT, INSERT, SELECT y SELECT dentro de transaccion"
sql_maxscale -e "
SELECT 'select (autocommit)'  AS consulta, @@hostname AS servidor;
INSERT INTO demo.registros(nodo) VALUES (CONCAT('mix:', @@hostname));
SELECT 'select tras insert'   AS consulta, @@hostname AS servidor;
START TRANSACTION;
SELECT 'select en transaccion' AS consulta, @@hostname AS servidor;
COMMIT;"

titulo "Estadisticas del router (consultas enrutadas por servidor)"
api services/RW-Split-Router | jq '.data.attributes.router_diagnostics | {queries, route_master, route_slave, route_all, server_query_statistics}'
