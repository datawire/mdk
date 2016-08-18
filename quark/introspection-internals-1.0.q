quark 1.0;

/* 
 * Copyright 2016 Datawire. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import quark.os;

use mdk_runtime.q;
import mdk_runtime;  // bring in EnvironmentVariables

namespace mdk_introspection
{
  
  namespace aws
  {
    class Ec2Host extends Supplier<String>
    {
      String scope;
      EnvironmentVariables env;

      Ec2Host(EnvironmentVariables env, String scope) {
        self.scope = scope.toUpper();
        self.env = env;
      }

      static String metadataHost(EnvironmentVariables env) {
        return env.var("DATAWIRE_METADATA_HOST_OVERRIDE").orElseGet("169.254.169.254");
      }

      String get()
      {
        if (scope == "INTERNAL")
        {
          return url_get("http://" + metadataHost(env) + "/latest/meta-data/local-hostname");
        }
        
        if (scope == "PUBLIC")
        {
          return url_get("http://" + metadataHost(env) + "/latest/meta-data/public-hostname");
        }

        return null;
      }
    }
  }

  /* TODO(plombardi): Implement once we have a ComputeEngine account.
  namespace google
  {
    class GoogleComputeEngineHost extends internal.Supplier<String>
    {
      static String METADATA_HOST = "metadata.google.internal";

      String get() 
      {
        return null;
      }
    }
  }
  */
  
  namespace kubernetes
  {
    class KubernetesHost extends Supplier<String>
    {
      String get()
      {
        return null;
      }
    }
    
    class KubernetesPort extends Supplier<int>
    {
      int get()
      {
        return null;
      }
    }
  }
}
