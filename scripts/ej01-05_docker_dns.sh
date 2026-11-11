#!/usr/bin/env bash
# Exercises 1 to 5: Docker network, name resolution with the embedded DNS,
# address change after recreating the container and traditional DNS.
# The output is saved in docs/salidas/ej01-05.txt
set -u
export MSYS_NO_PATHCONV=1   # Git Bash on Windows: do not rewrite /paths

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/docs/salidas/ej01-05.txt"
mkdir -p "$(dirname "$OUT")"
: > "$OUT"

run() {
  echo "\$ $*" | tee -a "$OUT"
  "$@" 2>&1 | tee -a "$OUT"
  echo | tee -a "$OUT"
}

title() { printf '\n===== %s =====\n\n' "$1" | tee -a "$OUT"; }

ip_of() {
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$1"
}

# Clean previous runs and pull the images beforehand (keeps the log readable)
docker pull -q nginx >/dev/null
docker pull -q alpine >/dev/null
docker rm -f inventory-service orders-service filler >/dev/null 2>&1
docker network rm ecommerce-network >/dev/null 2>&1

title "Ejercicio 1 - Crear una red Docker"
run docker network create ecommerce-network
run docker network ls --filter name=ecommerce-network
run docker network inspect ecommerce-network --format 'Name={{.Name}} Driver={{.Driver}} Subnet={{range .IPAM.Config}}{{.Subnet}}{{end}} Gateway={{range .IPAM.Config}}{{.Gateway}}{{end}}'

title "Ejercicio 2 - Crear el servicio de inventario"
run docker run -d --name inventory-service --network ecommerce-network nginx
run docker ps --filter name=inventory-service --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
run docker inspect inventory-service --format 'Name={{.Name}} State={{.State.Status}} Networks={{range $k, $v := .NetworkSettings.Networks}}{{$k}} IP={{$v.IPAddress}} MAC={{$v.MacAddress}} DNSNames={{$v.DNSNames}}{{end}}'
IP_BEFORE="$(ip_of inventory-service)"

title "Ejercicio 3 - Crear un cliente"
# The PDF uses "docker run -it ... alpine"; here it runs detached so the
# commands can be executed non-interactively with docker exec.
run docker run -d --name orders-service --network ecommerce-network alpine sleep infinity
docker exec orders-service apk add --no-cache bind-tools curl >/dev/null 2>&1
run docker exec orders-service cat /etc/resolv.conf
run docker exec orders-service ping -c 3 inventory-service
run docker exec orders-service nslookup inventory-service
run docker exec orders-service getent hosts inventory-service
run docker exec orders-service sh -c "curl -s -o /dev/null -w 'HTTP %{http_code} desde %{remote_ip}\n' http://inventory-service"

title "Ejercicio 4 - Cambio de direccion"
echo "IP de inventory-service ANTES: $IP_BEFORE" | tee -a "$OUT"
run docker stop inventory-service
run docker rm inventory-service
# A container that takes the freed address, so the new inventory-service
# gets a different one (like the 172.18.0.5 -> 172.18.0.9 case of the PDF).
run docker run -d --name filler --network ecommerce-network alpine sleep infinity
run docker run -d --name inventory-service --network ecommerce-network nginx
IP_AFTER="$(ip_of inventory-service)"
run docker inspect inventory-service --format 'Name={{.Name}} State={{.State.Status}} IP={{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
echo "IP de inventory-service DESPUES: $IP_AFTER" | tee -a "$OUT"
echo "IP de filler (ocupa la direccion anterior): $(ip_of filler)" | tee -a "$OUT"
echo | tee -a "$OUT"
run docker exec orders-service nslookup inventory-service
run docker exec orders-service sh -c "curl -s -o /dev/null -w 'HTTP %{http_code} desde %{remote_ip}\n' http://inventory-service"
run docker exec orders-service sh -c "curl -s -m 3 -o /dev/null -w 'HTTP %{http_code} desde %{remote_ip}\n' http://$IP_BEFORE || echo 'La IP vieja $IP_BEFORE ya no corresponde a inventory-service'"

title "Ejercicio 5 - DNS tradicional"
run docker exec orders-service nslookup www.google.com
run docker exec orders-service dig +noall +answer +stats www.google.com
run docker exec orders-service dig +noall +answer inventory-service
run docker exec orders-service sh -c "dig @8.8.8.8 inventory-service +noall +comments | grep status"

# Clean up so docker compose can reuse the names
docker rm -f inventory-service orders-service filler >/dev/null 2>&1
docker network rm ecommerce-network >/dev/null 2>&1
echo "Salida guardada en $OUT"
