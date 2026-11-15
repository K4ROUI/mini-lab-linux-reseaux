#!/usr/bin/env bash
set -Eeuo pipefail

NS="${1:?Fournir le nom du namespace du routeur}"
# Le routeur est dans son propre namespace réseau : aucune règle n'est ajoutée au pare-feu de l'hôte.
ip netns exec "$NS" iptables -P FORWARD DROP
ip netns exec "$NS" iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
# ICMP du client vers le serveur pour le diagnostic.
ip netns exec "$NS" iptables -A FORWARD -s 10.70.10.10 -d 10.70.20.10 -p icmp -j ACCEPT
# DNS depuis le client vers le serveur.
ip netns exec "$NS" iptables -A FORWARD -s 10.70.10.10 -d 10.70.20.10 -p udp --dport 53 -j ACCEPT
ip netns exec "$NS" iptables -A FORWARD -s 10.70.10.10 -d 10.70.20.10 -p tcp --dport 53 -j ACCEPT
# Service HTTP autorisé ; le port 9090 reste bloqué par la politique DROP.
ip netns exec "$NS" iptables -A FORWARD -s 10.70.10.10 -d 10.70.20.10 -p tcp --dport 8080 -j ACCEPT
