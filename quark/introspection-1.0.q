quark 1.0;

package datawire_mdk_introspection 1.0.0;

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

use util-1.0.q;
include introspection-internals-1.0.q;

import mdk_util;  // bring in EnvironmentVariable

namespace mdk_introspection 
{

  // XXX: How should this relate to Datawire Connect's DatawireState class?
  class DatawireToken
  {

    static String TOKEN_VARIABLE_NAME = "DATAWIRE_TOKEN";
  
    @doc("Returns the Datawire Access Token by reading the environment variable DATAWIRE_TOKEN.")
    static String getToken()
    {
        String token = EnvironmentVariable(TOKEN_VARIABLE_NAME).get();
        if (token == null)
        {
            concurrent.Context.runtime().fail("Environment variable 'DATAWIRE_TOKEN' is not set.");
        }

        return token;
    }
  }

  class Platform 
  {
    static Logger logger = new Logger("Platform");

    static String PLATFORM_TYPE_VARIABLE_NAME    = "DATAWIRE_PLATFORM_TYPE";

    static String PLATFORM_TYPE_EC2              = "EC2";
    static String PLATFORM_TYPE_GOOGLE_COMPUTE   = "GOOGLE_COMPUTE";
    static String PLATFORM_TYPE_GOOGLE_CONTAINER = "GOOGLE_CONTAINER";
    static String PLATFORM_TYPE_KUBERNETES       = "Kubernetes";
    static String ROUTABLE_HOST_VARIABLE_NAME    = "DATAWIRE_ROUTABLE_HOST";
    static String ROUTABLE_PORT_VARIABLE_NAME    = "DATAWIRE_ROUTABLE_PORT";

    static String platformType()
    {
      String result = EnvironmentVariable(PLATFORM_TYPE_VARIABLE_NAME).get();
      if (result != null)
      {
        result = result.toUpper();
      }

      return result;
    }

    @doc("Returns the routable hostname or IP for this service instance.")
    @doc("This method always returns the value of the environment variable DATAWIRE_ROUTABLE_HOST if it is defined.")
    static String getRoutableHost()
    {
      String result = null;

      if (EnvironmentVariable(ROUTABLE_HOST_VARIABLE_NAME).isDefined())
      {
        logger.debug("Using value in environment variable '" + ROUTABLE_HOST_VARIABLE_NAME + "'");
        result = EnvironmentVariable(ROUTABLE_HOST_VARIABLE_NAME).get();
      }
      else
      {
        if (platformType() == null)
        {
          logger.error("Platform type not specified in environment variable '" + PLATFORM_TYPE_VARIABLE_NAME + "'");
          concurrent.Context.runtime().fail("Environment variable 'DATAWIRE_PLATFORM_TYPE' is not set.");
        }

        if (platformType().startsWith(PLATFORM_TYPE_EC2))
        {
          logger.debug(PLATFORM_TYPE_VARIABLE_NAME + " = EC2");

          List<String> parts = platformType().split(":");
          logger.debug("Platform Scope = " + parts[1]);

          if(parts.size() == 2)
          {
            return aws.Ec2Host(parts[1]).get();
          }
          else
          {
            logger.error("Invalid format for '" + PLATFORM_TYPE_VARIABLE_NAME + "' starting with 'ec2'. Expected (ec2:<scope>)");
            concurrent.Context.runtime().fail("Invalid format for DATAWIRE_PLATFORM_TYPE == EC2. Expected EC2:<scope>.");
          }
        }

        /* [ !!! ] This code isn't really useful because Kubernetes doesn't inject any specific information into the container
           that can be used easily. K8s users should expect to do it through the DATAWIRE_ROUTABLE_HOST and
           DATAWIRE_ROUTABLE_PORT environment variables.

        if (platformType() == PLATFORM_TYPE_KUBERNETES || platformType() == PLATFORM_TYPE_GOOGLE_CONTAINER)
        {
          logger.debug(PLATFORM_TYPE_VARIABLE_NAME + " = [" + PLATFORM_TYPE_KUBERNETES  + "|" + PLATFORM_TYPE_GOOGLE_CONTAINER + "]");
          return KubernetesHost().get();
        }

*/
      }
      
      return result;
    }

    @doc("Returns the routable port number for this service instance or uses the provided port if a value cannot be resolved.")
    @doc("This method always returns the value of the environment variable DATAWIRE_ROUTABLE_PORT if it is defined.")
    static int getRoutablePort(int servicePort)
    {
      if (EnvironmentVariable(ROUTABLE_PORT_VARIABLE_NAME).isDefined())
      {
        return parseInt(EnvironmentVariable(ROUTABLE_PORT_VARIABLE_NAME).get());
      }

      if (platformType() == PLATFORM_TYPE_KUBERNETES)
      {
        return kubernetes.KubernetesPort().get();
      }
      
      return servicePort;
    }
  }
}
