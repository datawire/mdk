"""
Flask server that uses MDK's Flask integration and exposes the behavior
expected by test_webframeworks.py.
"""

import sys
from json import dumps

from flask import g, request, Flask

from mdk.flask import mdk_setup

app = Flask(__name__)


@app.route("/context")
def context():
    return g.mdk_session.externalize()

@app.route("/resolve")
def resolve():
    node = g.mdk_session.resolve("service1", "1.0")
    # This should be a RecordingFailurePolicy:
    policy = g.mdk_session._mdk._disco.failurePolicy(node)
    result = dumps({node.address: [policy.successes, policy.failures]})
    if request.args.get("error"):
        raise RuntimeError("Erroring as requested.")
    else:
        return result

@app.route("/timeout")
def timeout():
    return dumps(g.mdk_session.getSecondsToTimeout())


if __name__ == '__main__':
    mdk_setup(app, timeout=10.0)
    app.run(port=int(sys.argv[1]))
