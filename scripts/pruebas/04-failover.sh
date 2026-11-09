#!/usr/bin/env bash
# Parte 3: failover automatico.
#  1. Arranca un "cliente escritor" que hace un INSERT via MaxScale cada ~200 ms.
#  2. Detiene el contenedor del maestro actual.
#  3. Mide el tiempo hasta que MaxScale (API REST) reporta un nuevo Master.
#  4. Mide la ventana real sin escrituras vista por el cliente (impacto).
source "$(dirname "$0")/comun.sh"

LOG_ESCRITOR="$RESULTADOS/04-escritor.log"
DURACION_ESCRITOR=45

titulo "Topologia ANTES del failover"
tabla_servidores
MAESTRO_ID=$(maestro_actual)
MAESTRO_CONT=$(direccion_de "$MAESTRO_ID")
echo "Maestro actual: $MAESTRO_ID ($MAESTRO_CONT)"
[ -z "$MAESTRO_ID" ] && { echo "No hay maestro, abortando"; exit 1; }

titulo "Iniciando cliente escritor ($DURACION_ESCRITOR s, 1 INSERT cada ~200 ms)"
docker exec -e APP_USER -e APP_PASSWORD -e DUR=$DURACION_ESCRITOR sysbench bash -c '
  fin=$(( $(date +%s) + DUR ))
  while [ $(date +%s) -lt $fin ]; do
    t=$(date +%s.%N)
    if out=$(mariadb -h maxscale -P 4006 -u"$APP_USER" -p"$APP_PASSWORD" --connect-timeout=2 -N \
          -e "INSERT INTO demo.registros(nodo) VALUES (CONCAT(\"failover:\", @@hostname)); SELECT @@hostname;" 2>&1); then
      echo "$t OK"
    else
      echo "$t FAIL $(echo "$out" | head -1)"
    fi
    sleep 0.2
  done' > "$LOG_ESCRITOR" 2>&1 &
PID_ESCRITOR=$!
sleep 8

titulo "Deteniendo el maestro: docker stop $MAESTRO_CONT"
T0=$(ahora)
docker stop "$MAESTRO_CONT" >/dev/null
T_STOP=$(ahora)
echo "Contenedor detenido en $(echo "$T_STOP - $T0" | bc) s"

NUEVO=""
while true; do
  NUEVO=$(maestro_actual)
  if [ -n "$NUEVO" ] && [ "$NUEVO" != "$MAESTRO_ID" ]; then break; fi
  if (( $(echo "$(ahora) - $T0 > 120" | bc) )); then echo "TIMEOUT: no hubo promocion en 120 s"; break; fi
  sleep 0.2
done
T1=$(ahora)
echo "Nuevo maestro promovido por MaxScale: $NUEVO ($(direccion_de "$NUEVO"))"
printf ">> TIEMPO DE FAILOVER (docker stop -> nuevo Master en API REST): %.2f s\n" "$(echo "$T1 - $T0" | bc)"

wait $PID_ESCRITOR

titulo "Impacto visto por el cliente escritor"
TOTAL=$(grep -c . "$LOG_ESCRITOR"); OK=$(grep -c " OK" "$LOG_ESCRITOR"); FAIL=$(grep -c " FAIL" "$LOG_ESCRITOR")
echo "Intentos: $TOTAL   OK: $OK   FALLIDOS: $FAIL"
awk '
  $2=="OK" { if (enfalla) { printf(">> VENTANA SIN ESCRITURAS: %.2f s (desde el ultimo OK antes de la caida hasta el primer OK despues)\n", $1-ultok); enfalla=0 } ultok=$1 }
  $2=="FAIL" { if (!enfalla) { enfalla=1; printf("Primer error: %s\n", $0) } }
' "$LOG_ESCRITOR"
[ "$FAIL" = "0" ] && echo ">> Ningun INSERT fallo: MaxScale reconecto de forma transparente (master_reconnection)."

titulo "Topologia DESPUES del failover"
tabla_servidores
sql_maxscale -e "SELECT nodo AS escrito_en, COUNT(*) AS inserts FROM demo.registros WHERE nodo LIKE 'failover:%' GROUP BY nodo;"

echo "$MAESTRO_CONT" > "$RESULTADOS/.maestro_caido"
