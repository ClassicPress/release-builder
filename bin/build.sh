#!/usr/bin/env bash


###
# Basic setup
###

# Exit on error
set -e

# Change to root directory of this repository
cd "$(dirname "$0")"
cd ..


###
# Load configuration
###

. ~/.nvm/nvm.sh --no-use

. config.sh

VERSION="$1"
LAST_VERSION="$2"
RELEASE_TYPE="release"
[ "$3" = hotfix ] && RELEASE_TYPE="hotfix"
GITHUB_URL_CORE="https://github.com/ClassicPress/ClassicPress"
GITHUB_URL_RELEASE="https://github.com/ClassicPress/ClassicPress-release"


###
# Verify configuration
###

for v in \
	CP_CORE_PATH \
	CP_RELEASE_PATH \
	GPG_KEY_ID \
	DRAFT_SUBFORUM_URL \
	VERSION \
	LAST_VERSION \
; do
	if [ -z "${!v}" ]; then
		echo "$v variable not set!" >&2
		if [[ "$v" = *VERSION* ]]; then
			echo "Usage : $0 NEW_VERSION LAST_VERSION [hotfix]" >&2
			echo "See   : $GITHUB_URL_RELEASE/releases" >&2
		fi
		exit 1
	fi
	if [[ "$v" = *PATH ]] && [ ! -d "${!v}" ]; then
		echo "$v config directory does not exist!" >&2
		exit 1
	fi
done

for p in git nvm convert; do
	if ! type -t $p > /dev/null; then
		echo "Program/function \`$p\` not found, make sure it is installed!" >&2
		exit 1
	fi
done

if ! ( git flow 2>&1 | grep -q 'usage: git flow' ); then
	echo '`git flow` not found, make sure it is installed!' >&2
	exit 1
fi

if ! gpg --list-keys "$GPG_KEY_ID" > /dev/null; then
	echo "GPG key ID '$GPG_KEY_ID' is not valid!" >&2
	exit 1
fi


###
# Set up progress file
###

# https://stackoverflow.com/a/3572105
realpath_bash() {
  [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

PROGRESS_FILE="$(realpath_bash "$VERSION.progress")"


###
# Helper functions
###

# https://stackoverflow.com/a/52565509
token_quote() {
	local quoted=()
	for token; do
		quoted+=( "$(printf '%q' "$token")" )
	done
	printf '%s\n' "${quoted[*]}"
}

already_done() {
	ACTION="$1"
	PROGRESS_OUTPUT="$2"
	[ -z "$ACTION" ] && echo 0 && return
	echo "[[$ACTION]]" >&2
	[ ! -f "$PROGRESS_FILE" ] && echo 0 && return
	if grep -Pq "^$ACTION(\$|=)" "$PROGRESS_FILE"; then
		echo "[[$ACTION: already done!]]" >&2
		[ ! -z "$PROGRESS_OUTPUT" ] && echo "$PROGRESS_OUTPUT" >&2
		echo >&2
		echo 1
	else
		echo 0
	fi
}

wait_impl() {
	TYPE="$1"
	shift
	PROGRESS_OUTPUT=
	if [[ "$1" = "[["* ]]; then
		PROGRESS_OUTPUT="$1"
		shift
	fi
	ACTION="$1"
	shift
	if [ $(already_done "$ACTION" "$PROGRESS_OUTPUT") = 1 ]; then
		if [ "$TYPE" = input ]; then
			# Restore previous value
			progress_line=$(grep -P "^$ACTION=" "$PROGRESS_FILE")
			echo "$progress_line" | cut -d= -f2-
		fi
		return
	fi
	case $TYPE in
		cmd)
			echo -n "\$ $(token_quote "$@")" >&2
			read i
			eval "$(token_quote "$@")"
			;;
		action)
			for msg in "$@"; do
				echo "> $msg" >&2
			done
			echo -n '> ' >&2
			read i
			;;
		input)
			for msg in "$@"; do
				echo "> $msg" >&2
			done
			echo -n '= ' >&2
			read i
			echo "$i"
			;;
	esac
	[ ! -z "$PROGRESS_OUTPUT" ] && echo "$PROGRESS_OUTPUT" >&2
	echo >&2
	if [ "$TYPE" = input ]; then
		echo "$ACTION=$i" >> "$PROGRESS_FILE"
	else
		echo "$ACTION" >> "$PROGRESS_FILE"
	fi
}

