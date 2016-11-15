var util = require("util");
var winston = require("winston");
var cls = require("datawire_mdk/cls.js");

exports.MDKTransport = function (options) {
    this.level = options.level || "info";
};
util.inherits(exports.MDKTransport, winston.Transport);
exports.MDKTransport.prototype.name = "MDKTransport";

exports.MDKTransport.prototype.log = function (level, msg, meta, callback) {
    if (typeof meta === 'function') {
        callback = meta;
        meta = {};
    }
    cls.getMDKSession().info("", "");
    callback(null, true);
};
