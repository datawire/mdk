module Rack
  module MDK

    class Session
      def initialize(app, params={})
        # Quark runtime has at_exit that stops it... and sinatra only runs via
        # at_exit! So we want to make sure Quark runtime starts *after* sinatra
        # has started. Which is why we only require 'mdk' here:
        require 'mdk'
        @app = app
        @mdk = ::Quark::Mdk.start
        if params[:timeout] != nil
          @mdk.setDefaultDeadline(params[:timeout])
        end
        at_exit do
          @mdk.stop
        end
        yield @mdk if block_given?
      end

      def call(env)
        env[:mdk_session] = @mdk.join(env["HTTP_X_MDK_CONTEXT"])
        env[:mdk_session].start_interaction
        begin
          @app.call(env)
        rescue Exception => e
          env[:mdk_session].fail_interaction(e.message);
          raise
        ensure
          env[:mdk_session].finish_interaction
        end
      end
    end

  end
end
