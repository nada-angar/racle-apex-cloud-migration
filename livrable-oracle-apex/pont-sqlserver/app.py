import os
from flask import Flask, jsonify
import pyodbc

app = Flask(__name__)


def get_conn_str():
    """Construit la chaîne de connexion ODBC depuis les variables
    d'environnement (fournies via .env / docker-compose), plutôt que
    codées en dur dans le fichier — à adapter une seule fois au lancement,
    pas à chaque modification du code."""
    return (
        "DRIVER={FreeTDS};"
        f"SERVER={os.environ.get('SQLSERVER_HOST', '')};"
        f"PORT={os.environ.get('SQLSERVER_PORT', '1433')};"
        f"DATABASE={os.environ.get('SQLSERVER_DB', '')};"
        f"UID={os.environ.get('SQLSERVER_USER', '')};"
        f"PWD={os.environ.get('SQLSERVER_PWD', '')};"
        "TDS_Version=7.4;"
    )


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


@app.route("/table/<path:nom_table>")
def get_table(nom_table):
    """Endpoint générique de lecture — à restreindre/valider avant un usage
    en production (ici, nom_table est injecté tel quel dans la requête SQL,
    acceptable pour un prototype interne, pas pour un service exposé)."""
    try:
        conn = pyodbc.connect(get_conn_str())
        cursor = conn.cursor()
        cursor.execute(f"SELECT * FROM {nom_table}")
        columns = [col[0] for col in cursor.description]
        rows = [dict(zip(columns, [str(v) for v in row])) for row in cursor.fetchall()]
        conn.close()
        return jsonify(rows)
    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