wait_cmd() {
	wait_impl cmd "$@"
}

wait_action() {
	wait_impl action "$@"
}

wait_input() {
	wait_impl input "$@"
}


###
# Main program logic
###

# Do this before any other `cd` commands
wait_cmd \
	"[[release-banner: images/ClassicPress-release-banner-v$VERSION.png]]" \
	'release-banner' \
	convert images/ClassicPress-release-banner-template.png \
	-font images/source-sans-pro/SourceSansPro-Regular.otf \
	-pointsize 90 \
	-fill 'rgb(255,255,255)' \
	-gravity center \
	-annotate +0+264 "Version $VERSION available now!" \
	"images/ClassicPress-release-banner-v$VERSION.png"

FORUMS_RELEASE_POST_URL=$(
	wait_input 'release-changelog-forums-draft' \
		'Prepare the release changelog on the forums:' \
		'Previous releases   : https://forums.classicpress.net/c/announcements/release-notes' \
		"Changelog URL       : $GITHUB_URL_CORE/compare/$LAST_VERSION+dev...$VERSION+dev" \
		"New draft goes here : $DRAFT_SUBFORUM_URL"
)

wait_cmd '' \
	cd "$CP_CORE_PATH"

wait_cmd 'dev-fetch-origin' \
	git fetch origin
wait_cmd 'dev-update-master' \
	git checkout origin/master -B master
wait_cmd 'dev-update-develop' \
	git checkout origin/develop -B develop

wait_cmd 'dev-release-start' \
	git flow $RELEASE_TYPE start $VERSION+dev --showcommands

wait_action 'dev-security-fixes' \
	'if there are any security fixes, backport them now (in a new shell)' \
	'e.g. `git commit` or `bin/backport-wp-commit.sh -c XXXX`'

wait_action 'dev-version-bump' \
	"update version to $VERSION+dev and save (do not commit):" \
	'- in package.json (line 3)' \
	'- in src/wp-includes/version.php (line 30)'

wait_cmd 'dev-version-git-add' \
	git add package.json src/wp-includes/version.php

wait_cmd 'dev-version-git-commit' \
	git commit -m "Bump source version to $VERSION+dev"

wait_cmd 'dev-release-finish' \
	GIT_COMMITTER_NAME='ClassicPress Releases' \
	GIT_COMMITTER_EMAIL='releases@classicpress.net' \
	GIT_AUTHOR_NAME='ClassicPress Releases' \
	GIT_AUTHOR_EMAIL='releases@classicpress.net' \
	git flow $RELEASE_TYPE finish -u "$GPG_KEY_ID" --showcommands \
	$VERSION+dev -m 'Source code for release'

wait_cmd 'dev-release-push' \
	git push origin develop master $VERSION+dev

wait_action 'dev-release-inspect-changelog' \
	'Inspect the dev release changelog and diff:' \
	"$GITHUB_URL_CORE/compare/$LAST_VERSION+dev...$VERSION+dev"

wait_action 'dev-release-edit' \
	'Edit source release on GitHub:' \
	"$GITHUB_URL_CORE/releases/new?tag=$VERSION%2Bdev" \
    'Title:' \
	"  This is not the $VERSION release!" \
	'Body:' \
	"  Go here instead: $GITHUB_URL_RELEASE/releases/tag/$VERSION"

wait_cmd 'dev-checkout' \
	git checkout $VERSION+dev
wait_cmd 'dev-rm-build' \
	rm -rf node_modules/ build/
wait_cmd 'dev-nvm-use' \
	nvm use
wait_cmd 'dev-npm-install' \
	npm install
wait_cmd 'dev-npm-install-grunt' \
	npm install -g grunt-cli
wait_cmd 'release-build' \
	CLASSICPRESS_RELEASE=true grunt build

