= MDK Release Process

== The release process

1. Using the release automation scripts (see below), you tag a commit on `master` and push to GitHub.
2. Travis CI notices that the commit has a tag, builds packages and uploads them to PyPI/NPM/RubyGems/Maven Central.

== Running the release

1. `git checkout master`
2. `git pull`
3. `make release-patch` to update from 2.0.x to 2.0.x+1.
4. If the above command succeeds it will tell you to run `git push origin master --tags`, so do that.
5. Then, validate the release as described in the next section.

== Validating the release

Check Travis-CI build for the tag (it'll be in the Branches tab, e.g. you'll see a build for "v2.0.23").
If it succeeded, great.

If not:

* If the issue is failed upload to some repository due to network blip, retry the build.
* If tests failed with intermittent failure, retry the build.
* If upload succeeded to some places but not other due to permanent-looking problem you may have to delete artifacts from those package repositories where the release did end up.
