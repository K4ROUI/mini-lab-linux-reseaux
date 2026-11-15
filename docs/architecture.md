# Architecture technique et flux

Trois *network namespaces* Linux isolés, reliés par deux paires de veth. La création du réseau, le forwarding IPv4 et les règles iptables sont codés dans `scripts/lab.sh` et `scripts/firewall.sh`.

## Interfaces et routes

```text
[irs-lab-client]         [irs-lab-router]               [irs-lab-server]
eth0 10.70.10.10/24 --- lan0 10.70.10.1/24
                         lan1 10.70.20.1/24 ---------- eth0 10.70.20.10/24

client: route 10.70.20.0/24 via 10.70.10.1
server: route 10.70.10.0/24 via 10.70.20.1
router: transfert IPv4 activé uniquement dans son namespace
```

Sans route statique sur le client, les paquets destinés au réseau B n'atteignent pas le serveur. Sans route de retour sur le serveur, la réponse ne revient pas au client. Sans `ip_forward=1`, le noyau du routeur ne transfère pas les paquets entre ses interfaces.

## Chemin d'une requête HTTP autorisée

1. Le client veut joindre `10.70.20.10:8080`, adresse hors de son sous-réseau.
2. Sa route statique lui indique la passerelle `10.70.10.1`.
3. Le routeur reçoit le paquet sur `lan0` et le transfère vers `lan1`.
4. La chaîne iptables `FORWARD` accepte les nouvelles connexions TCP vers le port `8080` du serveur.
5. Le serveur Python répond avec `www/health.txt`.
6. La règle `ESTABLISHED,RELATED` autorise la réponse vers le client.

## DNS

`dnsmasq` écoute sur `10.70.20.10:53` et répond à `service.lab.test` par un enregistrement A `10.70.20.10`. Il ne dispose pas de résolveur externe. Le test envoie directement la question à ce serveur avec `dig @10.70.20.10` ; il **ne modifie pas** `/etc/resolv.conf` du poste hôte.

## Pare-feu du routeur

Politique de base : **DROP** pour le trafic traversant `FORWARD`.

- Autoriser les flux de retour `ESTABLISHED,RELATED`.
- Autoriser ICMP, DNS UDP/TCP 53 et HTTP TCP 8080 du client vers le serveur.
- Ne pas autoriser TCP 9090 depuis le client : le service est pourtant actif sur le serveur.

Les règles se trouvent **dans le namespace du routeur**, et non sur l'hôte. Il ne s'agit pas d'un pare-feu d'entreprise complet.

## Isolation et risques

Les réseaux sont créés dans un noyau Linux commun ; cela **n'offre pas l'isolation d'une VM complète**. Les services de démonstration sont lancés avec des privilèges à l'intérieur du lab et ne conviennent pas à une production. Le script ne crée pas de route vers Internet. Exécuter seulement sur une machine de laboratoire maîtrisée.
