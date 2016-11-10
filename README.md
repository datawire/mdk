The Datawire Microservices Development Kit
=======

The Datawire Microservices Development Kit lets developers code and
test microservices using their native languages and frameworks. The
MDK includes APIs for:

* registering and locating microservices
* distributed logging
* resilient connections (e.g., circuit breakers)

The MDK is currently available in Java, JavaScript, Ruby, and Python
versions.

Quick Start
--------

Visit https://app.datawire.io to create a free Datawire account, and see step-by-step instructions.

Slow Start (for developers)
--------

See
https://datawire.github.io/mdk-docs/latest/main/getting-started/index.html on how to install the MDK from the command line. Currently, there is an implementation dependency on the Datawire cloud services for service discovery. We plan to remove this requirement in the near future. 

Architecture
------------

The MDK is implemented as a series of *protocols*. These protocols are defined in [Quark](https://github.com/datawire/quark). The
Quark transpiler then compiles these protocol definitions into language native MDKs.

Environment Variables
---------------------

The MDK can be configured via environment variables.
The officially supported ones will be described in the [user-facing documentation](https://datawire.github.io/mdk-docs/latest/main/getting-started/index.html), but here is a list of the ones the code currently supports:

* `DATAWIRE_TOKEN`: Authentication token for Mission Control server (or the MCP server set with `MDK_SERVER_URL`, see below).
  If set the MDK will talk to the MCP and send log messages there, as well as using it for discovery.
* `MDK_ENVIRONMENT`: Operational environment to use.
  Services in different environments can't see each other.
  If in the form `<fallback>:<name>` then services not found in `<name>` will be looked up in the `<fallback>` operational environment.
  If not set the environment defaults to `sandbox`.
* `MDK_DISCOVERY_SOURCE`: Discovery source to use, overriding default discovery source set by `DATAWIRE_TOKEN`.
  * A value of `datawire:<token>` is the same as setting `DATAWIRE_TOKEN`.
  * A value of `synapse:path=</path/to/synapse_dir>` will read from Synapse filesystem dump.
  * A value of `static:nodes=<json list of encoded Nodes>` will use the specified `mdk_discovery.Node` instances.
* `MDK_SERVER_URL`: The server to talk to.
  Override to point at local MCP, or at the development server (`wss://mcp-develop.datawire.io/rtp`.)
* `MDK_FAILURE_POLICY` allows overriding the default 3-strikes-and-you're-blacklisted-for-30-seconds circuit breaker policy.
  * A value of `recording` sets a `mdk_discovery.RecordingFailurePolicyFactory`, which useful when writing unit tests.
* `MDK_EXPERIMENTAL`: If set enables experimental features, some of which may be insecure.
* `MDK_LOG_MESSAGES`: If set, e.g. to `1`, sent and received messages will be written out to files at `/tmp/mdk*.log`.
