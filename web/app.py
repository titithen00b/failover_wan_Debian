from flask import Flask, render_template
import json
import os

app = Flask(__name__)

@app.route('/')
def index():
    # Lire l'état courant
    with open('/opt/failover/state.json') as f:
        state = json.load(f)

    # Lire les derniers logs
    log_path = '/opt/failover/logs/failover.log'
    if os.path.exists(log_path):
        with open(log_path, 'r') as f:
            lines = f.readlines()[-10:]
    else:
        lines = ["Aucun log trouvé."]

    return render_template(
        'index.html',
        status=state.get("mode", "inconnu"),
        data_used=state.get("data_used", "0 B"),
        last_event=lines[-1] if lines else "Aucun",
        log=''.join(lines)
    )

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
