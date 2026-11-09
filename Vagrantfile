# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Proyecto 6 - Balanceo de carga de bases de datos con MariaDB MaxScale
# La VM solo actua como host de Docker: TODO el proyecto corre en contenedores
# orquestados con Docker Compose (ver docker-compose.yml).
#
# Uso:
#   vagrant up                                   -> instala Docker, levanta el stack y corre pruebas 01-03
#   vagrant provision --provision-with pruebas   -> corre failover, reintegracion y benchmarks (04-06)
#   vagrant ssh                                  -> entrar a la VM (proyecto en /vagrant)

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"
  config.vm.hostname = "maxscale-lab"
  # En este PC VirtualBox corre sobre Hyper-V (modo NEM) y el arranque es lento
  config.vm.boot_timeout = 900

  # API REST / GUI de MaxScale y listener ReadWriteSplit accesibles desde Windows
  config.vm.network "forwarded_port", guest: 8989, host: 8989, host_ip: "127.0.0.1"
  config.vm.network "forwarded_port", guest: 4006, host: 4006, host_ip: "127.0.0.1"

  # Permisos 644 para que MariaDB/MaxScale no ignoren archivos "world-writable"
  config.vm.synced_folder ".", "/vagrant", mount_options: ["dmode=755", "fmode=644"]

  config.vm.provider "virtualbox" do |vb|
    vb.name   = "p6-maxscale-lab"
    vb.memory = 3072
    # Con Hyper-V activo (modo NEM) 2+ vCPU hacen el arranque extremadamente lento
    vb.cpus   = 1
    # La box ubuntu/jammy64 escribe la consola serie a un archivo; desconectarla acelera el boot
    vb.customize ["modifyvm", :id, "--uartmode1", "disconnected"]
  end

  config.vm.provision "docker", type: "shell", path: "scripts/provision/instalar-docker.sh"
  config.vm.provision "stack",  type: "shell", path: "scripts/provision/levantar-stack.sh"
  config.vm.provision "pruebas", type: "shell", path: "scripts/provision/pruebas-completas.sh", run: "never"
end
