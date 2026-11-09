-- =====================================================================
-- Inicializacion de los ESCLAVOS (solo la primera vez).
-- No se crean usuarios aqui: los usuarios llegan replicados desde el
-- binlog del maestro. Asi los esclavos no tienen transacciones GTID
-- propias ("errant transactions"), requisito para que MaxScale pueda
-- hacer failover sin conflictos.
-- =====================================================================
CHANGE MASTER TO
  MASTER_HOST          = 'mariadb-master',
  MASTER_PORT          = 3306,
  MASTER_USER          = 'repl',
  MASTER_PASSWORD      = 'repl_pass',
  MASTER_USE_GTID      = slave_pos,
  MASTER_CONNECT_RETRY = 5;
-- Los hilos de replicacion arrancan automaticamente cuando inicia el
-- servidor definitivo (el provisionamiento ademas ejecuta START SLAVE).
