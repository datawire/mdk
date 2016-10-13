var mdk = require('datawire_mdk').mdk;
var process = require('process');
var mdk_request = require('datawire_mdk_request');

mdk = mdk.start();

process.on('exit', function () {
    mdk.stop();
});

var mdkSession = mdk.session();
mdkSession.setTimeout(1.0);

var requestMDK = mdk_request.forMDKSession(mdkSession);
requestMDK(process.argv[2], function (error, response, body) {
    if (error !== null && error.code === 'ETIMEDOUT') {
        process.exit(123);
    } else {
        process.exit(0);
    }
});
