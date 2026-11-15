# Protocole de validation et résultats

## État des validations

- **Contrôles statiques** : les fichiers peuvent être vérifiés sans droits élevés (`python3 -m unittest ...` et `bash -n ...`).
- **Intégration réelle** : à effectuer sur une VM Linux ou, après publication, sur un runner Ubuntu GitHub Actions. Le succès n'est **pas** revendiqué avant exécution.
- **Performances** : aucune mesure de débit, latence ou temps de démarrage n'est revendiquée.

## Plan de tests fonctionnels

| N° | Test | Résultat attendu | Résultat observé |
| --- | --- | --- | --- |
| 1 | Ping de client vers serveur | Réponse ICMP | À exécuter |
| 2 | GET HTTP sur 8080 | Réponse `OK ...` | À exécuter |
| 3 | DNS du nom `service.lab.test` | `10.70.20.10` | À exécuter |
| 4 | HTTP sur 9090 depuis le serveur | Accessible | À exécuter |
| 5 | HTTP sur 9090 depuis le client | Bloqué | À exécuter |
| 6 | IP forwarding + politique firewall | Forwarding actif, politique DROP | À exécuter |

Exécuter :

```bash
sudo bash scripts/lab.sh start
sudo bash scripts/lab.sh test
sudo bash scripts/lab.sh status
sudo bash scripts/lab.sh stop
```

Consigner les sorties exactes du terminal ou de GitHub Actions si elles sont publiables.

## Limites

- **Network namespaces**, pas des VM ni des postes physiques distincts.
- Routage **statique IPv4** uniquement, sans OSPF.
- DNS local minimal, sans service DNS récursif vers Internet.
- Pare-feu pédagogique `iptables` : pas de haute disponibilité, de supervision centralisée ou de segmentation d'entreprise.
- Service HTTP Python de test : **aucune exposition publique**, aucune authentification ; ce n'est pas un serveur de production.
- Les tests couvrent les scénarios attendus, pas toutes les erreurs possibles.
