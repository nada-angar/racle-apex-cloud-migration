# Documentation technique — Architecture et choix de conception

Document de référence : pourquoi chaque choix a été fait, quelles versions sont utilisées, et quels incidents ont été rencontrés (et résolus) pendant la mise au point manuelle avant l'écriture de ce `Dockerfile`.

---

## 1. Vue d'ensemble

```
Conteneur "oracle-apex" (construit via oracle-apex/Dockerfile)
├── Oracle Database 23ai Free   (CDB: FREE, PDB: FREEPDB1)      — ports 1521, 5500
├── APEX 26.1.0                  (workspace INTERNAL, ADMIN)
├── Java 17 (Temurin/Adoptium)   — /home/oracle/jdk17
├── ORDS 26.2                    — /home/oracle/ords              — port 8080 (interne, 8181 côté hôte)
└── unixODBC 2.3.7 + FreeTDS 1.5.18   — pilote vers SQL Server distant

Conteneur "pont-sqlserver" (construit via pont-sqlserver/Dockerfile, séparé)
└── Python 3.11 + Flask + pyodbc  — port 5000 — pont REST vers SQL Server
    (nécessaire car DG4ODBC est absent de l'image Oracle Database Free — voir section 7)
```

## 2. Pourquoi un conteneur unique (et pas deux conteneurs séparés)

Deux architectures étaient possibles : un conteneur dédié par composant (base de données / ORDS), ou tout regrouper. Le regroupement en un seul conteneur a été retenu à la demande explicite de l'infrastructure cible, et validé comme fonctionnellement équivalent : seule l'organisation des processus change, pas les mécanismes Oracle/APEX eux-mêmes.

Une alternative existait : l'image officielle « Autonomous Database Free » (`adb-free`), présentée par Oracle comme solution tout-en-un. Elle a été écartée car fonctionnellement différente (authentification par wallet TLS/mTLS et non par couple utilisateur/mot de passe, limite de 30 sessions simultanées, nécessité de privilèges de conteneur étendus `--cap-add SYS_ADMIN` susceptibles d'être bloqués par une politique de sécurité d'entreprise). L'installation manuelle sur l'image `database/free` classique reste compatible avec les mécanismes Oracle standards (workspaces, Data Pump, quotas).

## 3. Contrainte réseau — pourquoi aucun `dnf install` dans ce Dockerfile

**Constat établi pendant la mise au point manuelle** : les dépôts de paquets Oracle YUM (`yum-us-phoenix-1.oracle.com` et ses miroirs associés) sont bloqués (timeout de connexion) par la politique réseau de l'environnement de déploiement cible, alors que :
- les téléchargements de fichiers directs fonctionnent normalement : `download.oracle.com`, `api.adoptium.net`, `github.com`, les miroirs `fedoraproject.org` et `rockylinux.org`.

**Conséquence directe sur ce `Dockerfile`** : aucune instruction `RUN dnf install` ou `RUN yum install` n'est utilisée pour les composants Java, ORDS, unixODBC ou FreeTDS — tout est récupéré par téléchargement direct de binaires/archives autonomes (tarball, zip, `.rpm` installés avec `rpm -ivh --nodeps`). Cette approche a volontairement été conservée même si le `docker build` est lancé sur une machine où ce blocage ne s'applique pas (ex. poste de développement), pour garantir que l'image reste reconstructible telle quelle sur la VM cible.

## 4. Pourquoi l'installation d'APEX/ORDS reste un script de démarrage (pas une instruction `RUN`)

Un `Dockerfile` exécute ses instructions `RUN` au moment du `docker build`, **avant** qu'un conteneur n'existe et donc avant que la base de données Oracle ne soit démarrée. Or l'installation d'APEX (`apexins.sql`) et la configuration d'ORDS nécessitent une connexion active à l'instance Oracle (`sqlplus / as sysdba`, `ords ... install`).

