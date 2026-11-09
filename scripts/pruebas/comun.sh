#!/usr/bin/env bash
# Funciones comunes para las pruebas. Se ejecutan dentro de la VM (vagrant ssh).
# Raiz del repo (funciona en la VM de Vagrant o en cualquier Linux/Mac con Docker)
PROYECTO_DIR="${PROYECTO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
set -a; source "$PROYECTO_DIR/lab.env"; set +a

API="http://localhost:8989/v1"
API_AUTH="${MAXSCALE_API_USER}:${MAXSCALE_API_PASSWORD}"
RESULTADOS="$PROYECTO_DIR/resultados"
mkdir -p "$RESULTADOS"

titulo() { echo; echo "=================================================================="; echo "== $*"; echo "=================================================================="; }

# SQL como root directamente sobre un contenedor MariaDB
sql_nodo() { local nodo="$1"; shift; docker exec -i "$nodo" mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" "$@"; }

# SQL como usuario de aplicacion A TRAVES de MaxScale (desde el contenedor sysbench)
sql_maxscale() { docker exec -i sysbench mariadb -h maxscale -P 4006 -u"$APP_USER" -p"$APP_PASSWORD" --connect-timeout=2 "$@"; }

# Consultas a la API REST de MaxScale
api() { curl -s -u "$API_AUTH" "$API/$1"; }

tabla_servidores() {
  api servers | jq -r '["SERVIDOR","DIRECCION","ESTADO","GTID"],
    (.data[] | [.id, .attributes.parameters.address, .attributes.state, (.attributes.gtid_current_pos // "-")]) | @tsv' \
    | column -t -s $'\t'
}

# id del servidor que MaxScale considera maestro (vacio si no hay)
maestro_actual() { api servers | jq -r '[.data[] | select(.attributes.state | test("Master")) | .id][0] // empty'; }
direccion_de() { api "servers/$1" | jq -r '.data.attributes.parameters.address'; }

ahora() { date +%s.%N; }
