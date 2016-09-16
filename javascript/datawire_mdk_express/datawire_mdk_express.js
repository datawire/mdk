var datawire_mdk = require('datawire_mdk');
var process = require('process');

var mdk = datawire_mdk.mdk.start();
process.on('exit', function () {
    mdk.stop();
});

exports.mdkSessionStart = function (req, res, next) {
    console.log("MDK start");
    req.on("end", function() {
        console.log("MDK end");
        req.mdk_session.finish_interaction();
    });
    var header = req.get(datawire_mdk.mdk.MDK.CONTEXT_HEADER);
    if (header === undefined) {
        header = null;
    }
    req.mdk_session = mdk.join(header);
    req.mdk_session.start_interaction();
    next();
};

exports.mdkErrorHandler = function (err, req, res, next) {
    console.log("MDK err");
    req.mdk_session.fail_interaction(err.toString());
};
