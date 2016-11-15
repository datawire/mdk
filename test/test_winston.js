var assert = require("assert");
var cls = require("datawire_mdk/cls.js");
var winston = require('winston');
var mdk_winston = require("datawire_mdk_winston");
var datawire_mdk = require("datawire_mdk");

function createMDKwithFakeTracer(level) {
    var runtime = datawire_mdk.mdk_runtime.fakeRuntime();
    var tracer = new (datawire_mdk.mdk_tracing.FakeTracer);
    runtime.dependencies.registerService("tracer", tracer);
    runtime.getEnvVarsService().set("MDK_DISCOVERY_SOURCE", "static:nodes={}");
    var mdk = new (datawire_mdk.mdk.MDKImpl)(runtime);
    mdk.start();
    var logger = new (winston.Logger)({
        transports: [
            new (mdk_winston.MDKTransport)({level: level})
        ]
    });
    return {mdk: mdk, tracer: tracer, logger: logger};
};

describe("MDKWinstonTarget", function() {
    it("should use session from getMDKSession", function() {
        var o = createMDKwithFakeTracer("info");
        var session = o.mdk.session();
        cls.namespace.run(function() {
            cls.setMDKSession(session);
            o.logger.info("hello!");
        });
        assert.strictEqual(o.tracer.messages[0].get("context"),
                           session._context.traceId);
    });

    it("should use default session if there is no current session.", function() {
    });

    it("should map npm-style log levels.", function() {
    });

    it("should map syslog-style log levels.", function() {
    });
});
