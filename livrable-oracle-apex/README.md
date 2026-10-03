# Infrastructure Oracle Database + APEX + ORDS + SQL Server (DG4ODBC via pont REST)

Dossier livrable permettant de reconstruire, de façon automatisée et reproductible, l'environnement validé manuellement sur la VM entreprise : un conteneur unique Oracle DB + APEX + ORDS, plus un conteneur annexe faisant office de pont vers un SQL Server distant.

Ce dossier remplace la méthode manuelle initiale (`docker create` + copie de scripts après coup) par deux `Dockerfile` et un `docker-compose.yml`, pour un déploiement en une seule commande.

---

## 1. Contenu du dossier

```
.
├── docker-compose.yml          # Orchestration des deux conteneurs
├── .env.example                 # Modèle de fichier de mots de passe (à copier en .env)
├── .gitignore
├── .gitattributes                # Force les fins de ligne Unix sur les .sh
├── oracle-apex/
│   ├── Dockerfile                # Image DB + APEX + ORDS + ODBC/FreeTDS
│   ├── scripts/
│   │   └── 01_start_ords.sh      # Installation (1ère fois) + démarrage ORDS (à chaque fois)
│   └── config/
│       ├── odbcinst.ini          # Déclaration du pilote FreeTDS
│       └── odbc.ini              # DSN vers le SQL Server distant (À ADAPTER)
├── pont-sqlserver/
│   ├── Dockerfile                 # Image du pont REST (Python/Flask/pyodbc)
│   └── app.py
└── docs/
    └── ARCHITECTURE.md            # Détail technique complet, versions, incidents rencontrés
```

## 2. Prérequis

- Docker + Docker Compose (Docker Desktop avec backend WSL2 si déploiement sur Windows Server, comme c'est le cas sur la VM entreprise)
- Accès réseau sortant vers : `download.oracle.com`, `api.adoptium.net`, `download-ib01.fedoraproject.org`, `dl.rockylinux.org`, et le registre Docker Hub (pour l'image `oraclelinux:8` et `python:3.11-slim`)
- **Aucun accès requis** aux dépôts `yum.oracle.com` — volontairement évités dans ce Dockerfile (voir `docs/ARCHITECTURE.md`, section 5)
- Licence Oracle acceptée sur [container-registry.oracle.com](https://container-registry.oracle.com) pour l'image `database/free`, et authentification (`docker login container-registry.oracle.com`) avant le build

## 3. Installation — étapes

### 3.1 Configurer les secrets

```bash
cp .env.example .env
```

Éditer `.env` et remplacer toutes les valeurs par défaut (mots de passe Oracle + informations de connexion au SQL Server distant).

### 3.2 Adapter la configuration ODBC (si connexion SQL Server nécessaire dès le départ)

Éditer `oracle-apex/config/odbc.ini` et remplacer `CHANGEZ_MOI_adresse_sql_server` et `CHANGEZ_MOI_nom_base` par les vraies valeurs. Si l'adresse du SQL Server est amenée à changer souvent, il est possible de monter ce fichier en volume au lancement plutôt que de le figer dans l'image (non fait par défaut ici, pour rester simple).

### 3.3 S'authentifier au registre Oracle (une fois par machine)

```bash
docker login container-registry.oracle.com
```

### 3.4 Construire et lancer

```bash
docker compose up -d --build
```

Premier build : compter 10 à 20 minutes (téléchargement de Java, ORDS, APEX — environ 600 Mo au total). Les builds suivants sont bien plus rapides grâce au cache Docker, tant que les fichiers correspondants ne changent pas.

Premier démarrage du conteneur `oracle-apex` : compter encore quelques minutes supplémentaires — c'est à ce moment que `01_start_ords.sh` installe réellement APEX en base et configure ORDS (voir `docs/ARCHITECTURE.md` section 4, cette étape ne peut pas être faite pendant le `docker build` : elle nécessite une base de données active).

### 3.5 Suivre le démarrage

```bash
docker compose logs -f oracle-apex
```

Attendre dans l'ordre : `DATABASE IS READY TO USE!`, puis les messages du script `01_start_ords.sh` (`>>> Installation APEX/ORDS terminée.`, `>>> ORDS lancé en arrière-plan`).

## 4. Vérifications post-déploiement

| Vérification | Commande |
|---|---|
| Conteneurs actifs | `docker compose ps` |
| Base de données répond | `docker exec -it oracle-apex sqlplus system/"$ORACLE_PWD"@FREEPDB1` |
| ORDS répond | `docker exec oracle-apex curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/ords/` (attendu : `200` ou `301`) |
| Interface web APEX | `http://<adresse_du_serveur>:8181/ords/apex` — workspace `INTERNAL`, utilisateur `ADMIN`, mot de passe = `APEX_ADMIN_PWD` du `.env` |
| Pont REST SQL Server | `curl http://localhost:5000/health` → `{"status":"ok"}` |
| Lecture d'une table SQL Server via le pont | `curl http://localhost:5000/table/<nom_table>` |

## 5. Redémarrage (après coupure de la VM, de Docker Desktop, etc.)

```bash
docker compose up -d
```

(pas besoin de `--build` si les fichiers n'ont pas changé). `01_start_ords.sh` relance automatiquement ORDS à chaque démarrage, sans réinstaller APEX (grâce au marqueur `/home/oracle/.setup_done`), grâce au mécanisme déjà validé manuellement.

## 6. Pour tout repartir de zéro

```bash
docker compose down
docker volume rm livrable-oracle-apex_oracle-data
docker compose up -d --build
```

⚠️ Ceci supprime définitivement les données de la base (workspaces, applications, données clientes importées).

## 7. Documentation technique complète

Voir [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) pour : le détail de chaque composant, les versions exactes, les chemins internes, les incidents rencontrés pendant la mise au point manuelle et leurs résolutions, ainsi que les limites connues (notamment l'indisponibilité de DG4ODBC dans Oracle Database Free, qui justifie le pont REST).
