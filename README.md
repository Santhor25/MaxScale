# Proyecto 6 — Balanceo de carga de bases de datos con MariaDB MaxScale

Servicios Telemáticos · UAO · 2026-2

> **¿Solo quieres ponerlo a correr?** Ve directo a [Cómo iniciarlo](#cómo-iniciarlo): son tres
> comandos para copiar y pegar.

## ¿Qué hace este proyecto?

Una aplicación con una sola base de datos tiene dos problemas: si ese servidor se cae, se cae todo,
y si llegan muchos usuarios, ese único servidor se satura. Este proyecto resuelve ambos con un
**intermediario inteligente** delante de varias bases de datos:

- **MariaDB 10.11** (3 contenedores): un **maestro**, que recibe las escrituras, y dos **esclavos**,
  que copian automáticamente todo lo que pasa en el maestro. La copia es **semisíncrona**: el maestro
  no confirma un `COMMIT` hasta que un esclavo recibió el dato, así no se pierde aunque el maestro caiga.
- **MariaDB MaxScale 23.08** (1 contenedor): un proxy de base de datos. La aplicación se conecta solo
  a MaxScale (puerto **4006**) y MaxScale decide a qué servidor va cada consulta:
  - **Detecta la topología solo** (*MariaDB Monitor*): revisa los 3 servidores cada segundo y descubre
    quién es maestro y quién esclavo.
  - **Separa lecturas y escrituras** (*ReadWriteSplit*): `SELECT` → esclavos, `INSERT`/`UPDATE`/`DELETE`
    y transacciones → maestro.
  - **Failover automático**: si el maestro se cae, promueve en pocos segundos al esclavo más actualizado
    y reapunta al otro esclavo. Cuando el maestro viejo vuelve, lo reintegra como esclavo.
  - **API REST y GUI web** en el puerto **8989** para ver el estado de todo.
- **Sysbench** (1 contenedor): cliente para pruebas de carga y para conectarse a MaxScale.

Todo corre en **contenedores Docker orquestados con Docker Compose**; no se instala nada en el host.

Resultados obtenidos: failover en **3,77 s** perdiendo 1 de 169 escrituras, el maestro caído vuelve
como esclavo en 6,2 s, y el benchmark Sysbench (16 hilos × 120 s) corre con 0 errores
(ver `resultados/`).

## Arquitectura

```
                 Host  ──  localhost:8989 (API REST / GUI)   localhost:4006 (SQL)
┌──────────────────────────────────────────────── red docker "dbnet" ─────────────┐
│                                                                                 │
│   sysbench ──SQL──►  maxscale :4006 (RW-Split-Listener)   :8989 API REST        │
│                         │  RW-Split-Router (readwritesplit)                     │
│                         │  MariaDB-Monitor (mariadbmon, auto_failover/rejoin)   │
│            escrituras ┌─┴──────────────┬───────────────────┐ lecturas           │
│                       ▼                ▼                   ▼                    │
│               mariadb-master    mariadb-slave1      mariadb-slave2              │
│               server_id=1       server_id=2         server_id=3                 │
│                  │  replicación semisíncrona (GTID)   ▲                         │
│                  └──────────────────┴─────────────────┘                         │
└─────────────────────────────────────────────────────────────────────────────────┘
```

| Contenedor      | Imagen                 | Puerto en el host | Rol |
|-----------------|------------------------|-------------------|-----|
| mariadb-master  | mariadb:10.11          | 3307              | Maestro inicial |
| mariadb-slave1  | mariadb:10.11          | 3308              | Esclavo |
| mariadb-slave2  | mariadb:10.11          | 3309              | Esclavo |
| maxscale        | mariadb/maxscale:23.08 | 4006, 8989        | Router ReadWriteSplit, monitor, API REST |
| sysbench        | build `./sysbench`     | —                 | Cliente de pruebas y benchmark |

### ¿Qué pasa al arrancar?

1. Docker Compose crea la red `dbnet` y un volumen persistente por cada MariaDB.
2. Arranca `mariadb-master`. La primera vez ejecuta `mariadb/init/master/01-usuarios.sql`, que crea
   los usuarios de replicación, monitor, servicio de MaxScale y aplicación, y las bases `demo` y `sbtest`.
3. Cuando el maestro pasa su *health check*, arrancan los esclavos. Ejecutan
   `mariadb/init/slave/01-replica.sql` (`CHANGE MASTER ... MASTER_USE_GTID=slave_pos`) y empiezan a
   copiar al maestro; los usuarios les llegan replicados.
4. Cuando los 3 MariaDB están sanos, arranca MaxScale con `maxscale/maxscale.cnf`, detecta la topología
   y abre los puertos 4006 y 8989.
5. Arranca el contenedor `sysbench`, que queda esperando órdenes.

## Cómo iniciarlo

Elige **una** de las dos opciones según lo que tengas instalado. Cada bloque se copia y se pega
completo en la terminal.

### Opción A — Con Docker (recomendada)

**Requisitos:** [Git](https://git-scm.com/downloads) y Docker con Compose:
[Docker Desktop](https://www.docker.com/products/docker-desktop/) en Windows o Mac, o Docker Engine
con el plugin Compose en Linux. Docker Desktop debe estar **abierto** antes de empezar.

**Paso 1 — Clonar y levantar todo** (PowerShell, terminal de Mac o de Linux):

```bash
git clone https://github.com/Santhor25/MaxScale.git
cd MaxScale
docker compose up -d --wait
```

La primera vez descarga las imágenes y construye la de Sysbench (5–10 minutos según la conexión).
El comando termina solo cuando todo está arriba.

**Paso 2 — Verificar:**

```bash
docker compose ps
docker exec maxscale maxctrl list servers
```

Deben aparecer los 5 contenedores `Up` (los tres MariaDB `healthy`) y MaxScale debe mostrar
`server1` como `Master, Running` y `server2` y `server3` como `Slave, Running`. Si los servidores
aún no muestran rol, espera 10 segundos y repite el segundo comando.

**Paso 3 — Abrir la GUI de MaxScale:** <http://localhost:8989> (usuario `admin`, clave `mariadb`).

Los scripts de prueba (`scripts/pruebas/`) necesitan `bash`, `curl`, `jq` y `bc`. En Linux y Mac se
corren directamente desde la carpeta `MaxScale`; en Windows, desde WSL.

### Opción B — Con Vagrant (equipos sin Docker)

**Requisitos:** [Git](https://git-scm.com/downloads),
[VirtualBox](https://www.virtualbox.org/wiki/Downloads) y
[Vagrant](https://developer.hashicorp.com/vagrant/install). La VM (Ubuntu 22.04) solo instala Docker;
el proyecto sigue corriendo en contenedores.

**Paso 1 — Clonar y crear la VM** (PowerShell):

```powershell
git clone https://github.com/Santhor25/MaxScale.git
cd MaxScale
vagrant up
```

`vagrant up` crea la VM, instala Docker, levanta los contenedores y corre las pruebas 01–03 (10–20
minutos la primera vez). Al final debe decir `Stack listo`.

**Paso 2 — Entrar a la VM** (todos los comandos de las secciones siguientes se ejecutan ahí):

```powershell
vagrant ssh
```

```bash
cd /vagrant
docker exec maxscale maxctrl list servers
```

**Paso 3 — Abrir la GUI de MaxScale** en el navegador de Windows: <http://localhost:8989>
(usuario `admin`, clave `mariadb`). Los puertos 4006 y 8989 de la VM quedan redirigidos a
`localhost`.

Si `vagrant up` termina en *timeout*, es porque Hyper-V está activo y VirtualBox arranca lento:
ejecuta `vagrant up --provision` para continuar (ver *Solución de problemas*).

**Para apagar y volver otro día:** `exit` y luego `vagrant halt`. Al volver, `vagrant up` y
`vagrant ssh` (ya no reinstala nada; los contenedores arrancan solos).

### Comprobar que funciona

1. **GUI de MaxScale:** abrir <http://localhost:8989> (usuario `admin`, clave `mariadb`). Deben verse
   `server1` como *Master* y `server2` y `server3` como *Slave*.
2. **Desde la terminal:**
   ```bash
   docker exec maxscale maxctrl list servers
   ```
3. **Conectarse como una aplicación** (a través de MaxScale):
   ```bash
   docker exec -it sysbench mariadb -h maxscale -P 4006 -uapp -papp_pass demo
   ```
   ```sql
   SELECT @@hostname;                               -- responde un esclavo
   INSERT INTO registros(nodo) VALUES (@@hostname); -- se ejecuta en el maestro
   SELECT * FROM registros ORDER BY id DESC LIMIT 1;
   ```

## Pruebas automatizadas

Desde la raíz del repositorio (en la Opción B, dentro de `vagrant ssh` y `cd /vagrant`):

```bash
bash scripts/pruebas/01-verificar-replicacion.sh
bash scripts/pruebas/02-api-rest.sh
bash scripts/pruebas/03-readwritesplit.sh
bash scripts/pruebas/04-failover.sh
bash scripts/pruebas/05-reintegrar-maestro.sh --switchover
bash scripts/pruebas/06-benchmark.sh               # ~10 min
bash scripts/pruebas/07-balanceo.sh                # reparto de lecturas entre esclavos (~1 min)
bash scripts/pruebas/08-ponerse-al-dia.sh          # un esclavo apagado se pone al dia (~1 min)
```

Con Vagrant también se pueden correr todas juntas desde Windows:
`vagrant provision --provision-with pruebas`.

| # | Script | Qué demuestra |
|---|--------|---------------|
| 01 | `01-verificar-replicacion.sh` | `SHOW SLAVE STATUS`, semisíncrona activa (2 clientes), propagación de un INSERT |
| 02 | `02-api-rest.sh` | `GET /v1/servers`: topología auto-detectada (Master / Slave) |
| 03 | `03-readwritesplit.sh` | SELECT → esclavos, INSERT → maestro, SELECT en transacción → maestro |
| 04 | `04-failover.sh` | `docker stop` del maestro, tiempo hasta la promoción y ventana sin escrituras |
| 05 | `05-reintegrar-maestro.sh` | el maestro original vuelve como esclavo (`auto_rejoin`); `--switchover` le devuelve el rol |
| 06 | `06-benchmark.sh` | Sysbench OLTP 16 hilos × 120 s vía MaxScale vs. directo al maestro |
| 07 | `07-balanceo.sh` | SELECT ejecutados por cada nodo bajo carga: los esclavos se reparten la lectura |
| 08 | `08-ponerse-al-dia.sh` | apaga un esclavo, escribe 500.000 filas y mide cómo se pone al día al volver |

Cada script guarda su salida en `resultados/`. Antes de repetir el 04, correr el 05 con
`--switchover` para que `mariadb-master` vuelva a ser el maestro.

## Estructura del repositorio

```
docker-compose.yml                    5 servicios, volúmenes persistentes y health checks
lab.env                               contraseñas del laboratorio (solo para pruebas)
mariadb/init/master/01-usuarios.sql   usuarios repl, monitor, servicio MaxScale, app + BDs
mariadb/init/slave/01-replica.sql     CHANGE MASTER ... MASTER_USE_GTID=slave_pos
maxscale/maxscale.cnf                 monitor, router y listener (montado como volumen)
sysbench/Dockerfile                   sysbench 1.0 + cliente mariadb
scripts/pruebas/01..06                pruebas mínimas del enunciado
scripts/diagnostico.sh                guarda estado y logs de MaxScale si algo falla
Vagrantfile, scripts/provision/       opción B: VM con Docker
resultados/                           salidas de las pruebas
```

## API REST de MaxScale (ejemplos)

Usuario por defecto `admin` / `mariadb`.

```bash
curl -u admin:mariadb http://localhost:8989/v1/servers                    # topología
curl -u admin:mariadb http://localhost:8989/v1/servers/server1            # un servidor
curl -u admin:mariadb http://localhost:8989/v1/monitors/MariaDB-Monitor   # monitor
curl -u admin:mariadb http://localhost:8989/v1/services/RW-Split-Router   # router + estadísticas
curl -u admin:mariadb http://localhost:8989/v1/listeners
curl -u admin:mariadb http://localhost:8989/v1/maxscale                   # info general

# resumen legible
curl -s -u admin:mariadb http://localhost:8989/v1/servers \
  | jq -r '.data[] | "\(.id)\t\(.attributes.parameters.address)\t\(.attributes.state)"'
```

En PowerShell usar `curl.exe` en lugar de `curl`.

## Guía de failover

1. Ver quién es maestro: <http://localhost:8989> o `docker exec maxscale maxctrl list servers`.
2. Simular la caída: `docker stop mariadb-master`.
3. Tras `failcount × monitor_interval` (3 × 1 s) MaxScale marca `server1` como `Down`, elige el
   esclavo más actualizado (GTID), lo promueve, apaga su `read_only` y redirige el otro esclavo.
4. Los clientes siguen conectados a `maxscale:4006`; `master_reconnection` y `transaction_replay`
   reenvían las escrituras al nuevo maestro.
5. Recuperación: `docker start mariadb-master`. Con `auto_rejoin=true` MaxScale ejecuta
   `CHANGE MASTER` y lo reintegra como `Slave`.
6. Devolver el rol (opcional):
   `docker exec maxscale maxctrl call command mariadbmon switchover MariaDB-Monitor server1`.

Para verlo en vivo, dejar en otra terminal: `watch -n1 "docker exec maxscale maxctrl list servers"`.

## Detener y reiniciar

```bash
docker compose stop          # detiene sin borrar datos
docker compose start         # vuelve a arrancar
docker compose down -v       # borra contenedores Y datos (la próxima vez se reinicializa todo)
```

Con Vagrant: `vagrant halt` apaga la VM y `vagrant destroy -f` la elimina.

## Solución de problemas

| Síntoma | Causa | Solución |
|---------|-------|----------|
| `vagrant up` termina en timeout | Hyper-V activo: VirtualBox emula y arranca lento | Esperar y correr `vagrant up --provision`, o desactivar el hipervisor (`bcdedit /set hypervisorlaunchtype off` y reiniciar) |
| La API en 8989 no responde | MaxScale no arrancó | `bash scripts/diagnostico.sh` y revisar `resultados/diagnostico.txt` |
| Scripts fallan con `\r: command not found` | El repo se clonó con finales de línea de Windows | `.gitattributes` ya fuerza LF; volver a clonar |
| Se cambió `maxscale.cnf` y no hace efecto | MaxScale lee la configuración al arrancar | `docker compose restart maxscale` |
