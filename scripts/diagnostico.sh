#!/usr/bin/env bash
# Guarda el estado de los contenedores y el log de MaxScale en resultados/diagnostico.txt
cd /vagrant; mkdir -p resultados
{
  echo "== docker compose ps"; docker compose ps -a
  echo; echo "== docker logs maxscale (ultimas 80 lineas)"; docker logs --tail 80 maxscale 2>&1
  echo; echo "== /var/log/maxscale/maxscale.log"; docker exec maxscale tail -40 /var/log/maxscale/maxscale.log 2>&1
  echo; echo "== maxscale.cnf visto por el contenedor"; docker run --rm --entrypoint ls -v /vagrant/maxscale/maxscale.cnf:/etc/maxscale.cnf:ro mariadb/maxscale:23.08 -l /etc/maxscale.cnf 2>&1
  echo; echo "== entrypoint de la imagen"; docker inspect -f '{{json .Config.Entrypoint}} {{json .Config.Cmd}} user={{.Config.User}}' mariadb/maxscale:23.08
} > resultados/diagnostico.txt 2>&1
echo "Listo: resultados/diagnostico.txt"
