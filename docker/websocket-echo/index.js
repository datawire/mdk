// https://yaler.net/nodejs-websocket-server

var WebSocketServer = require('ws').Server,
    wss = new WebSocketServer({ port: 9123 });

wss.on('connection', function connection(ws) {
    ws.on('message', function incoming(message) {
        ws.send(message);
    });
});
