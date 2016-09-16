var express = require('express');
var mdk_express = require('datawire_mdk_express');
var app = express();

app.use(mdk_express.mdkSessionStart);

app.get('/context', function (req, res) {
    res.send(req.mdk_session.externalize());
});

app.get('/resolve', function (req, res) {
    req.mdk_session.resolve_async("service1", "1.0").then(
        function (node) {
            var policy = req.mdk_session._mdk._disco.failurePolicy(node);
            var result = {};
            result[node.address] = [policy.successes, policy.failures];
            if (req.GET.get("error")) {
                throw "Erroring as requested.";
            } else {
                res.json(result);
            }
        }, function (err) {});
});

app.use(mdk_express.mdkErrorHandler);

app.listen(9191, function () {
  console.log('Listening on port 9191');
});
