# Tester une application sur l'environnement Oracle DB + APEX (Docker)

Document de référence pour importer et tester une application métier sur l'environnement conteneurisé Oracle Database + APEX mis en place dans le cadre du PoC de migration cloud.

---

## Prérequis

- Accès au dépôt Git du projet, environnement de base déjà lancé (voir `GUIDE-DEMARRAGE.md`)
- Fichier d'export de l'application APEX (`.sql`)
- Fichier d'export du schéma de données (`.dmp`, généré via Oracle Data Pump)
- Informations sur l'environnement source (voir section suivante)

---

## Informations nécessaires avant import

- Taille approximative de la base de données (Go)
- Version d'Oracle Database source
- Version d'APEX source
- Dépendances externes de l'application (jobs planifiés, appels à des services externes, liens vers d'autres schémas/bases)
- Statut de confidentialité des données (anonymisation requise ou non pour un test hors environnement de production)

---

## Limites de l'environnement actuel

- Édition utilisée : **Oracle Database Free**
- Capacité maximale : **~12 Go de données utilisateur**
- Ressources maximales allouées : 2 CPU, 2 Go de SGA
- Au-delà de ces limites, l'import échoue ou est incomplet — l'environnement n'est pas dimensionné pour des volumes de production
- Cet environnement est destiné à la validation de méthode, non au traitement de données de production

---

## Étapes d'import d'une application

### 1. Créer un workspace dédié
- Se connecter à l'administration globale : `http://localhost:8181/ords/apex/apex_admin` (workspace `INTERNAL`)
- `Administration → Manage Workspaces → Create Workspace`
- Nom de workspace et schéma dédiés à l'application testée

### 2. Importer l'application APEX
- Dans le workspace créé : `App Builder → Import`
- Sélectionner le fichier `.sql` fourni
- Choisir l'option **"Import an existing app"**
- Suivre l'assistant d'installation

### 3. Importer le schéma de données associé

Copier le fichier d'export dans le conteneur :
```bash
docker cp export_appli.dmp oracle-db:/opt/oracle/oradata/dpdump/
```

Accorder les droits nécessaires sur le répertoire d'échange (connexion `sqlplus system/<mdp>@FREEPDB1`) :
```sql
GRANT READ, WRITE ON DIRECTORY dpump_dir TO <schema_cible>;
```

Importer les données :
```bash
docker exec oracle-db impdp <schema_cible>/'<mdp>'@FREEPDB1 directory=dpump_dir dumpfile=export_appli.dmp logfile=import_appli.log remap_schema=<schema_source>:<schema_cible> table_exists_action=replace
```

Si l'environnement source utilise une version Oracle différente, ajouter le paramètre de compatibilité :
```bash
docker exec oracle-db impdp <schema_cible>/'<mdp>'@FREEPDB1 directory=dpump_dir dumpfile=export_appli.dmp logfile=import_appli.log remap_schema=<schema_source>:<schema_cible> version=<version_cible>
```

### 4. Dimensionner le quota du schéma
```sql
ALTER USER <schema_cible> QUOTA <valeur>M ON <tablespace>;
```
Valeur recommandée : taille du fichier d'export × 2, dans la limite de la capacité disponible (voir section Limites).

---

## Validation post-import

- Application accessible sans erreur dans APEX
- Données présentes dans les tables (vérification du nombre de lignes par rapport à l'environnement source)
- Test d'un scénario métier représentatif de bout en bout
- Persistance vérifiée après redémarrage de l'environnement (`docker compose restart`)

---

## Points de vigilance connus

| Situation | Action |
|---|---|
| Erreur de quota insuffisant (`ORA-01950`) | Ajuster le quota du schéma (voir étape 4) |
| Erreur de compatibilité de version (`ORA-39002`/`ORA-39142`) | Ajouter `version=` à l'import, ou régénérer l'export source avec ce paramètre |
| Table déjà existante dans le schéma cible | Utiliser `table_exists_action=replace` (écrase les données existantes du schéma cible) |
| Volume de données supérieur à la capacité de l'environnement | Se référer à la section Limites — un environnement dimensionné (édition Standard/Enterprise) est nécessaire au-delà |

---

## Remarque sur le choix de l'application à tester

Pour ce test, une application interne non critique et sans données sensibles est recommandée, afin de valider le processus d'import sans contrainte de confidentialité. Le test d'une application client nécessiterait au préalable une anonymisation des données et/ou un environnement dimensionné en conséquence.
