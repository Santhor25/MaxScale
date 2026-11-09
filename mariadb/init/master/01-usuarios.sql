-- =====================================================================
-- Inicializacion del MAESTRO (se ejecuta solo la primera vez que se crea
-- el volumen de datos). Todo lo que se hace aqui queda en el binlog y se
-- replica automaticamente a los esclavos.
-- Las contrasenas deben coincidir con lab.env y maxscale/maxscale.cnf
-- =====================================================================

-- 1) Usuario de replicacion (lo usan los esclavos para leer el binlog)
CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED BY 'repl_pass';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';

-- 2) Usuario MONITOR de MaxScale (MariaDB Monitor)
--    Minimo exigido por el enunciado: REPLICATION SLAVE y SUPER.
--    En MariaDB 10.11 SUPER ya no incluye algunos privilegios que
--    mariadbmon necesita para hacer failover/switchover/rejoin, por eso se
--    agregan explicitamente (sin dar acceso a datos de usuario).
CREATE USER IF NOT EXISTS 'maxscale_monitor'@'%' IDENTIFIED BY 'monitor_pass';
GRANT REPLICATION SLAVE, SUPER ON *.* TO 'maxscale_monitor'@'%';
GRANT REPLICATION CLIENT, REPLICATION SLAVE ADMIN, SLAVE MONITOR,
      BINLOG ADMIN, READ_ONLY ADMIN, CONNECTION ADMIN,
      RELOAD, PROCESS, SHOW DATABASES, EVENT
  ON *.* TO 'maxscale_monitor'@'%';

-- 3) Usuario de SERVICIO de MaxScale (carga la lista de usuarios para
--    autenticar a los clientes que se conectan al router)
CREATE USER IF NOT EXISTS 'maxscale'@'%' IDENTIFIED BY 'maxscale_pass';
GRANT SELECT ON mysql.user          TO 'maxscale'@'%';
GRANT SELECT ON mysql.db            TO 'maxscale'@'%';
GRANT SELECT ON mysql.tables_priv   TO 'maxscale'@'%';
GRANT SELECT ON mysql.columns_priv  TO 'maxscale'@'%';
GRANT SELECT ON mysql.procs_priv    TO 'maxscale'@'%';
GRANT SELECT ON mysql.proxies_priv  TO 'maxscale'@'%';
GRANT SELECT ON mysql.roles_mapping TO 'maxscale'@'%';
GRANT SHOW DATABASES ON *.* TO 'maxscale'@'%';

-- 4) Bases de datos de la aplicacion / pruebas
CREATE DATABASE IF NOT EXISTS demo;
CREATE DATABASE IF NOT EXISTS sbtest;

CREATE TABLE IF NOT EXISTS demo.registros (
  id     BIGINT AUTO_INCREMENT PRIMARY KEY,
  nodo   VARCHAR(64) NOT NULL,             -- @@hostname del servidor que ejecuto el INSERT
  creado TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB;

-- 5) Usuario de aplicacion (el que se conecta a traves de MaxScale)
CREATE USER IF NOT EXISTS 'app'@'%' IDENTIFIED BY 'app_pass';
GRANT ALL PRIVILEGES ON demo.*   TO 'app'@'%';
GRANT ALL PRIVILEGES ON sbtest.* TO 'app'@'%';

FLUSH PRIVILEGES;
