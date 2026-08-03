# Commandes Data Pump réutilisables
## 1. Créer le dossier + l'objet DIRECTORY (une seule fois par base)
docker exec oracle-db mkdir -p /opt/oracle/oradata/dpdump
docker exec oracle-db chown oracle:oinstall /opt/oracle/oradata/dpdump
En SQL (sqlplus system/motdepasse@FREEPDB1) :
CREATE OR REPLACE DIRECTORY dpump_dir AS '/opt/oracle/oradata/dpdump';
GRANT READ, WRITE ON DIRECTORY dpump_dir TO nom_schema;
## 2. Export d'un schéma
docker exec oracle-db expdp nom_schema/'motdepasse'@FREEPDB1 directory=dpump_dir dumpfile=export.dmp logfile=export.log schemas=nom_s
## 3. Import dans un autre schéma
docker exec oracle-db impdp nom_schema_cible/'motdepasse'@FREEPDB1 directory=dpump_dir dumpfile=export.dmp logfile=import.log remap_s
## 4. Calculer un quota logique (au lieu de UNLIMITED)
SELECT SUM(bytes)/1024/1024 AS taille_mo FROM dba_segments WHERE owner = 'NOM_SCHEMA';
-- Quota recommandé = taille_mo x 2 (ou x3 si forte croissance attendue)
ALTER USER nom_schema QUOTA [valeur]M ON nom_tablespace;
## 5. Vérifier le succès d'un import
docker exec oracle-db cat /opt/oracle/oradata/dpdump/import.log
-- chercher : "completed with 0 error(s)"
## Rappels importants
- Toujours coller expdp/impdp en UNE SEULE ligne (le retour à la ligne \ casse la commande)
- Le mot de passe du schéma applicatif (créé via APEX) est DIFFÉRENT de ORACLE_PWD (qui ne concerne que SYS/SYSTEM/PDBADMIN)
- table_exists_action=replace écrase les données existantes — à utiliser avec précaution sur un vrai client
