var assert = require("assert");
var cls = require("datawire_mdk/cls.js");

var Promise = require('bluebird');
var clsBluebird = require('cls-bluebird');

clsBluebird( cls.namespace );

describe('continuation-local-storage', function() {
    it('cls.setMDKSession stores an object that can be retrieved with cls.getMDKSession', function() {
        var thing1 = 1234;
        var thing2 = 4567;
        cls.namespace.run(function() {
            cls.setMDKSession(thing1);
            assert.strictEqual(cls.getMDKSession(), thing1);
        });
        cls.namespace.run(function() {
            cls.setMDKSession(thing2);
            assert.strictEqual(cls.getMDKSession(), thing2);
        });
    });

    it('cls.getMDKSession returns undefined when run outside the cls namespace', function () {
        assert.strictEqual(cls.getMDKSession(), undefined);
    });
});
