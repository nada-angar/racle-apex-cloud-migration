# Pont REST Python — contourne l'absence de DG4ODBC dans Oracle Database Free
# (voir docs/ARCHITECTURE.md section 10). Permet à APEX d'interroger SQL
# Server via un simple appel HTTP (APEX_WEB_SERVICE), sans composant Oracle
# supplémentaire (DG4ODBC n'existe qu'en édition Enterprise / licence séparée).
FROM python:3.11-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        unixodbc unixodbc-dev freetds-dev freetds-bin tdsodbc && \
    rm -rf /var/lib/apt/lists/*

RUN printf '[FreeTDS]\nDescription = FreeTDS Driver\nDriver = /usr/lib/x86_64-linux-gnu/odbc/libtdsodbc.so\n' > /etc/odbcinst.ini

RUN pip install --no-cache-dir flask pyodbc

COPY app.py /app.py

EXPOSE 5000
CMD ["python", "/app.py"]
