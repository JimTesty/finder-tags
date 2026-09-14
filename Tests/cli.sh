#!/bin/sh
set -eu

bin=${1:?usage: cli.sh /path/to/tag}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/finder-tags-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

touch "$tmp/a" "$tmp/b"
mkdir -p "$tmp/tree/sub"
touch "$tmp/tree/root-file" "$tmp/tree/sub/child"

"$bin" --help | grep -q -- 'finder-tags executable: tag'
"$bin" --help | grep -q -- '--match'
"$bin" --help | grep -q -- '--usage'
[ "$("$bin" --version)" = "tag 4.1" ]

# Traversal/display compatibility with jdberry/tag: explicit directory first,
# then descendants relative to that directory argument.
enter_output=$("$bin" -e "$tmp/tree")
[ "$(printf '%s\n' "$enter_output" | sed -n '1p')" = "$tmp/tree" ]
printf '%s\n' "$enter_output" | grep -qx 'root-file'
printf '%s\n' "$enter_output" | grep -qx 'sub'
if printf '%s\n' "$enter_output" | grep -qF "$tmp/tree/root-file"; then
    echo "-e unexpectedly prefixed child with parent path" >&2
    exit 1
fi

recursive_output=$("$bin" -R "$tmp/tree")
[ "$(printf '%s\n' "$recursive_output" | sed -n '1p')" = "$tmp/tree" ]
printf '%s\n' "$recursive_output" | grep -qx 'sub/child'
if printf '%s\n' "$recursive_output" | grep -qF "$tmp/tree/sub/child"; then
    echo "-R unexpectedly prefixed descendant with parent path" >&2
    exit 1
fi

# Generic CLI behavior. On non-macOS filesystems Foundation generally reports
# no Finder tags, but these still exercise match, JSON, aliases, and dry-run.
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

# Real Finder-tag integration checks when running on macOS. These test the core
# order-preservation behavior without XCTest or external utilities.
if [ "$(uname -s)" = Darwin ]; then
    "$bin" --set 'First,Second' "$tmp/a"
    [ "$("$bin" -N "$tmp/a")" = 'First,Second' ]

    "$bin" --add 'Third,First' "$tmp/a"
    [ "$("$bin" -N "$tmp/a")" = 'First,Second,Third' ]
    [ "$("$bin" -VN "$tmp/a")" = 'Third,Second,First' ]

    "$bin" --remove 'Second' "$tmp/a"
    [ "$("$bin" -N "$tmp/a")" = 'First,Third' ]

    "$bin" --copy "$tmp/a" "$tmp/b"
    [ "$("$bin" -N "$tmp/b")" = 'First,Third' ]

    "$bin" --set 'X,Y' --json "$tmp/b" | grep -q '"dryRun" : false'
    [ "$("$bin" -N "$tmp/b")" = 'X,Y' ]
fi

echo "CLI smoke tests passed"
