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
        request_env[:request][:timeout] = @mdk_session.getRemainingTime
      end
      @app.call(request_env)
    end
  end

  Faraday::Request.register_middleware :mdk_session => lambda {Session}
end
