#!/bin/bash
# =============================================================================
# Script exécuté automatiquement par le hook officiel Oracle
# (/opt/oracle/scripts/startup), à chaque démarrage du conteneur, UNE FOIS
# que la base de données est complètement démarrée.
#
# Deux responsabilités distinctes, dans cet ordre :
#   1. Au tout premier démarrage uniquement : installer APEX en base et
#      configurer ORDS (nécessite la base active, donc impossible à faire
#      au moment du `docker build`).
#   2. À CHAQUE démarrage : (re)lancer le processus ORDS, car il ne survit
#      pas à un redémarrage du conteneur (ordre technique, pas un oubli :
#      ORDS est un serveur, pas un service enregistré par l'image Oracle).
#
# IMPORTANT : ce fichier doit être enregistré avec des fins de ligne Unix
# (LF), jamais Windows (CRLF) — un CRLF résiduel casse l'interprétation des
# heredocs bash ci-dessous et provoque une boucle "Password cannot be null"
# (déjà rencontré et documenté pendant la mise au point manuelle).
# =============================================================================
set -e

MARKER=/home/oracle/.setup_done

export JAVA_HOME=/home/oracle/jdk17
export PATH=$JAVA_HOME/bin:$PATH

# -----------------------------------------------------------------------------
# 1. Installation (une seule fois)
# -----------------------------------------------------------------------------
if [ ! -f "$MARKER" ]; then
    echo ">>> Premier démarrage détecté : installation d'APEX et configuration d'ORDS..."

    if [ -z "$APEX_ADMIN_PWD" ] || [ -z "$APEX_PUBLIC_USER_PWD" ]; then
        echo "ERREUR : APEX_ADMIN_PWD et APEX_PUBLIC_USER_PWD doivent être définis (voir .env)." >&2
        exit 1
    fi

    # --- 1.1 Installer APEX dans le PDB ------------------------------------
    cd /home/oracle/apex_install/apex
    sqlplus -s / as sysdba <<SQL
ALTER SESSION SET CONTAINER = FREEPDB1;
@apexins.sql SYSAUX SYSAUX TEMP /i/
EXIT;
SQL

    # --- 1.2 Débloquer et fixer le mot de passe du compte technique --------
    sqlplus -s / as sysdba <<SQL
ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER USER APEX_PUBLIC_USER ACCOUNT UNLOCK;
ALTER USER APEX_PUBLIC_USER IDENTIFIED BY "${APEX_PUBLIC_USER_PWD}";
EXIT;
SQL

    # --- 1.3 Créer le compte web ADMIN d'APEX -------------------------------
    sqlplus -s / as sysdba <<SQL
ALTER SESSION SET CONTAINER = FREEPDB1;
BEGIN
    APEX_UTIL.set_security_group_id( 10 );
    APEX_UTIL.create_user(
        p_user_name       => 'ADMIN',
        p_email_address   => 'me@example.com',
        p_web_password    => '${APEX_ADMIN_PWD}',
        p_developer_privs => 'ADMIN' );
    APEX_UTIL.set_security_group_id( null );
    COMMIT;
END;
/
EXIT;
SQL

    # --- 1.4 Installer et configurer ORDS -----------------------------------
    # Le bloc --password-stdin attend, DANS CET ORDRE, le mot de passe du
    # compte --admin-user (SYS) PUIS celui du compte --gateway-user
    # (APEX_PUBLIC_USER) — ce ne sont PAS deux confirmations d'une même valeur.
    /home/oracle/ords/bin/ords --config /home/oracle/ords_config install \
         --admin-user SYS \
         --db-hostname localhost \
         --db-port 1521 \
         --db-servicename FREEPDB1 \
         --feature-db-api true \
         --feature-rest-enabled-sql true \
         --feature-sdw true \
         --gateway-mode proxied \
         --gateway-user APEX_PUBLIC_USER \
         --password-stdin <<EOT
${ORACLE_PWD}
${APEX_PUBLIC_USER_PWD}
EOT

    /home/oracle/ords/bin/ords --config /home/oracle/ords_config config set standalone.context.path /ords
    /home/oracle/ords/bin/ords --config /home/oracle/ords_config config set standalone.doc.root /home/oracle/ords_config/global/doc_root
    /home/oracle/ords/bin/ords --config /home/oracle/ords_config config set standalone.http.port 8080
    /home/oracle/ords/bin/ords --config /home/oracle/ords_config config set standalone.static.context.path /i
    /home/oracle/ords/bin/ords --config /home/oracle/ords_config config set standalone.static.path /home/oracle/software/apex/images/
    /home/oracle/ords/bin/ords --config /home/oracle/ords_config config set jdbc.InitialLimit 15
    /home/oracle/ords/bin/ords --config /home/oracle/ords_config config set jdbc.MaxLimit 25
    /home/oracle/ords/bin/ords --config /home/oracle/ords_config config set jdbc.MinLimit 15

    touch "$MARKER"
    echo ">>> Installation APEX/ORDS terminée."
else
    echo ">>> Installation déjà effectuée (marqueur $MARKER présent) — passage direct au démarrage d'ORDS."
fi

# -----------------------------------------------------------------------------
# 2. (Re)démarrage d'ORDS — exécuté à CHAQUE démarrage du conteneur
# -----------------------------------------------------------------------------
if ! pgrep -f "ords.war" > /dev/null; then
    cd /home/oracle
    # setsid (pas seulement nohup) + redirection complète des 3 flux :
    # nécessaire pour qu'ORDS survive réellement à la fin de ce script,
    # exécuté par le hook de démarrage Oracle (déjà validé par plusieurs
    # redémarrages consécutifs pendant la mise au point manuelle).
    setsid /home/oracle/ords/bin/ords --config /home/oracle/ords_config serve \
        > /home/oracle/ords.log 2>&1 < /dev/null &
    echo ">>> ORDS lancé en arrière-plan (log : /home/oracle/ords.log)."
else
    echo ">>> ORDS tourne déjà, rien à faire."
fi

exit 0
