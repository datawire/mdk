require 'faraday'

module FaradayMDK
  # Inject the MDK session contest into a request via a HTTP header, and set
  # timeouts based on the MDK session timeout.
  class Session < Faraday::Middleware
    def initialize(app, mdk_session)
      super(app)
      @mdk_session = mdk_session
    end

    def call(request_env)
      request_env[:request_headers]["X-MDK-CONTEXT"] = @mdk_session.externalize
      if @mdk_session.getRemainingTime != nil
        timeout = Integer(@mdk_session.getRemainingTime)
        # Rounding down means 0.99 will end up as 0 second timeout, so set
        # minimum timeout of 1 second:
        if timeout == 0
          timeout = 1
        end
        request_env[:request][:timeout] = timeout
        request_env[:request][:open_timeout] = timeout
      end
      @app.call(request_env)
    end
  end

  Faraday::Request.register_middleware :mdk_session => lambda {Session}
end