**Découpage retenu** :
- **Dans le `Dockerfile` (`RUN`, au build)** : tout ce qui ne dépend pas d'une base active — téléchargement et extraction de Java, ORDS, APEX, récupération des paquets ODBC. Ceci fige ces éléments dans l'image et accélère tous les démarrages futurs.
- **Dans `scripts/01_start_ords.sh` (exécuté au runtime, via le hook officiel Oracle `/opt/oracle/scripts/startup/`)** : l'installation d'APEX en base, la configuration d'ORDS, et le lancement du processus ORDS.

Ce script est **idempotent** : un marqueur (`/home/oracle/.setup_done`) garantit que l'installation (étape 1) ne s'exécute qu'au tout premier démarrage du conteneur — les démarrages suivants ne font que relancer ORDS (étape 2), sans retraiter l'installation déjà faite.

## 5. Pourquoi ORDS a besoin d'un script de relance dédié

ORDS est un **serveur** qui doit tourner en continu pour que l'interface web APEX reste accessible — contrairement à la base de données, qui est redémarrée automatiquement par un mécanisme intégré à l'image officielle `database/free`, ORDS est ajouté manuellement et n'a par défaut aucun mécanisme de survie entre deux démarrages du conteneur.

**Points techniques validés pendant la mise au point manuelle, repris dans `01_start_ords.sh`** :
- `setsid` (et pas seulement `nohup`) est nécessaire pour détacher réellement le processus de la session qui le lance.
- La redirection complète des 3 flux (`> log 2>&1 < /dev/null`) évite que le processus se bloque en attendant une entrée standard qui n'arrivera jamais.
- Le test `pgrep -f "ords.war"` évite de lancer un second processus ORDS si un premier tourne déjà (cas d'un redémarrage rapproché).

## 6. Incidents rencontrés pendant la mise au point manuelle (pour référence)

| Problème rencontré | Cause identifiée | Solution appliquée (reprise dans ce livrable) |
|---|---|---|
| Boucle infinie « Password cannot be null » lors de la configuration d'ORDS | Fins de ligne Windows (CRLF) dans les scripts transférés depuis un poste Windows, perturbant l'interprétation des heredocs bash | `.gitattributes` force les fins de ligne Unix (LF) sur tous les `.sh` du dépôt |
| `dnf install` refusé lors des tests manuels | Connexion par défaut sous l'utilisateur applicatif (`oracle`), sans les privilèges nécessaires | Le `Dockerfile` bascule explicitement en `USER root` pour les étapes qui le nécessitent, puis repasse en `USER oracle` en fin de construction |
| `dnf install` échoue avec `Connection timed out` (Java, ORDS, puis unixODBC/FreeTDS) | Blocage réseau volontaire des dépôts Oracle YUM par la politique de sécurité de l'environnement cible | Contournement systématique : récupération de chaque composant en archive autonome depuis des sources alternatives accessibles (voir section 3) |
| ORDS ne redémarre pas automatiquement après un redémarrage du conteneur | Un lancement en arrière-plan classique (`nohup` seul, ou `su -`/`runuser` combiné à un détachement) ne survit pas à la façon dont le hook officiel de démarrage Oracle exécute les scripts | Script dédié `01_start_ords.sh`, utilisant `setsid` avec redirection complète des flux — solution validée par plusieurs redémarrages consécutifs |

Cette table illustre une démarche de diagnostic méthodique : isoler une variable à la fois, formuler une hypothèse, la tester, et revérifier le symptôme après chaque correction plutôt que de supposer qu'elle a réglé le problème.

## 7. SQL Server distant — pourquoi un pont REST plutôt que DG4ODBC natif

Le besoin initial était que l'application Oracle/APEX interroge des données situées sur une base SQL Server distante. Trois mécanismes ont été évalués :

| Option | Sens de communication | Coût | Retenue ? |
|---|---|---|---|
| Database Gateway for ODBC (DG4ODBC) | Oracle interroge SQL Server | Gratuit (en théorie) | Non — voir ci-dessous |
| Database Gateway for SQL Server (DG4MSQL) | Oracle interroge SQL Server | Payant, licence séparée | Non |
| Linked Server côté SQL Server | SQL Server interroge Oracle | Gratuit | Non (mauvais sens pour le besoin exprimé) |

**DG4ODBC a été configuré intégralement** (pilote FreeTDS, DSN ODBC, fichier `initdg4odbc.ora`, alias TNS, service déclaré au listener, `DATABASE LINK` Oracle créé), mais le test final a échoué avec :
```
ORA-28500: connection from ORACLE to a non-Oracle system returned this message:
ORA-02063: preceding line from SQLSERVER_LINK
```

**Cause confirmée** : les exécutables `dg4odbc` et `hsodbc` sont **absents** du répertoire binaire de l'image `database/free` (édition gratuite). Ce n'est pas un défaut de configuration mais une limite de disponibilité produit — Oracle Database Gateway for ODBC n'est distribué qu'avec l'édition Enterprise ou via un produit Oracle séparé sous licence.

**Solution retenue : un pont applicatif REST** (`pont-sqlserver/`). L'application Oracle/APEX, via `APEX_WEB_SERVICE` (capacité native d'APEX pour appeler une URL HTTP et interpréter une réponse JSON), appelle ce service, qui interroge SQL Server via la même chaîne ODBC/FreeTDS déjà validée, et retourne le résultat en JSON. Ce contournement ne remet pas en cause le travail de configuration ODBC (section 8) : seule la couche qui l'exploite change (un service applicatif à la place du gateway Oracle indisponible).

