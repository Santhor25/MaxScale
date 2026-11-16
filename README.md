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
bash scripts/pruebas/09-escalado.sh                # agrega 2 esclavos mas (ver Planes de prueba)
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
| 09 | `09-escalado.sh` | Plan 1: agrega 2 esclavos en caliente y mide el reparto entre 4 réplicas |

Cada script guarda su salida en `resultados/`. Antes de repetir el 04, correr el 05 con
`--switchover` para que `mariadb-master` vuelva a ser el maestro.

## Planes de prueba

Cuatro planes para evaluar el sistema más allá de las pruebas mínimas. Cada uno tiene objetivo,
preparación, pasos, qué medir y criterio de éxito. Se ejecutan desde la raíz del repositorio (con
Vagrant: dentro de `vagrant ssh` y `cd /vagrant`). Antes de cada plan, `server1` debe ser el maestro:

```bash
docker exec maxscale maxctrl call command mariadbmon switchover MariaDB-Monitor server1
docker exec maxscale maxctrl list servers
```

### Plan 1 — Escalado horizontal: más esclavos

**Objetivo:** comprobar que se pueden agregar réplicas sin detener el servicio, que MaxScale las
incorpora en caliente y que las lecturas se reparten entre todos los esclavos.

**Preparación:** el archivo `docker-compose.escalado.yml` define `mariadb-slave3` (puerto 3310) y
`mariadb-slave4` (puerto 3311). Con Vagrant, darle a la VM al menos 4 GB de RAM (`vb.memory`).

**Pasos (automatizado):**

```bash
bash scripts/pruebas/09-escalado.sh
```

El script:
1. Levanta los dos esclavos nuevos con
   `docker compose -f docker-compose.yml -f docker-compose.escalado.yml up -d --wait`.
2. Los registra en MaxScale **sin reiniciarlo ni editar `maxscale.cnf`**:
   `maxctrl create server server4 mariadb-slave3 3306 --services RW-Split-Router --monitors MariaDB-Monitor`.
3. Espera a que copien todo el historial del maestro por GTID y mide cuánto tardan.
4. Ejecuta `07-balanceo.sh` para medir el reparto de lecturas entre los 4 esclavos.

**Qué medir:**

| Métrica | Dónde se ve |
|---|---|
| Tiempo hasta que los nuevos esclavos alcanzan el GTID del maestro | línea `>> Esclavos nuevos sincronizados en …` |
| Rol detectado por MaxScale | `server4` y `server5` como `Slave, Running` |
| Clientes semisíncronos en el maestro | `Rpl_semi_sync_master_clients` = 4 |
| Porcentaje de SELECT por nodo | tabla final de `07-balanceo.sh` |
| TPS de solo lectura con 2 vs. 4 esclavos | `transactions:` en la salida de Sysbench |

**Criterio de éxito:** los 4 esclavos con el mismo GTID que el maestro, ninguna petición de cliente
fallida durante la incorporación, y cada esclavo con alrededor del 25 % de los SELECT (±10 puntos).
En una VM de 1 CPU el TPS no subirá: el plan valida el **reparto**; para validar la **ganancia** de
rendimiento hay que repetirlo con más CPU.

**Variante — failover con 4 esclavos:** con los 5 nodos arriba, ejecutar `04-failover.sh`. MaxScale
debe promover al esclavo más actualizado y reapuntar a los **otros 3**. Comparar el tiempo de failover
con el obtenido con 2 esclavos.

**Limpieza:** `bash scripts/pruebas/09-escalado.sh --quitar` los saca de MaxScale y borra sus
contenedores y volúmenes.

### Plan 2 — Caída de un esclavo bajo carga de lectura

**Objetivo:** demostrar que si cae una réplica, MaxScale la saca del reparto y las lecturas siguen
funcionando en las demás sin errores para el cliente.

**Pasos:**

1. Terminal 1, carga de lectura continua durante 90 s, con reporte cada segundo:
   ```bash
   docker exec sysbench sysbench oltp_read_only --db-driver=mysql --mysql-host=maxscale --mysql-port=4006 \
     --mysql-user=app --mysql-password=app_pass --mysql-db=sbtest --tables=4 --table-size=20000 \
     --threads=16 --time=90 --skip_trx=on --db-ps-mode=disable --report-interval=1 run
   ```
   (Si no existen las tablas `sbtest`, crearlas antes ejecutando `07-balanceo.sh` una vez.)
