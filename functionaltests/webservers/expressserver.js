var process = require('process');
var express = require('express');
var timeout = require('connect-timeout');
var mdk_express = require('datawire_mdk_express');
var app = express();

app.use(timeout('1s', {respond: true}));
app.use(mdk_express.mdkSessionStart);

app.get('/context', function (req, res) {
    res.send(req.mdk_session.externalize());
});

app.get('/resolve', function (req, res) {
    var isError = req.query.error !== undefined;
    req.mdk_session.resolve_async("service1", "1.0").then(
        function (node) {
            var policy = req.mdk_session._mdk._disco.failurePolicy(node);
            var result = {};
            result[node.address] = [policy.successes, policy.failures];
            if (isError) {
                throw "Erroring as requested.";
            } else {
                res.json(result);
            }
        }, function (err) {});
});

app.get('/timeout', function (req, res) {
    res.json(req.mdk_session.getSecondsToTimeout());
});

app.use(mdk_express.mdkErrorHandler);

app.listen(process.argv[2], function () {
    console.log('Listening on port ' + process.argv[2].toString());
});
