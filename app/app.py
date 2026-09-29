from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/health')
def health():
    return jsonify(status="healthy"), 200

@app.route('/info')
def info():
    return jsonify(app="devops-portfolio-project", version="1.0"), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001)