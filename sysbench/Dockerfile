# Contenedor cliente: Sysbench 1.0 + cliente MariaDB para pruebas y benchmarks
FROM ubuntu:22.04
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      sysbench mariadb-client ca-certificates \
 && rm -rf /var/lib/apt/lists/*
CMD ["sleep", "infinity"]
