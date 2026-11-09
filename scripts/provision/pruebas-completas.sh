#!/usr/bin/env bash
# Pruebas de la Parte 3: failover, reintegracion y benchmarks.
# Ejecutar con:  vagrant provision --provision-with pruebas
set -uo pipefail
cd /vagrant
mkdir -p resultados
bash scripts/pruebas/04-failover.sh                     2>&1 | tee resultados/04-failover.txt
bash scripts/pruebas/05-reintegrar-maestro.sh --switchover 2>&1 | tee resultados/05-reintegracion.txt
bash scripts/pruebas/06-benchmark.sh                    2>&1 | tee resultados/06-benchmark.txt