wait_cmd '' \
	cd "$CP_RELEASE_PATH"
wait_cmd 'release-fetch-origin' \
	git fetch origin
wait_cmd 'release-update-master' \
	git checkout origin/master -B master
wait_cmd 'release-update-develop' \
	git checkout origin/develop -B develop

wait_cmd '' \
	cd "$CP_CORE_PATH/build"
wait_cmd 'release-cp-gitdir' \
	cp -var "$CP_RELEASE_PATH/.git/" ./
wait_cmd 'release-git-status' \
	git status
wait_cmd 'release-git-stash' \
	git stash
wait_cmd 'release-start' \
	git flow $RELEASE_TYPE start $VERSION --showcommands
wait_cmd 'release-git-stash-pop' \
	git stash pop
wait_cmd 'release-git-add' \
	git add .
wait_cmd 'release-git-commit' \
	git commit -m "Release $VERSION"
wait_cmd 'release-check-files' \
	../bin/check-release-files.pl

wait_cmd 'release-finish' \
	GIT_COMMITTER_NAME='ClassicPress Releases' \
	GIT_COMMITTER_EMAIL='releases@classicpress.net' \
	GIT_AUTHOR_NAME='ClassicPress Releases' \
	GIT_AUTHOR_EMAIL='releases@classicpress.net' \
	git flow $RELEASE_TYPE finish -u "$GPG_KEY_ID" --showcommands \
	"$VERSION" -m 'Release'

wait_cmd 'release-push' \
	git push origin develop master "$VERSION"

wait_action 'release-inspect-changelog' \
	'Inspect the final release changelog and diff:' \
	"$GITHUB_URL_RELEASE/compare/$LAST_VERSION...$VERSION"

wait_cmd 'update-api-test' \
	ssh classicpress.api-v1_api-v1-test \
	/www/src/ClassicPress-APIs_api-v1-test/v1-upgrade-generator/update.sh

wait_action 'release-test' \
	'Ask people to test the release now:' \
	"$GITHUB_URL_RELEASE/archive/$VERSION.zip"

wait_action 'release-changelog-github' \
	'Edit release on GitHub:' \
	"$GITHUB_URL_RELEASE/releases/new?tag=$VERSION" \
	'Title:' \
	"  ClassicPress $VERSION" \
	'Body:' \
	"
**ClassicPress \`$VERSION\`** is (A SENTENCE OR TWO ABOUT THE RELEASE HERE)

It is **available now** - use the \"**Source code** (zip)\" file below.

## Major changes since ClassicPress \`$LAST_VERSION\`

(COPY MAJOR CHANGES FROM FORUM POST)

## More information

- [Release announcement post]($FORUMS_RELEASE_POST_URL)
- Full changelog: $GITHUB_URL_CORE/compare/$LAST_VERSION+dev...$VERSION+dev"

wait_action 'release-changelog-forums-publish' \
	'Publish the release changelog on the forums:' \
	"$FORUMS_RELEASE_POST_URL"

wait_cmd 'update-api-production' \
	ssh classicpress.api-v1_api-v1 \
	/www/src/ClassicPress-APIs_api-v1/v1-upgrade-generator/update.sh

wait_action 'release-announcement-slack' \
	'Drop a note in the #announcements channel on Slack:' \
	"ClassicPress version \`$VERSION\` is now available for automatic updates and new installations: $FORUMS_RELEASE_POST_URL"

wait_action 'release-changelog-forums-update-previous' \
	'https://forums.classicpress.net/c/announcements/release-notes' \
	'Edit the post for the previous release to include this box at the top:' \
	'**This is no longer the latest release of ClassicPress!**' \
	'You can find the latest release at the top of the [Release Notes subforum](https://forums.classicpress.net/c/announcements/release-notes).'

wait_action 'release-changelog-github-verify' \
	'Double-check the GitHub post to make sure everything looks OK' \
	'(all links work, etc.)' \
	"$GITHUB_URL_RELEASE/releases/tag/$VERSION"

echo "RELEASE COMPLETE!"
