/* continuation-local-storage support for MDK sessions. */

var cls = require('continuation-local-storage');
var namespace = cls.createNamespace('io.datawire.mdk');

exports.setMDKSession = function (session) {
    namespace.set('session', session);
};

exports.getMDKSession = function () {
    return namespace.get('session');
};

exports.run = function (f) {
    return namespace.run(f);
};
