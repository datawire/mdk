var util = require("util");
var winston = require("winston");
var cls = require("datawire_mdk/cls.js");

// Map Winston levels to MDK log levels:
exports.levelMapping = {
    "silly": "debug",
    "debug": "debug",
    "verbose": "debug",
    "info": "info",
    "warn": "warn",
    "error": "error",
    "notice": "info",
    "warning": "warn",
    "error": "error",
    "crit": "critical",
    "alert": "critical",
    "emerg": "critical"
};

exports.MDKTransport = function (options) {
    this.defaultSession = options.mdk.session();
    this.level = options.level || "info";
    this.name = options.name || this.name;
};
util.inherits(exports.MDKTransport, winston.Transport);
exports.MDKTransport.prototype.name = "mdk";

exports.MDKTransport.prototype.log = function (level, msg, meta, callback) {
    var session = cls.getMDKSession();
    if (session === undefined) {
        session = this.defaultSession;
    }
    level = exports.levelMapping[level];
    session[level](this.name, msg);
    callback(null, true);
};
