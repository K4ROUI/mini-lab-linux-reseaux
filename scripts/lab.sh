#!/usr/bin/env bash
# Laboratoire de routage/dns/HTTP Linux, déployé via network namespaces.
# À exécuter en root sur un environnement de test dédié (Linux/VM/WSL2 compatible).
set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="$BASE_DIR/.runtime"
NS_CLIENT="irs-lab-client"
NS_ROUTER="irs-lab-router"
NS_SERVER="irs-lab-server"
CLIENT_IP="10.70.10.10"
ROUTER_CLIENT_IP="10.70.10.1"
ROUTER_SERVER_IP="10.70.20.1"
SERVER_IP="10.70.20.10"

log() { printf '[lab] %s\n' "$*"; }
fail() { printf '[erreur] %s\n' "$*" >&2; exit 1; }
require_root() { [[ "${EUID:-$(id -u)}" -eq 0 ]] || fail "Utiliser sudo : sudo bash scripts/lab.sh $ACTION"; }
require_command() { command -v "$1" >/dev/null 2>&1 || fail "Commande manquante : $1"; }
ns_exists() { ip netns list | awk '{print $1}' | grep -Fxq "$1"; }
run() { ip netns exec "$1" "${@:2}"; }

stop_lab() {
  # Seuls les noms propres à ce laboratoire sont traités.
  for ns in "$NS_CLIENT" "$NS_ROUTER" "$NS_SERVER"; do
    if ns_exists "$ns"; then
      # Les services et commandes éventuelles dans le namespace sont arrêtés.
      while IFS= read -r pid; do
        [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
      done < <(ip netns pids "$ns" 2>/dev/null)
    fi
  done
  sleep 0.2
  for ns in "$NS_CLIENT" "$NS_ROUTER" "$NS_SERVER"; do
    if ns_exists "$ns"; then
      ip netns del "$ns"
      log "Namespace supprimé : $ns"
    fi
  done
  rm -rf -- "$RUN_DIR"
  log 'Nettoyage terminé.'
}

up_lab() {
  for cmd in ip iptables dnsmasq python3 curl ping dig ss sysctl; do require_command "$cmd"; done
  for ns in "$NS_CLIENT" "$NS_ROUTER" "$NS_SERVER"; do
    if ns_exists "$ns"; then
      fail "Le namespace $ns existe déjà : utiliser 'down' uniquement si ce laboratoire t'appartient."
    fi
  done
  mkdir -p "$RUN_DIR"
  chmod 700 "$RUN_DIR"
  trap 'log "Échec de la création, nettoyage..."; stop_lab' ERR

  for ns in "$NS_CLIENT" "$NS_ROUTER" "$NS_SERVER"; do ip netns add "$ns"; done
  ip link add v-irs-c type veth peer name v-irs-rc
  ip link add v-irs-s type veth peer name v-irs-rs
  ip link set v-irs-c netns "$NS_CLIENT"
  ip link set v-irs-rc netns "$NS_ROUTER"
  ip link set v-irs-s netns "$NS_SERVER"
  ip link set v-irs-rs netns "$NS_ROUTER"

  ip -n "$NS_CLIENT" link set v-irs-c name eth0
  ip -n "$NS_ROUTER" link set v-irs-rc name lan0
  ip -n "$NS_ROUTER" link set v-irs-rs name lan1
  ip -n "$NS_SERVER" link set v-irs-s name eth0

  for ns in "$NS_CLIENT" "$NS_ROUTER" "$NS_SERVER"; do ip -n "$ns" link set lo up; done
  ip -n "$NS_CLIENT" addr add "$CLIENT_IP/24" dev eth0
  ip -n "$NS_ROUTER" addr add "$ROUTER_CLIENT_IP/24" dev lan0
  ip -n "$NS_ROUTER" addr add "$ROUTER_SERVER_IP/24" dev lan1
  ip -n "$NS_SERVER" addr add "$SERVER_IP/24" dev eth0

  ip -n "$NS_CLIENT" link set eth0 up
  ip -n "$NS_ROUTER" link set lan0 up
  ip -n "$NS_ROUTER" link set lan1 up
  ip -n "$NS_SERVER" link set eth0 up

  # Il n'y a pas de route par défaut ni de NAT vers Internet.
  ip -n "$NS_CLIENT" route add 10.70.20.0/24 via "$ROUTER_CLIENT_IP"
  ip -n "$NS_SERVER" route add 10.70.10.0/24 via "$ROUTER_SERVER_IP"
  run "$NS_ROUTER" sysctl -w net.ipv4.ip_forward=1 >/dev/null
  bash "$BASE_DIR/scripts/firewall.sh" "$NS_ROUTER"

  # Services de démonstration. Pas d'exposition sur l'interface publique de l'hôte.
  nohup ip netns exec "$NS_SERVER" dnsmasq --no-daemon \
      --conf-file="$BASE_DIR/config/dnsmasq.conf" \
      >"$RUN_DIR/dnsmasq.log" 2>&1 </dev/null &
  echo "$!" >"$RUN_DIR/dnsmasq.pid"
  nohup ip netns exec "$NS_SERVER" python3 -m http.server 8080 \
      --bind "$SERVER_IP" --directory "$BASE_DIR/www" \
      >"$RUN_DIR/http-8080.log" 2>&1 </dev/null &
  echo "$!" >"$RUN_DIR/http-8080.pid"
  # Port de diagnostic : ouvert localement sur le serveur, mais interdit via le routeur.
  nohup ip netns exec "$NS_SERVER" python3 -m http.server 9090 \
      --bind "$SERVER_IP" --directory "$BASE_DIR/www" \
      >"$RUN_DIR/http-9090.log" 2>&1 </dev/null &
  echo "$!" >"$RUN_DIR/http-9090.pid"

  ready=0
  for _ in $(seq 1 35); do
    if run "$NS_SERVER" curl --silent --fail --max-time 1 "http://$SERVER_IP:8080/health.txt" >/dev/null 2>&1 && \
       run "$NS_SERVER" curl --silent --fail --max-time 1 "http://$SERVER_IP:9090/health.txt" >/dev/null 2>&1 && \
       run "$NS_SERVER" dig +short +time=1 +tries=1 "@$SERVER_IP" service.lab.test A | grep -Fxq "$SERVER_IP"; then
      ready=1
      break
    fi
    sleep 0.2
  done
  [[ "$ready" -eq 1 ]] || fail "Les services n'ont pas démarré : voir les logs dans $RUN_DIR"
  trap - ERR
  log 'Laboratoire en place : client -> routeur -> serveur.'
  log 'Lancer : sudo bash scripts/lab.sh test'
}

test_lab() {
  ns_exists "$NS_CLIENT" && ns_exists "$NS_ROUTER" && ns_exists "$NS_SERVER" || fail 'Laboratoire absent : lancer start'
  log '1/6 Routage IPv4 : ping client -> serveur'
  run "$NS_CLIENT" ping -c 2 -W 2 "$SERVER_IP" >/dev/null
  log '2/6 HTTP autorisé : connexion client -> serveur:8080'
  response="$(run "$NS_CLIENT" curl --silent --show-error --fail --max-time 5 "http://$SERVER_IP:8080/health.txt")"
  [[ "$response" == 'OK - laboratoire Linux et reseaux' ]] || fail "Réponse HTTP inattendue : $response"
  log '3/6 DNS local : résolution du nom service.lab.test'
  dns_result="$(run "$NS_CLIENT" dig +short +time=2 +tries=1 "@$SERVER_IP" service.lab.test A)"
  [[ "$dns_result" == "$SERVER_IP" ]] || fail "Résolution incorrecte : $dns_result"
  log '4/6 Service diagnostic: port 9090 disponible depuis le serveur'
  run "$NS_SERVER" curl --silent --fail --max-time 3 "http://$SERVER_IP:9090/health.txt" >/dev/null
  log '5/6 Pare-feu : HTTP 9090 interdit depuis le client'
  if run "$NS_CLIENT" curl --silent --fail --max-time 3 "http://$SERVER_IP:9090/health.txt" >/dev/null 2>&1; then
    fail 'Erreur : le port 9090 aurait dû être bloqué depuis le client'
  fi
  log '6/6 Vérification du routage et de la politique du pare-feu'
  run "$NS_ROUTER" sysctl -n net.ipv4.ip_forward | grep -Fxq 1
  run "$NS_ROUTER" iptables -S FORWARD | grep -Fq -- '-P FORWARD DROP'
  log 'SUCCÈS : les 6 vérifications d’intégration sont passées.'
}

status_lab() {
  for ns in "$NS_CLIENT" "$NS_ROUTER" "$NS_SERVER"; do
    if ns_exists "$ns"; then
      log "--- $ns ---"
      ip -n "$ns" -br addr
      ip -n "$ns" route show
    else
      log "Namespace absent : $ns"
    fi
  done
  if ns_exists "$NS_ROUTER"; then
    log '--- Compteurs du pare-feu du routeur ---'
    run "$NS_ROUTER" iptables -L FORWARD -n -v
  fi
}

usage() {
  cat <<'HELP'
Usage : sudo bash scripts/lab.sh start|test|status|stop
  start   Créer les 3 namespaces, les routes, le filtrage et les services
  test    Exécuter 6 vérifications réelles du laboratoire
  status  Afficher les interfaces, les routes et le pare-feu
  stop    Arrêter les services et supprimer les namespaces du laboratoire
HELP
}

ACTION="${1:-}"
case "$ACTION" in
  start) require_root; up_lab ;;
  test) require_root; test_lab ;;
  status) require_root; status_lab ;;
  stop) require_root; stop_lab ;;
  *) usage; [[ -z "$ACTION" ]] && exit 0 || exit 2 ;;
esac
