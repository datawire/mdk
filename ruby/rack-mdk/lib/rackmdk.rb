require 'mdk'

module RackMdk

  class MdkSession
    def initialize(app)
      @app = app
      @mdk = ::Quark::Mdk.start
      at_exit do
        @mdk.stop
      end
    end

    def call(env)
      env[:mdk_session] = @mdk.join_session(env["HTTP_X_MDK_CONTEXT"])
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
