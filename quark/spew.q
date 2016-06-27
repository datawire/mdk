quark 1.0;

use discovery-2.0.q;

import discovery.protocol;

void main(List<String> args) {
    Active event = new Active();
    print(event.encode());
}
