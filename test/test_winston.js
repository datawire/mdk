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
            new (mdk_winston.MDKTransport)({level: level, mdk: mdk, name: "mycategory"})
        ]
    });
    return {mdk: mdk, tracer: tracer, logger: logger};
};

describe("MDKWinstonTarget", function() {
    it("should use session from getMDKSession", function() {
        var o = createMDKwithFakeTracer("info");
        assert.strictEqual(o.tracer.messages.length, 0);
        var session = o.mdk.session();
        cls.namespace.run(function() {
            cls.setMDKSession(session);
            o.logger.info("hello!");
        });
        assert.strictEqual(o.tracer.messages.length, 1);
        assert.strictEqual(o.tracer.messages[0].get("context"),
                           session._context.traceId);
        assert.strictEqual(o.tracer.messages[0].get("text"), "hello!");
        assert.strictEqual(o.tracer.messages[0].get("category"), "mycategory");
    });

    it("should use default session if there is no current session.", function() {
        var o = createMDKwithFakeTracer("info");
        assert.strictEqual(o.tracer.messages.length, 0);
        o.logger.info("hello2");
        assert.strictEqual(o.tracer.messages.length, 1);
        assert.strictEqual(o.tracer.messages[0].get("text"), "hello2");
    });

    it("should map npm-style log levels.", function() {
        var o = createMDKwithFakeTracer("silly");
        o.logger.transports.mycategory.defaultSession.trace("DEBUG");
        o.logger.setLevels(winston.config.npm.levels);
        o.logger.silly("sillyz");
        o.logger.debug("debugz");
        o.logger.verbose("verbosez");
        o.logger.info("infoz");
        o.logger.warn("warnz");
        o.logger.error("errorz");
        assert.deepEqual(
            ["DEBUG", "DEBUG", "DEBUG", "INFO", "WARN", "ERROR"],
            o.tracer.messages.map(m => m.get("level")));
        assert.deepEqual(
            ["sillyz", "debugz", "verbosez", "infoz", "warnz", "errorz"],
            o.tracer.messages.map(m => m.get("text")));
    });

    it("should map syslog-style log levels.", function() {
        var o = createMDKwithFakeTracer("debug");
        o.logger.transports.mycategory.defaultSession.trace("DEBUG");
        o.logger.setLevels(winston.config.syslog.levels);
        o.logger.debug("debugz");
        o.logger.info("infoz");
        o.logger.notice("noticez");
        o.logger.warning("warningz");
        o.logger.error("errorz");
        o.logger.crit("critz");
        o.logger.alert("alertz");
        o.logger.emerg("emergz");
        assert.deepEqual(
            ["DEBUG", "INFO", "INFO", "WARN", "ERROR", "CRITICAL", "CRITICAL",
            "CRITICAL"],
            o.tracer.messages.map(m => m.get("level")));
        assert.deepEqual(
            ["debugz", "infoz", "noticez", "warningz", "errorz", "critz",
             "alertz", "emergz"],
            o.tracer.messages.map(m => m.get("text")));
    });

    it("should have a default name of 'mdk' and default level 'info'.", function() {
        var o = createMDKwithFakeTracer("debug");
        var transport = new (mdk_winston.MDKTransport)({mdk: o.mdk});
        assert.equal(transport.name, 'mdk');
        assert.equal(transport.level, 'info');
    });
});
