# Guide de démarrage — Cloner et tester ce projet

Ce document explique comment récupérer ce projet et le faire tourner sur une nouvelle machine (ta VM, ton PC, etc.), en partant de zéro.

---

## 1. Ce que contient ce repo

| Fichier / dossier | Rôle |
|---|---|
| `docker-compose.yml` | Définit les 2 conteneurs Docker : `oracle-db` (Oracle Database Free) et `oracle-ords` (ORDS + APEX) |
| `README.md` | Document de synthèse complet du projet : contexte, choix techniques, étapes réalisées, problèmes rencontrés et solutions |
| `docs/commandes-datapump.md` | Commandes réutilisables pour exporter/importer un schéma Oracle (Data Pump) entre deux environnements |
| `.gitignore` | Liste des fichiers volontairement exclus du repo (voir section 4 ci-dessous, pourquoi) |
| `.env.example` | Modèle de fichier pour les mots de passe — à copier et compléter (voir section 3) |

## 2. Ce que ce repo NE contient PAS (volontairement)

- **Aucune donnée de base de données** (le dossier `oracle-data/` n'est pas versionné) — la base sera recréée neuve au premier lancement
- **Aucun mot de passe réel** (le fichier `.env` n'est pas versionné, seulement un modèle `.env.example`)
- **Aucun fichier APEX** (le dossier `apex/` n'est pas versionné, à retélécharger — voir étape 5 ci-dessous)

C'est un choix volontaire : ce repo contient la **méthode et la configuration**, pas les données. Ça le rend léger, sûr (pas de mot de passe ni de données qui traînent), et reproductible sur n'importe quelle machine.

## 3. Prérequis avant de commencer

- Docker et Docker Compose installés (sur WSL2/Linux, ou Docker Desktop sur Windows/Mac)
- Un compte sur `container-registry.oracle.com` avec les licences acceptées pour les images `database/free` et `database/ords` (gratuit, à créer si pas déjà fait)
- `git` installé

## 4. Étapes pour cloner et lancer le projet

### Étape 1 — Cloner le repo
```bash
git clone <URL_DU_REPO>
cd <nom-du-dossier>
```

### Étape 2 — Se connecter au registre Oracle (une fois)
```bash
docker login container-registry.oracle.com
```
(demande les identifiants du compte créé au préalable — voir prérequis)

### Étape 3 — Créer le fichier de mots de passe
Ce fichier n'est jamais versionné (volontairement, pour la sécurité). Il faut le créer à la main :
```bash
cp .env.example .env
nano .env
```
Remplace les valeurs par défaut par des mots de passe de ton choix (au moins 8 caractères, 1 majuscule, 1 minuscule, 1 chiffre — recommandation Oracle).

### Étape 4 — Télécharger APEX
```bash
curl -o apex.zip https://download.oracle.com/otn_software/apex/apex-latest.zip
unzip apex.zip
sudo chown -R 54321:54321 apex
```
(l'UID 54321 correspond à l'utilisateur `oracle` à l'intérieur des conteneurs — nécessaire pour que les conteneurs puissent lire ces fichiers)

### Étape 5 — Lancer les conteneurs
```bash
docker compose up -d
docker logs -f oracle-db
```
Attendre le message `DATABASE IS READY TO USE!` (peut prendre plusieurs minutes au premier lancement), puis `Ctrl+C` pour sortir du suivi de logs.

```bash
docker logs -f oracle-ords
```
Attendre `Oracle REST Data Services initialized`, puis `Ctrl+C`.

### Étape 6 — Tester l'accès
Dans un navigateur : `http://localhost:8181/ords/apex`

Tu dois arriver sur la page de login APEX. Connecte-toi au workspace `INTERNAL` avec l'utilisateur `ADMIN` et le mot de passe défini dans ton `.env` (variable `APEX_PWD`), pour vérifier l'accès administrateur global.

## 5. Reproduire le test réalisé (validation du socle)

Pour retrouver le même scénario de test que celui documenté dans le `README.md` :

1. Créer un workspace de test (`Administration → Manage Workspaces → Create Workspace`)
2. Dans ce workspace, `App Builder → Install a simple or starter app` → choisir "Sample Workflow, Approvals, and Tasks"
3. Tester le scénario : modifier le salaire d'un employé, faire approuver le changement par un autre rôle
4. Arrêter et relancer les conteneurs (`docker compose restart`) → vérifier que le changement de salaire est toujours présent après redémarrage (validation de la persistance des données)

## 6. Tester l'export/import entre deux environnements (Data Pump)

Voir `docs/commandes-datapump.md` pour les commandes détaillées et réutilisables. Résumé du principe testé :
1. Export d'un schéma source avec `expdp`
2. Import dans un schéma cible avec `impdp` et `remap_schema`
3. Vérification que les données (pas seulement la structure) sont bien arrivées

## 7. En cas de problème

Consulte la section "Problèmes rencontrés et solutions" du `README.md` — elle documente les erreurs déjà rencontrées pendant ce PoC (permissions de volumes, ports mal mappés, quotas de tablespace, mots de passe des schémas applicatifs...) avec leurs solutions précises.

## 8. Arrêter proprement l'environnement

```bash
docker compose down
```
(les données restent dans `oracle-data/`, elles seront retrouvées au prochain `docker compose up -d`)

Pour tout réinitialiser complètement (recommencer de zéro) :
```bash
docker compose down
rm -rf oracle-data/
docker compose up -d
```
