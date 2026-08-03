# Socle Oracle Database + APEX — Environnement conteneurisé (PoC)

## 1. Objectif du projet

Ce projet met en place un socle d'infrastructure réutilisable, basé sur **Oracle Database + Oracle APEX**, conteneurisé avec Docker. Il s'inscrit dans une démarche de migration cloud d'applications métier packagées autour de cette même stack technique (Oracle DB + APEX).

L'architecture retenue est **mutualisée** : une seule instance Oracle Database + APEX héberge plusieurs applications, chacune isolée dans son propre **workspace APEX** et son propre **schéma de base de données**. Ce modèle permet de démarrer simplement, tout en restant conforme à une architecture multi-application classique.

Ce dépôt constitue un **Proof of Concept (PoC)**, validé sur un environnement de développement local (WSL2), avant réplication sur l'infrastructure de l'entreprise.

---

## 2. Architecture

```
WSL2 (Ubuntu)
   └── Docker
          ├── Conteneur "oracle-db"    (Oracle Database Free, édition 23ai/26ai)
          └── Conteneur "oracle-ords"  (Oracle REST Data Services + APEX)
                 ↕ communication via réseau Docker interne (hostname: oracle-db)
```

**Modèle applicatif** : une base de données unique, plusieurs workspaces APEX isolés (un par application), chacun avec son propre schéma de base de données dédié.

---

## 3. Stack technique

| Composant | Choix | Justification |
|---|---|---|
| Base de données | `container-registry.oracle.com/database/free:latest` | Version actuelle recommandée par Oracle, remplace l'édition Express (XE), désormais en fin de vie |
| Services applicatifs | `container-registry.oracle.com/database/ords:latest` | ORDS gère l'exposition REST et l'installation d'APEX |
| Interface de développement | Oracle APEX (dernière version stable) | Téléchargée séparément et montée en volume partagé entre les deux conteneurs |
| Orchestration | Docker Compose | 2 conteneurs distincts (DB / ORDS), pour refléter une architecture proche d'un environnement de production |
| Environnement d'exécution | WSL2 (Ubuntu) | Environnement de test léger, sans coût, avant déploiement sur infrastructure cloud dédiée |

---

## 4. Prérequis

