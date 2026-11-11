#!/usr/bin/env bash
# Exercise 13: Kubernetes Service as a stable name in front of replaceable Pods.
# Uses a local kind cluster (Kubernetes inside Docker).
#   go install sigs.k8s.io/kind@v0.27.0
# The output is saved in docs/salidas/ej13.txt
set -u
export MSYS_NO_PATHCONV=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/docs/salidas/ej13.txt"
CLUSTER="shopresolver"
NS="ecommerce"
cd "$ROOT"
mkdir -p "$(dirname "$OUT")"
: > "$OUT"

run() {
  echo "\$ $*" | tee -a "$OUT"
  "$@" 2>&1 | tee -a "$OUT"
  echo | tee -a "$OUT"
}
note() { echo "$*" | tee -a "$OUT"; }
k() { kubectl --context "kind-$CLUSTER" -n "$NS" "$@"; }

if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  kind create cluster --name "$CLUSTER" --wait 120s
fi

docker compose build -q
kind load docker-image --name "$CLUSTER" shopresolver-inventory-service:latest shopresolver-orders-service:latest >/dev/null

kubectl --context "kind-$CLUSTER" delete namespace "$NS" --ignore-not-found --wait >/dev/null 2>&1
run kubectl --context "kind-$CLUSTER" apply -f k8s/shopresolver.yaml
k rollout status deployment/inventory-service --timeout=180s >/dev/null
k rollout status deployment/orders-service --timeout=180s >/dev/null
k run client --image=busybox:1.36 --restart=Never -- sleep 3600 >/dev/null
k wait --for=condition=Ready pod/client --timeout=120s >/dev/null

note "===== Ejercicio 13 - Kubernetes ====="
echo | tee -a "$OUT"
run k get pods -o wide
run k get service
run k get endpointslices -l kubernetes.io/service-name=inventory-service
run k exec client -- cat /etc/resolv.conf
run k exec client -- nslookup inventory-service.ecommerce.svc.cluster.local
note "--- OrdersService resuelve el nombre: obtiene la ClusterIP del Service, no las IP de los Pods ---"
run k exec client -- wget -qO- http://orders-service:8080/api/orders/resolve
echo | tee -a "$OUT"
note "--- 30 consultas: el Service reparte entre los Pods ---"
for i in $(seq 1 30); do
  k exec client -- wget -qO- http://orders-service:8080/api/orders/inventory/P001; echo
done | sed -E 's/.*"server":"([^"]+)","address":"([^"]+)".*/\1 \2/' | sort | uniq -c | tee -a "$OUT"
echo | tee -a "$OUT"

VICTIM="$(k get pods -l app=inventory-service -o jsonpath='{.items[0].metadata.name}')"
note "--- Se elimina el Pod $VICTIM; el Deployment crea uno nuevo con otra IP ---"
run k delete pod "$VICTIM"
k rollout status deployment/inventory-service --timeout=180s >/dev/null
sleep 3
run k get pods -l app=inventory-service -o wide
run k get endpointslices -l kubernetes.io/service-name=inventory-service
run k get service inventory-service
for i in $(seq 1 30); do
  k exec client -- wget -qO- http://orders-service:8080/api/orders/inventory/P001; echo
done | sed -E 's/.*"server":"([^"]+)","address":"([^"]+)".*/\1 \2/' | sort | uniq -c | tee -a "$OUT"
echo | tee -a "$OUT"

note "Para borrar el cluster: kind delete cluster --name $CLUSTER"
