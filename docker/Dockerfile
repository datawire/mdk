# Use standard quark run as the base
FROM datawire/quark-run

# Add a ton of crap so Twisted can be built...
RUN apk add --update alpine-sdk libffi-dev openssl-dev

# Replace the run script to include --online for quark install
COPY _run-in-docker.py /tmp
RUN chmod +x /tmp/_run-in-docker.py