## 8. Tableau récapitulatif des chemins internes

| Élément | Chemin |
|---|---|
| Scripts de démarrage automatique (hook officiel Oracle) | `/opt/oracle/scripts/startup/` |
| Marqueur d'installation déjà faite | `/home/oracle/.setup_done` |
| Java (JDK 17 portable) | `/home/oracle/jdk17/` |
| ORDS (binaires) | `/home/oracle/ords/` |
| ORDS (configuration) | `/home/oracle/ords_config/` |
| Fichiers d'installation APEX (téléchargés au build) | `/home/oracle/apex_install/apex/` |
| Images statiques APEX (servies par ORDS) | `/home/oracle/software/apex/images/` |
| Log ORDS runtime | `/home/oracle/ords.log` |
| Pilote ODBC FreeTDS | `/usr/lib64/libtdsodbc.so` |
| Config pilote ODBC | `/etc/odbcinst.ini` |
| Source de données ODBC (DSN) | `/etc/odbc.ini` |

## 9. Tableau récapitulatif des versions

| Composant | Version |
|---|---|
| Oracle Database | 23.26.0.0.0 (23ai Free) |
| APEX | 26.1.0 |
| ORDS | 26.2 |
| Java | 17 (Eclipse Temurin / Adoptium) |
| unixODBC | 2.3.7 |
| FreeTDS | 1.5.18 |
| Python (pont REST) | 3.11 |
| Flask | 3.1.x |

## 10. Limites connues et points à surveiller

- **Taille de l'image** : le téléchargement d'APEX (~550 Mo) et de Java figés dans l'image via `RUN` augmentent sa taille finale par rapport à l'image `database/free` nue — compromis assumé pour accélérer les démarrages ultérieurs.
- **Adresse du SQL Server distant figée au build** (`oracle-apex/config/odbc.ini`) : si cette adresse change fréquemment, envisager de monter ce fichier en volume au lancement plutôt que de reconstruire l'image à chaque fois.
- **Le pont REST n'est pas sécurisé pour un usage exposé** : `app.py` construit la requête SQL directement à partir du nom de table passé dans l'URL — acceptable pour un usage interne/prototype, à durcir (liste blanche de tables, authentification) avant toute exposition au-delà du réseau Docker interne.
- **Secrets** : aucun mot de passe n'est codé en dur dans les `Dockerfile` — tous sont injectés via `.env` au lancement (`docker compose up`), jamais au moment du `docker build`, pour ne pas apparaître dans l'historique de l'image.