2. Terminal 2, a los 30 s: `docker stop mariadb-slave2`
3. Terminal 2, a los 60 s: `docker start mariadb-slave2`
4. Al terminar: `docker exec maxscale maxctrl list servers`

**Qué medir:** TPS por segundo antes, durante y después de la caída (salida de la terminal 1);
número de errores (`ignored errors` y `reconnects` en el resumen de Sysbench); segundos hasta que
`server3` vuelve a aparecer como `Slave`.

**Criterio de éxito:** 0 errores fatales en Sysbench; durante la caída todas las lecturas van al
esclavo restante; al volver, `server3` se reincorpora al reparto sin intervención manual.

### Plan 3 — Failover del maestro bajo carga de escritura

**Objetivo:** medir el impacto real de un failover sobre una aplicación que escribe sin parar: cuántos
segundos baja el rendimiento y cuántas transacciones se pierden.

**Pasos:**

1. Terminal 1, carga de lectura/escritura durante 120 s, reporte cada segundo:
   ```bash
   docker exec sysbench sysbench oltp_read_write --db-driver=mysql --mysql-host=maxscale --mysql-port=4006 \
     --mysql-user=app --mysql-password=app_pass --mysql-db=sbtest --tables=4 --table-size=20000 \
     --threads=16 --time=120 --db-ps-mode=disable --report-interval=1 \
     --mysql-ignore-errors=all run | tee resultados/plan3-failover-bajo-carga.txt
   ```
2. Terminal 2, a los 40 s: `docker stop mariadb-master`
3. Terminal 2, a los 80 s: `docker start mariadb-master`

**Qué medir:** el intervalo en segundos en que el TPS cae a 0 o casi 0 (líneas `[ Ns ]` del
reporte); el tiempo hasta que MaxScale muestra un nuevo `Master`; `ignored errors` al final; y el TPS
promedio antes y después del failover.

**Criterio de éxito:** el TPS se recupera en menos de 10 s tras la caída, el nuevo maestro aparece en
la API antes de 5 s, y el maestro original vuelve como `Slave` con el mismo GTID que el resto.
Graficar el TPS por segundo de este archivo es una buena figura para el informe.

### Plan 4 — Persistencia y reinicio completo del clúster

**Objetivo:** comprobar que los datos sobreviven a un apagado total gracias a los volúmenes Docker,
y que al encender todo el clúster recupera la misma topología sin reconfigurar nada.

**Pasos:**

```bash
# 1. Anotar el estado antes
docker exec sysbench mariadb -h maxscale -P 4006 -uapp -papp_pass -N -e "SELECT COUNT(*), MAX(id) FROM demo.registros"
docker exec maxscale maxctrl list servers

# 2. Apagar TODO (sin -v: los volúmenes se conservan)
docker compose down

# 3. Volver a encender
docker compose up -d --wait
sleep 15

# 4. Comparar
docker exec sysbench mariadb -h maxscale -P 4006 -uapp -papp_pass -N -e "SELECT COUNT(*), MAX(id) FROM demo.registros"
docker exec maxscale maxctrl list servers
bash scripts/pruebas/01-verificar-replicacion.sh
```

Con Vagrant, repetir además con la VM completa: `exit`, `vagrant halt`, `vagrant up`, `vagrant ssh`.

**Qué medir:** filas y `MAX(id)` antes y después; GTID de los tres servidores; tiempo desde
`docker compose up` hasta que los tres aparecen como `Running`; que los scripts de inicialización
**no** se vuelvan a ejecutar (los usuarios no se recrean y no hay errores en `docker logs mariadb-master`).

**Criterio de éxito:** mismo número de filas y mismo GTID antes y después; `server1` Master y los
demás Slave sin intervención; replicación `Yes / Yes` en ambos esclavos. Como contraprueba,
`docker compose down -v` sí borra todo y el clúster arranca vacío.

## Estructura del repositorio

```
docker-compose.yml                    5 servicios, volúmenes persistentes y health checks
docker-compose.escalado.yml           2 esclavos extra para el plan de escalado
lab.env                               contraseñas del laboratorio (solo para pruebas)
mariadb/init/master/01-usuarios.sql   usuarios repl, monitor, servicio MaxScale, app + BDs
mariadb/init/slave/01-replica.sql     CHANGE MASTER ... MASTER_USE_GTID=slave_pos
maxscale/maxscale.cnf                 monitor, router y listener (montado como volumen)
sysbench/Dockerfile                   sysbench 1.0 + cliente mariadb
scripts/pruebas/01..09                pruebas del enunciado y planes de prueba
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
