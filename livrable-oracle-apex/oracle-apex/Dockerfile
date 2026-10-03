# =============================================================================
# Dockerfile — Oracle Database Free + APEX + ORDS + unixODBC/FreeTDS
# Reproduit l'environnement validé manuellement sur la VM entreprise.
#
# Contrainte réseau importante (voir docs/ARCHITECTURE.md section 5) :
# les dépôts YUM/DNF Oracle (yum-us-phoenix-1.oracle.com) sont bloqués sur
# la VM cible. Ce Dockerfile n'utilise donc AUCUN `dnf install` pour Java,
# ORDS, unixODBC ou FreeTDS — tout est récupéré par téléchargement direct
# de binaires/archives, depuis des sources non bloquées.
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1 — Récupération des bibliothèques unixODBC manquantes dans l'image
# database/free, depuis une image Oracle Linux 8 complète (multi-stage build,
# remplace le conteneur temporaire manuel utilisé pendant la mise au point).
# -----------------------------------------------------------------------------
FROM oraclelinux:8 AS odbc-libs

RUN dnf install -y unixODBC libtool-ltdl && \
    mkdir -p /out && \
    cp -L /usr/lib64/libodbc.so.2     /out/ && \
    cp -L /usr/lib64/libodbcinst.so.2 /out/ && \
    cp -L /usr/lib64/libodbccr.so.2   /out/ && \
    cp -L /usr/lib64/libltdl.so.7     /out/ && \
    cp -L /usr/bin/isql               /out/

# -----------------------------------------------------------------------------
# Stage 2 — Image finale, construite sur l'image officielle Oracle
# -----------------------------------------------------------------------------
FROM container-registry.oracle.com/database/free:latest

USER root

# --- Java 17 (Eclipse Temurin / Adoptium) ----------------------------------
# Téléchargement direct (api.adoptium.net n'est pas bloqué), pas de `dnf`.
RUN mkdir -p /home/oracle/jdk17 && \
    curl -L -o /tmp/jdk.tar.gz \
      "https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jdk/hotspot/normal/eclipse?project=jdk" && \
    tar -xzf /tmp/jdk.tar.gz -C /home/oracle/jdk17 --strip-components=1 && \
    rm -f /tmp/jdk.tar.gz

# --- ORDS 26.x --------------------------------------------------------------
RUN mkdir -p /home/oracle/ords /home/oracle/ords_config && \
    curl -L -o /tmp/ords.zip https://download.oracle.com/otn_software/java/ords/ords-latest.zip && \
    unzip -oq /tmp/ords.zip -d /home/oracle/ords && \
    rm -f /tmp/ords.zip

# --- APEX : téléchargement et extraction à la construction de l'image ------
# (seule l'INSTALLATION en base, via apexins.sql, doit attendre que la base
#  soit démarrée — voir scripts/01_start_ords.sh. Le téléchargement, lui,
#  ne dépend pas d'une base active et peut donc être figé dans l'image.)
RUN mkdir -p /home/oracle/apex_install /home/oracle/software/apex && \
    curl -L -o /tmp/apex.zip https://download.oracle.com/otn_software/apex/apex-latest.zip && \
    unzip -oq /tmp/apex.zip -d /home/oracle/apex_install && \
    cp -r /home/oracle/apex_install/apex/images /home/oracle/software/apex/images && \
    rm -f /tmp/apex.zip

# --- unixODBC + FreeTDS : paquets .rpm récupérés sur des miroirs publics ---
# (EPEL pour FreeTDS, Rocky Linux pour unixODBC — pas de dépôt Oracle)
WORKDIR /tmp/odbc-install
RUN curl -L -O https://download-ib01.fedoraproject.org/pub/epel/8/Everything/x86_64/Packages/f/freetds-libs-1.5.18-1.el8.x86_64.rpm && \
    curl -L -O https://download-ib01.fedoraproject.org/pub/epel/8/Everything/x86_64/Packages/f/freetds-1.5.18-1.el8.x86_64.rpm && \
    curl -L -O https://download-ib01.fedoraproject.org/pub/epel/8/Everything/x86_64/Packages/f/freetds-devel-1.5.18-1.el8.x86_64.rpm && \
    curl -L -O https://dl.rockylinux.org/pub/rocky/8/AppStream/x86_64/os/Packages/u/unixODBC-2.3.7-2.el8_10.x86_64.rpm && \
    rpm -ivh --nodeps *.rpm && \
    cd / && rm -rf /tmp/odbc-install

# Bibliothèques manquantes, récupérées du stage odbc-libs (remplace les
# `docker cp` manuels depuis un conteneur temporaire)
COPY --from=odbc-libs /out/libodbc.so.2 /out/libodbcinst.so.2 /out/libodbccr.so.2 /out/libltdl.so.7 /usr/lib64/
COPY --from=odbc-libs /out/isql /usr/bin/isql

# Configuration du pilote ODBC et de la source de données SQL Server
# (adapter config/odbc.ini à la vraie adresse du serveur avant le build,
#  ou le fournir via un volume monté au lancement si l'adresse change souvent)
COPY config/odbcinst.ini /etc/odbcinst.ini
COPY config/odbc.ini     /etc/odbc.ini

# --- Scripts exécutés par le hook officiel Oracle au démarrage du conteneur
# (/opt/oracle/scripts/startup est scanné automatiquement par l'image une
#  fois la base de données complètement démarrée)
COPY scripts/01_start_ords.sh /opt/oracle/scripts/startup/01_start_ords.sh

RUN chmod +x /opt/oracle/scripts/startup/01_start_ords.sh && \
    chown -R oracle:oinstall \
      /home/oracle/jdk17 \
      /home/oracle/ords \
      /home/oracle/ords_config \
      /home/oracle/apex_install \
      /home/oracle/software

USER oracle

# Ports : 1521 (SQL), 5500 (EM Express), 8080 (ORDS/APEX HTTP), 8443 (ORDS HTTPS)
EXPOSE 1521 5500 8080 8443
