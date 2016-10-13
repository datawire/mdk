var request = require('request');
var extend = require('extend');

// The following code was originally part of Request, and is therfore in part
// copyright 2010-2012 Mikeal Rogers, licensed under the Apache License 2.0.
function initParams(uri, options, callback) {
    if (typeof options === 'function') {
        callback = options;
    }

    var params = {};
    if (typeof options === 'object') {
        extend(params, options, {uri: uri});
    } else if (typeof uri === 'string') {
        extend(params, {uri: uri});
    } else {
        extend(params, uri);
    }
    params.callback = callback || params.callback;
    return params;
}

function wrapRequestMethod (method, optionsFactory, requester, verb) {
    return function (uri, opts, callback) {
        var options = optionsFactory();
        var params = initParams(uri, opts, callback);
        var target = {};
        extend(true, target, options, params);

        target.pool = params.pool || options.pool;

        if (verb) {
            target.method = verb.toUpperCase();
        }

        if (typeof requester === 'function') {
            method = requester;
        }

        return method(target, target.callback);
    };
}

// Create a wrapper for Request that injects the MDK session header and sets an
// appropriate timeout.
exports.forMDKSession = function (mdkSession, requester) {
    var self = request;

    function optionsFactory() {
        var options = {headers: {"X-MDK-CONTEXT": mdkSession.externalize()}};
        var timeout = mdkSession.getRemainingTime() * 1000;
        if (timeout !== null) {
            options["timeout"] = timeout;
        }
        return options;
    };

    var defaults      = wrapRequestMethod(self, optionsFactory, requester);

    var verbs = ['get', 'head', 'post', 'put', 'patch', 'del', 'delete'];
    verbs.forEach(function(verb) {
        defaults[verb]  = wrapRequestMethod(self[verb], optionsFactory, requester, verb);
    });

    defaults.cookie   = wrapRequestMethod(self.cookie, optionsFactory, requester);
    defaults.jar      = self.jar;
    defaults.defaults = self.defaults;
    return defaults;
};
