"use strict";

var process = require("process");
var mdk = require("datawire_mdk").mdk;
var MDK = mdk.start();

var main = function() {
    setTimeout(function() {
        console.log("timeout");
        MDK.stop();
        process.exit(1);
    }, 30000);
    var session = MDK.session();
    session.trace("DEBUG");
    var category = process.argv[2];
    var messages = [];
    var sent_messages = ["hello critical " + category,
                         "hello debug " + category,
                         "hello error " + category,
                         "hello info " + category,
                         "hello warn " + category];
    MDK._tracer.subscribe(function (event) {
        if (event.category == category) {
            messages.push(event.text);
        }
        if (messages.length == 5) {
            MDK.stop();
            messages.sort();
            // Remind me never to write any Javascript ever again:
            if (JSON.stringify(messages) != JSON.stringify(sent_messages)) {
                console.log("unexpected responses: " + messages);
                process.exit(1);
            } else {
                console.log("got all messages");
                process.exit(0);
            }
        }
    });

    setTimeout(function() {
        session.critical(category, sent_messages[0]);
        session.debug(category, sent_messages[1]);
        session.error(category, sent_messages[2]);
        session.info(category, sent_messages[3]);
        session.warn(category, sent_messages[4]);
    }, 3000);
};

main();
