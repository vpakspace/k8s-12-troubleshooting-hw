#!/usr/bin/env bash
# Проигрывает всё ДЗ с чистого листа и пишет пронумерованные логи в logs/.
# ВНИМАНИЕ: в начале удаляет namespace'ы web и data (только они используются в этом ДЗ).
set -u
cd "$(dirname "$0")/.."
R=scripts/r.sh
URL=https://raw.githubusercontent.com/netology-code/kuber-homeworks/main/3.5/files/task.yaml

# ждём, пока в namespace web останется ровно N Pod'ов (старые Pod'ы с `sh -c` на PID 1 гаснут по SIGKILL через 30 с)
wait_pods() { for _ in $(seq 1 40); do [ "$(kubectl get pods -n web --no-headers 2>/dev/null | wc -l)" = "$1" ] && return; sleep 3; done; }

rm -f logs/*.log
echo ">>> чистый старт"
kubectl delete namespace web data --ignore-not-found --wait=true > /dev/null 2>&1

echo ">>> 00 окружение"
$R 'microk8s kubectl version | grep -i server' 'microk8s ctr version | grep -m1 -A1 Server' 'kubectl get nodes -o wide' > logs/00_env.log

echo ">>> 01 apply из задания"
$R "kubectl apply -f $URL" 'kubectl get namespace web data' > logs/01_apply_error.log

echo ">>> 02 создаём namespace'ы и применяем снова"
$R 'kubectl apply -f manifests/00-namespaces.yaml' "kubectl apply -f $URL" > logs/02_namespaces.log

echo ">>> 03 web-consumer не стартует: образ"
for _ in $(seq 1 30); do
  kubectl get pods -n web -o jsonpath='{.items[*].status.containerStatuses[*].state.waiting.reason}' 2>/dev/null \
    | grep -q -E 'ErrImagePull|ImagePullBackOff' && break; sleep 3; done
$R 'kubectl get pods -n web' 'kubectl get pods -n data' \
   "kubectl get events -n web --field-selector reason=Failed -o custom-columns=REASON:.reason,MESSAGE:.message | grep 'schema 1' | head -1" \
   'scripts/image-manifest.sh radial/busyboxplus curl' \
   'scripts/image-manifest.sh curlimages/curl 8.11.1' > logs/03_image_pull.log

echo ">>> 04 подмена образа"
$R 'kubectl set image deployment/web-consumer -n web busybox=curlimages/curl:8.11.1' \
   'kubectl rollout status deployment/web-consumer -n web --timeout=120s | tail -1' > logs/04_image_swap.log
wait_pods 2
$R 'kubectl get pods -n web' >> logs/04_image_swap.log

echo ">>> 05 симптом"
sleep 12
$R 'kubectl logs -n web deploy/web-consumer --tail=4' > logs/05_symptom.log

echo ">>> 06 диагностика"
$R 'kubectl get deploy -A | grep -E "^NAMESPACE|web-consumer|auth-db"' \
   'kubectl get svc -A | grep -E "^NAMESPACE|auth-db"' \
   'kubectl exec -n web deploy/web-consumer -- cat /etc/resolv.conf' \
   'kubectl exec -n web deploy/web-consumer -- curl -sS -o /dev/null -w "HTTP %{http_code}\n" -m 5 http://auth-db' \
   'kubectl exec -n web deploy/web-consumer -- curl -sS -o /dev/null -w "HTTP %{http_code}\n" -m 5 http://auth-db.data' \
   'kubectl exec -n web deploy/web-consumer -- curl -sS -o /dev/null -w "HTTP %{http_code}\n" -m 5 http://auth-db.data.svc.cluster.local' \
   'IP=$(kubectl get svc auth-db -n data -o jsonpath={.spec.clusterIP}); kubectl exec -n web deploy/web-consumer -- curl -sS -o /dev/null -w "HTTP %{http_code}\n" -m 5 http://$IP' \
   'kubectl exec -n web deploy/web-consumer -- nslookup auth-db.data.svc.cluster.local' \
   'kubectl get svc,endpointslice -n data' \
   'kubectl get pods -n kube-system -l k8s-app=kube-dns' \
   'kubectl get networkpolicy -A' > logs/06_diagnosis.log

echo ">>> 07 исправление"
$R 'diff -u --label task.yaml --label fixed.yaml manifests/task.yaml manifests/fixed.yaml' \
   'kubectl apply -f manifests/fixed.yaml' \
   'kubectl rollout status deployment/web-consumer -n web --timeout=120s | tail -1' > logs/07_fix.log
wait_pods 2
sleep 8

echo ">>> 08 проверка"
$R 'kubectl get deploy web-consumer -n web -o jsonpath="{.spec.template.spec.containers[0].command[2]}{\"\n\"}"' \
   'kubectl get pods -n web -o wide' \
   'kubectl logs -n web deploy/web-consumer --tail=30' \
   'for p in $(kubectl get pods -n web -o name); do echo "$p: ответов nginx = $(kubectl logs -n web $p | grep -c "<title>Welcome to nginx!</title>"), ошибок резолва = $(kubectl logs -n web $p | grep -c "Could not resolve")"; done' > logs/08_verify.log

echo ">>> 09 альтернатива: ExternalName"
$R 'kubectl apply -f manifests/alt-externalname.yaml' 'kubectl get svc -n web' > logs/09_alt_externalname.log
sleep 4
$R 'kubectl exec -n web deploy/web-consumer -- nslookup auth-db.web.svc.cluster.local' \
   'kubectl exec -n web deploy/web-consumer -- curl -sS -o /dev/null -w "HTTP %{http_code}\n" -m 5 http://auth-db' >> logs/09_alt_externalname.log
kubectl delete -f manifests/alt-externalname.yaml > /dev/null 2>&1   # основное решение не должно зависеть от алиаса

echo ">>> 10 особенность: busybox nslookup не расширяет имя «auth-db.data» search-доменами, а curl — расширяет"
$R 'kubectl exec -n web deploy/web-consumer -- nslookup auth-db.data' \
   'kubectl exec -n web deploy/web-consumer -- curl -sS -o /dev/null -w "HTTP %{http_code}\n" -m 5 http://auth-db.data' \
   'kubectl exec -n web deploy/web-consumer -- nslookup auth-db.data.svc.cluster.local' > logs/10_nslookup_quirk.log

echo ">>> готово"
