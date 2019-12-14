# What?

This script prepares most parts of a new ClassicPress release.

## How to use

Copy `sample-config.sh` to `config.sh` and fill in the values.  In order to do
an official ClassicPress release, you'll need the correct key registered with
GPG on your computer.

Run `bin/build.sh`.  It will display usage information that indicates the
correct arguments, which include the current version number and the previous
version number.  Security releases should use the `hotfix` argument to do a
hotfix release according to the `git flow` model, and regular releases should
not.  For example:

- Regular release: `bin/build.sh 1.2.0 1.1.2`
- Security release: `bin/build.sh 1.1.2 1.1.1 hotfix`
