var tracing = require("datawire_tracing").tracing;

tracer = new tracing.Tracer()

tracer.query(1467045724000, 1467045780000).andEither(
	function goodHandler(res) {
		console.log("Good!");

		res.result.forEach(function (record) {
			console.log(String(record.timestamp) + " " + record.record.level +
				        " " + record.record.text);
		});

		# This should be unnecessary -- to be fixed soon.
		return null;
	},
	function badHandler(result) {
		print("Failure: %s" % result.toString());

		# This should be unnecessary -- to be fixed soon.
		return null;
	}
);
