#!/bin/sh
set -eu

bin=${1:?usage: cli.sh /path/to/tag}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/tag-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

touch "$tmp/a" "$tmp/b"

"$bin" --help | grep -q -- '--match'
"$bin" --help | grep -q -- '--usage'
[ "$("$bin" --version)" = "tag 4.0" ]

# On ordinary Linux filesystems Foundation reports no Finder tags. These tests
# still exercise traversal, empty-tag matching, JSON, aliases, and dry-run
# without making any metadata writes.
[ "$("$bin" --match '' "$tmp/a")" = "$tmp/a" ]
"$bin" --json "$tmp/a" | grep -q '"tags"'
"$bin" --set 'First,Second' --dryrun "$tmp/a" | grep -q 'First,Second'
"$bin" --set 'First,Second' --dry-run --json "$tmp/a" | grep -q '"after"'

if "$bin" --copy "$tmp/a" >/dev/null 2>&1; then
    echo "expected malformed --copy to fail" >&2
    exit 1
fi

if "$bin" --dry-run "$tmp/a" >/dev/null 2>&1; then
    echo "expected --dry-run with list to fail" >&2
    exit 1
fi

echo "CLI smoke tests passed"
