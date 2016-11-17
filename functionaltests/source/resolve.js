"use strict";

var MDK = require("datawire_mdk").mdk.start();

function showResult(result) {
    console.log(result.address);
    MDK.stop();
}

function showError(error) {
    console.log(error);
    MDK.stop();
}

function main() {
    setTimeout(function() {
        console.log("timeout");
        MDK.stop();
    }, 30000);
    var ssn = MDK.session();
    ssn.resolve_async(process.argv[2], "1.0.0").then(showResult, showError);
}

main();
