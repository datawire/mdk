"""
Flask server that uses MDK's Flask integration and exposes the behavior
expected by test_webframeworks.py.
"""

from flask import g, Flask

from mdk.flask import mdk_setup

app = Flask(__name__)


@app.route("/context")
def context():
    return g.mdk_session.externalize()


if __name__ == '__main__':
    mdk_setup(app)
    app.run(port=9191)
