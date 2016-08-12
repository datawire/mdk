quark 1.0;

package datawire_mdk_synapse 1.0.0;

use discovery-3.0.q;

import mdk_discovery;
import mdk_runtime;
import actors.core;

namespace mdk_synapse {
    @doc("""
    AirBnB Synapse discovery source.

    Reads Synapse-generated files (https://github.com/airbnb/synapse#file) and
    generates discovery events.

    Usage:

        m = mdk.init()
        m.registerDiscoverySource(Synapse('/path/to/synapse/files'))
        m.start()
    """)
    class Synapse extends DiscoverySourceFactory {
        String _directory_path;

        Synapse(String directory_path) {
            self._directory_path = directory_path;
        }

        DiscoverySource create(Actor subscriber, MDKRuntime runtime) {
            return new _SynapseSource(subscriber, self._directory_path, runtime);
        }
    }

    @doc("Implementation of the Synapse discovery source.")
    class _SynapseSource extends DiscoverySource {
        _SynapseSource(Actor subscriber, String directory_path, MDKRuntime runtime) {
        }
    }
}
