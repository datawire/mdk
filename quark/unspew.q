quark 1.0;

use discovery-2.0.q;

import discovery.protocol;

void main(List<String> args) {
    String encoded = args[1];
    print(encoded);
    print(DiscoveryEvent.decode(encoded));
}
