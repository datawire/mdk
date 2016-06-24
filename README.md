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

Visit http://app.datawire.io for step-by-step instructions.

Slow Start (for developers)
--------

You can also install the MDK from the command line. 

Architecture
------------

The MDK is implemented as a series of *protocols*. These protocols are
formally defined in [Quark](https://github.com/datawire/quark). The
Quark transpiler then compiles these protocol definitions into
language native MDKs.


