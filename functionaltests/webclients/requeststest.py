import sys

from mdk import start
from mdk.requests import requests_session

from requests.exceptions import Timeout

def main():
    url = sys.argv[1]
    mdk = start()
    session = mdk.session()
    session.setDeadline(1.0)
    mdk.stop()
    req_ssn = requests_session(session)
    try:
        req_ssn.get(url).content
    except Timeout:
        sys.exit(123)
        return

main()
