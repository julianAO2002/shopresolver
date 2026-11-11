#!/usr/bin/env bash
# Exercises 7, 9, 10 and 11 with the C# services running in Docker Compose.
#  - 7:  logical name vs fixed IP (a second OrdersService configured with the IP)
#  - 9:  docker compose up --build, names, addresses and resolution
#  - 10: recreate the infrastructure and compare the addresses
#  - 11: three instances of inventory-service behind the same name
# The output is saved in docs/salidas/ej07-11.txt
set -u
export MSYS_NO_PATHCONV=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/docs/salidas/ej07-11.txt"
NET="shopresolver_ecommerce-network"
ORDERS="http://localhost:8081"
cd "$ROOT"
mkdir -p "$(dirname "$OUT")"
: > "$OUT"

run() {
  echo "\$ $*" | tee -a "$OUT"
  "$@" 2>&1 | tee -a "$OUT"
  echo | tee -a "$OUT"
}

title() { printf '\n===== %s =====\n\n' "$1" | tee -a "$OUT"; }
note() { echo "$*" | tee -a "$OUT"; }

wait_for() {
  for _ in $(seq 1 60); do
    curl -sf "$1" >/dev/null && return 0
    sleep 1
  done
  note "TIMEOUT esperando $1"
  return 1
}

ips() {
  docker compose ps -q inventory-service | while read -r id; do
    docker inspect -f '{{.Name}} {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$id"
  done
  docker inspect -f '{{.Name}} {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$(docker compose ps -q orders-service)"
}

docker rm -f orders-by-ip filler >/dev/null 2>&1
docker compose down --remove-orphans >/dev/null 2>&1

title "Ejercicio 9 - Docker Compose"
docker compose build -q
run docker compose up -d
wait_for "$ORDERS/health"
run docker compose ps --format 'table {{.Name}}\t{{.Service}}\t{{.Status}}\t{{.Ports}}'
run docker network ls --filter name=ecommerce
note "Direcciones asignadas:"
ips | tee -a "$OUT"
echo | tee -a "$OUT"
run curl -s "$ORDERS/api/orders/resolve"
echo | tee -a "$OUT"
run curl -s "$ORDERS/api/orders/inventory/P001"
echo | tee -a "$OUT"
run curl -s -X POST "$ORDERS/api/orders" -H "content-type: application/json" -d '{"productId":"P001","quantity":2}'
echo | tee -a "$OUT"
run curl -s -w ' [HTTP %{http_code}]' -X POST "$ORDERS/api/orders" -H "content-type: application/json" -d '{"productId":"P003","quantity":1}'
echo | tee -a "$OUT"
run docker compose logs --no-log-prefix orders-service --tail 4

title "Ejercicio 7 - IP directa vs nombre logico"
INV_ID="$(docker compose ps -q inventory-service)"
OLD_IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$INV_ID")"
note "Se levanta un segundo OrdersService (orders-by-ip) configurado con la IP fija http://$OLD_IP:8080"
run docker run -d --name orders-by-ip --network "$NET" -p 8082:8080 -e Inventory__BaseUrl="http://$OLD_IP:8080" shopresolver-orders-service
wait_for "http://localhost:8082/health"
note "--- Con ambas configuraciones funcionando ---"
run curl -s "$ORDERS/api/orders/inventory/P001"
echo | tee -a "$OUT"
run curl -s "http://localhost:8082/api/orders/inventory/P001"
echo | tee -a "$OUT"
note "--- Se recrea inventory-service (filler ocupa la IP liberada, como en el caso 172.18.0.5 -> 172.18.0.9) ---"
run docker compose stop inventory-service
run docker compose rm -f inventory-service
run docker run -d --name filler --network "$NET" alpine sleep infinity
run docker compose up -d inventory-service
sleep 3
NEW_ID="$(docker compose ps -q inventory-service)"
note "IP vieja: $OLD_IP  |  IP nueva: $(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$NEW_ID")  |  filler: $(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' filler)"
echo | tee -a "$OUT"
run curl -s -w ' [HTTP %{http_code}]' "$ORDERS/api/orders/inventory/P001"
echo | tee -a "$OUT"
run curl -s -w ' [HTTP %{http_code}]' "http://localhost:8082/api/orders/inventory/P001"
echo | tee -a "$OUT"
docker rm -f orders-by-ip filler >/dev/null 2>&1

title "Ejercicio 10 - Recrear la infraestructura"
note "--- ANTES ---"
ips | tee -a "$OUT"
run docker network inspect "$NET" --format 'Subnet={{range .IPAM.Config}}{{.Subnet}}{{end}}'
run docker compose down
run docker compose up -d
wait_for "$ORDERS/health"
note "--- DESPUES ---"
ips | tee -a "$OUT"
run docker network inspect "$NET" --format 'Subnet={{range .IPAM.Config}}{{.Subnet}}{{end}}'
run curl -s "$ORDERS/api/orders/resolve"
echo | tee -a "$OUT"
run curl -s "$ORDERS/api/orders/inventory/P002"
echo | tee -a "$OUT"

title "Ejercicio 11 - Multiples instancias"
run docker compose up -d --scale inventory-service=3
sleep 4
run docker compose ps --format 'table {{.Name}}\t{{.Service}}\t{{.Status}}'
note "Direcciones asignadas:"
ips | tee -a "$OUT"
echo | tee -a "$OUT"
run curl -s "$ORDERS/api/orders/resolve"
echo | tee -a "$OUT"
note "--- 12 consultas al mismo nombre http://inventory-service:8080 ---"
for i in $(seq 1 12); do
  curl -s -w '\n' "$ORDERS/api/orders/inventory/P001" | sed -E 's/.*"server":"([^"]+)","address":"([^"]+)".*/\1 \2/' | tee -a "$OUT"
done
echo | tee -a "$OUT"
note "--- Reparto de las consultas por instancia ---"
for i in $(seq 1 30); do
  curl -s -w '\n' "$ORDERS/api/orders/inventory/P001" | sed -E 's/.*"address":"([^"]+)".*/\1/'
done | sort | uniq -c | tee -a "$OUT"
echo | tee -a "$OUT"

note "--- Falla una instancia ---"
VICTIM="$(docker compose ps -q inventory-service | head -n 1)"
run docker stop "$VICTIM"
sleep 2
run curl -s "$ORDERS/api/orders/resolve"
echo | tee -a "$OUT"
for i in $(seq 1 30); do
  curl -s -w ' %{http_code}\n' "$ORDERS/api/orders/inventory/P001" | sed -E 's/.*"address":"([^"]+)".* ([0-9]+)$/\1 HTTP \2/'
done | sort | uniq -c | tee -a "$OUT"
echo | tee -a "$OUT"

run docker compose up -d --scale inventory-service=1
note "Salida guardada en $OUT"
