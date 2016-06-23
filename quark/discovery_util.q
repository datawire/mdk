quark 1.0;

package datawire_discovery_util 2.0.0;

import quark.os;

namespace discovery_util {
  @doc("A Supplier has a 'get' method that can return a value to anyone who needs it.")
  interface Supplier<T> {
    
    @doc("Gets a value")
    T get();
     
    /* BUG (compiler) -- Issue # --> https://github.com/datawire/quark/issues/143
    @doc("Gets a value or if null returns the given alternative.")
    T orElseGet(T alternative) 
    {
      T result = get();
      if (result != null) 
      {
        return result;
      }
      else
      {
        return alternative;
      }
    }
    */
  }

  @doc("EnvironmentVariable is a Supplier of Strings that come from the environment.")
  class EnvironmentVariable extends Supplier<String> {
    String variableName;

    EnvironmentVariable(String variableName) {
      self.variableName = variableName;
    }

    bool isDefined() {
      return get() != null;
    }

    String get() {
      return Environment.getEnvironment()[variableName];
    }

    // TODO: Remove once Issue #143 --> https://github.com/datawire/quark/issues/143 is resolved.
    String orElseGet(String alternative) {
      String result = get();
      if (result != null) {
        return result;
      }
      else {
        return alternative;
      }
    }
  }
}