- WSL2 avec une distribution Ubuntu installée
- Docker et Docker Compose (`docker.io`, `docker-compose-v2`)
- Un compte sur le [Oracle Container Registry](https://container-registry.oracle.com), avec les licences acceptées pour les images `database/free` et `database/ords`
- Git

---

## 5. Installation

### 5.1. Cloner le dépôt

```bash
git clone <url-du-repo>
cd oracle-project
```

### 5.2. Configurer les variables d'environnement

Créer un fichier `.env` à la racine du projet (non versionné, voir section Sécurité) :

```bash
cat > .env << 'EOF'
ORACLE_PWD=VotreMotDePasse
ORDS_PWD=VotreMotDePasse
APEX_PWD=VotreMotDePasse
EOF
```

### 5.3. Télécharger Oracle APEX

```bash
curl -o apex.zip https://download.oracle.com/otn_software/apex/apex-latest.zip
unzip apex.zip
sudo chown -R 54321:54321 ./apex
```

### 5.4. Authentification au registre Oracle

```bash
docker login container-registry.oracle.com
```

### 5.5. Lancement

```bash
docker compose up -d
```

Suivre le démarrage des deux services :

```bash
docker compose logs -f oracle-db      # attendre "DATABASE IS READY TO USE!"
docker compose logs -f oracle-ords    # attendre "Oracle REST Data Services initialized"
```

### 5.6. Accès à l'interface APEX

```
http://localhost:8181/ords/apex
```

---

## 6. Reprise après interruption (redémarrage machine/service)

Docker ne conserve pas l'état des services actifs après un redémarrage complet de l'environnement WSL2. À chaque nouvelle session :

```bash
sudo service docker start
cd oracle-project
docker compose up -d
docker compose logs -f oracle-db
docker compose logs -f oracle-ords
```

⚠️ Ne jamais interrompre l'environnement (arrêt système, fermeture de session) pendant une installation ou une configuration Oracle DB / APEX en cours. Une interruption à ce stade peut entraîner un état incohérent nécessitant une réinitialisation complète des volumes de données.

---

## 7. Gestion des workspaces et schémas applicatifs

Chaque nouvelle application est isolée dans son propre workspace APEX, associé à un schéma de base de données dédié.

**Création d'un nouveau workspace** (nécessite une connexion administrateur global) :

```
http://localhost:8181/ords/apex/apex_admin
Workspace : INTERNAL
```

Puis : Administration → Manage Workspaces → Create Workspace.

**Bonnes pratiques appliquées** :
- Un schéma dédié par workspace/application (pas de schéma partagé entre applications)
- Un quota de tablespace dimensionné selon le volume réel de données attendu (voir section 9), plutôt qu'un quota illimité par défaut

---

## 8. Migration de données entre schémas (Oracle Data Pump)

L'export d'une application via l'interface APEX (App Builder → Export) ne transfère que la **définition applicative** (pages, logique, composants) — il n'inclut pas les données métier stockées dans les tables.

Pour un transfert complet (structure **et** données), utiliser Oracle Data Pump.

### 8.1. Préparation (à réaliser une fois par base)

```bash
docker exec oracle-db mkdir -p /opt/oracle/oradata/dpdump
docker exec oracle-db chown oracle:oinstall /opt/oracle/oradata/dpdump
```

```sql
CREATE OR REPLACE DIRECTORY dpump_dir AS '/opt/oracle/oradata/dpdump';
GRANT READ, WRITE ON DIRECTORY dpump_dir TO <nom_schema>;
```

### 8.2. Export d'un schéma

```bash
docker exec oracle-db expdp <schema>/'<motdepasse>'@FREEPDB1 \
  directory=dpump_dir dumpfile=export.dmp logfile=export.log schemas=<schema>
```

### 8.3. Import vers un schéma cible

```bash
docker exec oracle-db impdp <schema_cible>/'<motdepasse>'@FREEPDB1 \
  directory=dpump_dir dumpfile=export.dmp logfile=import.log \
  remap_schema=<schema_source>:<schema_cible> table_exists_action=replace
```

### 8.4. Vérification

```bash
docker exec oracle-db cat /opt/oracle/oradata/dpdump/import.log
```

Rechercher la mention `completed with 0 error(s)`.

**Commandes réutilisables détaillées** : voir [`docs/commandes-datapump.md`](docs/commandes-datapump.md)

---

## 9. Gestion des quotas de tablespace

Chaque schéma applicatif dispose d'un quota d'espace de stockage sur le tablespace partagé. Un quota illimité (`UNLIMITED`) n'est pas recommandé en environnement mutualisé : il expose au risque qu'un schéma consomme l'intégralité de l'espace disponible, au détriment des autres applications hébergées sur le même socle.

**Méthode de dimensionnement recommandée** :

1. Mesurer la taille actuelle des données du schéma source :
```sql
SELECT SUM(bytes)/1024/1024 AS taille_mo FROM dba_segments WHERE owner = '<SCHEMA>';
```
2. Appliquer une marge de croissance (recommandation : ×2 à ×3 selon le taux de croissance attendu)
3. Vérifier l'espace disponible cumulé sur le tablespace concerné
4. Fixer un quota explicite :
```sql
ALTER USER <schema> QUOTA <valeur>M ON <tablespace>;
```

---

## 10. Sécurité

- Les identifiants (mots de passe base de données, ORDS, APEX) sont externalisés dans un fichier `.env`, exclu du contrôle de version (voir `.gitignore`)
- Aucune donnée applicative (fichiers `.dmp`, `.log`) n'est versionnée : ces fichiers peuvent contenir des données métier sensibles
- Les volumes de données (`oracle-data/`) sont exclus du dépôt Git : ils sont volumineux, propres à chaque environnement d'exécution, et recréés automatiquement au premier démarrage

---

## 11. Structure du dépôt

```
.
├── docker-compose.yml
├── .env                        (non versionné — à créer localement, voir section 5.2)
├── .gitignore
├── README.md
├── docs/
│   └── commandes-datapump.md
├── apex/                       (non versionné — voir section 5.3)
└── oracle-data/                (non versionné — généré automatiquement)
```

---

## 12. État d'avancement

- [x] Socle Docker Oracle Database + APEX opérationnel
- [x] Persistance des données validée après redémarrage
- [x] Isolation entre workspaces/schémas applicatifs validée
- [x] Procédure d'export/import de schéma (Data Pump) validée et documentée
- [x] Gestion des quotas de tablespace documentée
- [ ] Réplication de l'environnement sur infrastructure de développement/staging entreprise
- [ ] Migration d'une première application client pilote

---

## 13. Prochaines étapes

1. Déploiement de cet environnement sur l'infrastructure de développement/staging fournie par l'entreprise
2. Réception des exports (schéma + application APEX) d'une première application client
3. Application de la procédure d'import documentée en section 8, avec import de l'application via *Import an existing app*
