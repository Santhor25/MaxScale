#!/usr/bin/env bash
# Parte 2: auto-deteccion de topologia consultando la API REST de MaxScale.
source "$(dirname "$0")/comun.sh"

titulo "GET /v1/servers  (topologia detectada por MariaDB Monitor)"
tabla_servidores

titulo "GET /v1/monitors/MariaDB-Monitor  (parametros clave)"
api monitors/MariaDB-Monitor | jq '.data.attributes | {state, modulo: .module, parameters: (.parameters | {auto_failover, auto_rejoin, failcount, enforce_read_only_slaves, monitor_interval})}'

titulo "GET /v1/services/RW-Split-Router  (router y conexiones)"
api services/RW-Split-Router | jq '.data.attributes | {router, state, connections, total_connections}'

titulo "GET /v1/listeners"
api listeners | jq -r '.data[] | "\(.id)  puerto=\(.attributes.parameters.port)  estado=\(.attributes.state)"'

titulo "maxctrl list servers (CLI equivalente)"
docker exec maxscale maxctrl list servers
