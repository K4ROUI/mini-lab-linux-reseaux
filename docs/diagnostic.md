# Diagnostic réseau : méthodologie et scénarios

Avant tout : `sudo bash scripts/lab.sh start`. Les commandes qui suivent s'exécutent depuis **l'hôte Linux** et ciblent explicitement les namespaces du lab.

## 1. Vérifier les interfaces et la passerelle

```bash
sudo ip -n irs-lab-client -br address
sudo ip -n irs-lab-client route show
sudo ip -n irs-lab-router -br address
sudo ip -n irs-lab-server route show
```

Attendu : client en `10.70.10.10/24`, serveur en `10.70.20.10/24`, route via `.1` de chaque côté.

## 2. Contrôler la connectivité IP

```bash
sudo ip netns exec irs-lab-client ping -c 3 -W 2 10.70.10.1
sudo ip netns exec irs-lab-client ping -c 3 -W 2 10.70.20.10
```

Si la première commande échoue, examiner `eth0`, `lan0` et leurs adresses. Si la première réussit mais pas la seconde, regarder **le routage**, `ip_forward` et les règles du pare-feu.

## 3. Examiner DNS et HTTP

```bash
sudo ip netns exec irs-lab-client dig @10.70.20.10 service.lab.test A +short
sudo ip netns exec irs-lab-client curl -v --max-time 5 http://10.70.20.10:8080/health.txt
sudo ip netns exec irs-lab-server ss -lntu
```

DNS et HTTP sont deux tests distincts : un ping réussi ne suffit pas à garantir que l'application répond.

## 4. Vérifier le filtrage

```bash
sudo ip netns exec irs-lab-router iptables -L FORWARD -n -v
sudo ip netns exec irs-lab-client curl --max-time 3 http://10.70.20.10:9090/health.txt
sudo ip netns exec irs-lab-server curl --max-time 3 http://10.70.20.10:9090/health.txt
```

Interprétation attendue : HTTP 9090 marche dans le namespace serveur, **mais pas depuis le client**, car le routeur laisse seulement passer les ports prévus. Le refus depuis le client n'est donc pas la preuve que le service est arrêté.

## 5. Analyser un incident sans inventer de résultats

**Scénario à reproduire dans un environnement jetable :** après une réussite des six tests, regarder l'effet d'une route absente, puis la rétablir.

```bash
sudo ip -n irs-lab-client route del 10.70.20.0/24
sudo ip netns exec irs-lab-client ping -c 2 -W 2 10.70.20.10
sudo ip -n irs-lab-client route add 10.70.20.0/24 via 10.70.10.1
sudo bash scripts/lab.sh test
```

Les commandes créent **volontairement** un incident temporaire dans le lab ; la dernière commande confirme sa résolution. Les captures, compteurs et journaux doivent provenir de votre exécution réelle. Ne pas présenter ces étapes comme déjà réalisées sans les exécuter.

## 6. Analyser les journaux

Une fois le lab en place, les services enregistrent leurs sorties dans `.runtime/` : `dnsmasq.log`, `http-8080.log`, `http-9090.log`. Ces fichiers ne sont pas versionnés. Ils sont supprimés avec `sudo bash scripts/lab.sh stop`.

## 7. Nettoyer

```bash
sudo bash scripts/lab.sh stop
```

Ne supprimer aucun namespace ne portant pas le préfixe explicite de ce laboratoire.
