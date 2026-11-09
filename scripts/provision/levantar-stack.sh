#!/usr/bin/env bash
# Levanta el stack con Docker Compose y ejecuta las pruebas basicas 01-03.
set -euo pipefail
cd /vagrant
mkdir -p resultados

echo ">> docker compose build / up (espera health checks)..."
docker compose build
docker compose up -d --wait --wait-timeout 300
# Relee maxscale.cnf por si cambio desde la ultima vez
docker compose restart maxscale
docker compose ps

# Seguridad: asegura que los hilos de replicacion esten corriendo
for n in mariadb-slave1 mariadb-slave2; do
  docker exec "$n" mariadb -uroot -p"$(grep MARIADB_ROOT_PASSWORD lab.env | cut -d= -f2)" -e "START SLAVE;" 2>/dev/null || true
done

echo ">> Esperando a que MaxScale detecte la topologia..."
for i in $(seq 1 60); do
  if curl -s -u admin:mariadb http://localhost:8989/v1/servers | jq -e '[.data[].attributes.state] | map(select(test("Master|Slave"))) | length == 3' >/dev/null 2>&1; then
    echo "   topologia detectada"; break
  fi
  if [ "$i" = 60 ]; then
    echo "MaxScale no respondio; guardando diagnostico en resultados/diagnostico.txt"
    bash scripts/diagnostico.sh; exit 1
  fi
  sleep 2
done

bash scripts/pruebas/01-verificar-replicacion.sh 2>&1 | tee resultados/01-replicacion.txt
bash scripts/pruebas/02-api-rest.sh            2>&1 | tee resultados/02-api-rest.txt
bash scripts/pruebas/03-readwritesplit.sh      2>&1 | tee resultados/03-readwritesplit.txt

echo
echo "Stack listo. API REST desde Windows: http://localhost:8989/v1/servers  (admin / mariadb)"
echo "Siguiente paso: vagrant provision --provision-with pruebas"
