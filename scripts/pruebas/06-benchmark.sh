#!/usr/bin/env bash
# Parte 3: benchmarks Sysbench, a traves de MaxScale vs. directo al maestro.
#   - oltp_read_write : prueba OLTP exigida (16 hilos, 120 s)
#   - oltp_read_only --skip_trx=on : lecturas fuera de transaccion, donde
#     ReadWriteSplit si reparte la carga entre los esclavos
# Variables: HILOS (16), DURACION (120), TABLAS (4), FILAS (20000)
source "$(dirname "$0")/comun.sh"
HILOS=${HILOS:-16}; DURACION=${DURACION:-120}; TABLAS=${TABLAS:-4}; FILAS=${FILAS:-20000}

MAESTRO=$(direccion_de "$(maestro_actual)")
COMUN="--db-driver=mysql --mysql-user=$APP_USER --mysql-password=$APP_PASSWORD --mysql-db=sbtest --tables=$TABLAS --table-size=$FILAS"
VIA_MAXSCALE="--mysql-host=maxscale --mysql-port=4006"
VIA_DIRECTO="--mysql-host=$MAESTRO --mysql-port=3306"

titulo "Preparando datos sbtest ($TABLAS tablas x $FILAS filas) en $MAESTRO"
docker exec sysbench sysbench oltp_read_write $COMUN $VIA_DIRECTO cleanup >/dev/null 2>&1 || true
docker exec sysbench sysbench oltp_read_write $COMUN $VIA_DIRECTO --threads=4 prepare | tail -2
sleep 5

correr() { # $1=nombre $2=prueba $3=destino $4=extra
  local f="$RESULTADOS/06-$1.txt"
  echo ">> $1 ($HILOS hilos, $DURACION s)..."
  docker exec sysbench sysbench "$2" $COMUN $3 $4 --threads=$HILOS --time=$DURACION \
      --report-interval=10 --db-ps-mode=disable run > "$f" 2>&1
}
api services/RW-Split-Router | jq '.data.attributes.router_diagnostics.server_query_statistics' > "$RESULTADOS/06-stats-antes.json"
correr rw-maxscale  oltp_read_write "$VIA_MAXSCALE" ""
correr rw-directo   oltp_read_write "$VIA_DIRECTO"  ""
correr ro-maxscale  oltp_read_only  "$VIA_MAXSCALE" "--skip_trx=on"
correr ro-directo   oltp_read_only  "$VIA_DIRECTO"  "--skip_trx=on"

titulo "Resumen comparativo"
printf "%-14s %12s %12s %12s %12s %8s\n" PRUEBA TPS QPS LAT_PROM_ms LAT_P95_ms ERRORES
for n in rw-maxscale rw-directo ro-maxscale ro-directo; do
  f="$RESULTADOS/06-$n.txt"
  tps=$(grep -m1 "transactions:" "$f" | sed -E 's/.*\(([0-9.]+) per sec.*/\1/')
  qps=$(grep -m1 "queries:" "$f" | sed -E 's/.*\(([0-9.]+) per sec.*/\1/')
  avg=$(grep -m1 "avg:" "$f" | awk '{print $2}')
  p95=$(grep -m1 "95th percentile:" "$f" | awk '{print $3}')
  err=$(grep -m1 "ignored errors:" "$f" | awk '{print $3}')
  printf "%-14s %12s %12s %12s %12s %8s\n" "$n" "${tps:--}" "${qps:--}" "${avg:--}" "${p95:--}" "${err:--}"
done

titulo "Consultas enrutadas por MaxScale a cada servidor (acumulado)"
api services/RW-Split-Router | jq -r '.data.attributes.router_diagnostics.server_query_statistics[] | "\(.id): total=\(.total) lecturas=\(.read) escrituras=\(.write)"'
