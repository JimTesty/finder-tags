#!/bin/sh
set -eu

bin_arg=${1:?usage: cli.sh /path/to/tag}
case "$bin_arg" in
    /*) bin=$bin_arg ;;
    *) bin="$(pwd -P)/$bin_arg" ;;
esac

repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
work="$repo/Tests/.cli-work.$$"
rm -rf "$work"
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT HUP INT TERM

touch "$work/a" "$work/b" "$work/c" "$work/space name"
mkdir -p "$work/tree/sub" "$work/tree/real"
touch "$work/tree/root-file" "$work/tree/sub/child" "$work/tree/real/linked-child"
touch "$work/tree/.hidden"
ln -s real "$work/tree/link"
ln -s .. "$work/tree/real/back-to-tree"

"$bin" --help | grep -q -- 'finder-tags executable: tag'
"$bin" --help | grep -q -- '--case-sensitive'
"$bin" --help | grep -q -- '--sorted-tags'
"$bin" --help | grep -q -- '--before TAG'
"$bin" --help | grep -q -- '--absolute'
"$bin" --help | grep -q -- '--stdin0'
"$bin" --help | grep -q -- '--no-follow-symlinks'
"$bin" --help | grep -q -- '--find TAGS'
"$bin" --help | grep -q -- '--jsonl'
[ "$("$bin" --version)" = "tag 8.0" ]

# Explicit directory first, then descendants relative to that argument.
enter_output=$("$bin" -e "$work/tree")
[ "$(printf '%s\n' "$enter_output" | sed -n '1p')" = "$work/tree" ]
printf '%s\n' "$enter_output" | grep -qx 'root-file'
printf '%s\n' "$enter_output" | grep -qx 'sub'
if printf '%s\n' "$enter_output" | grep -qF "$work/tree/root-file"; then
    echo "-e unexpectedly prefixed child with parent path" >&2
    exit 1
fi

recursive_output=$("$bin" -R "$work/tree")
[ "$(printf '%s\n' "$recursive_output" | sed -n '1p')" = "$work/tree" ]
printf '%s\n' "$recursive_output" | grep -qx 'sub/child'
printf '%s\n' "$recursive_output" | grep -qx 'link/linked-child'
printf '%s\n' "$recursive_output" | grep -qx 'real/back-to-tree'
[ "$(printf '%s\n' "$recursive_output" | wc -l | tr -d ' ')" -lt 30 ]

# --no-follow-symlinks still lists the symlink but does not recurse through it.
nofollow_output=$("$bin" -R --no-follow-symlinks "$work/tree")
printf '%s\n' "$nofollow_output" | grep -qx 'link'
if printf '%s\n' "$nofollow_output" | grep -q '^link/'; then
    echo "--no-follow-symlinks unexpectedly traversed link/" >&2
    exit 1
fi

# Hidden files are skipped unless -A is present.
if "$bin" -e "$work/tree" | grep -q '^\.hidden$'; then
    echo "hidden file unexpectedly listed without -A" >&2
    exit 1
fi
"$bin" -Ae "$work/tree" | grep -q '^\.hidden$'

# Absolute paths and richer JSONL path provenance.
absolute_output=$(cd "$work" && "$bin" --absolute a)
[ "$absolute_output" = "$work/a" ]
json_path=$(cd "$work" && "$bin" --jsonl a)
printf '%s\n' "$json_path" | grep -Fq '"absolutePath"'
printf '%s\n' "$json_path" | grep -Fq '"resolvedPath"'
printf '%s\n' "$json_path" | grep -Fq '"root"'
printf '%s\n' "$json_path" | grep -Fq '"path":"a"'

# Paths from stdin, including NUL-delimited input. Explicit empty stdin means
# zero files rather than silently falling back to current-directory traversal.
stdin_lines=$(printf '%s\n%s\n' "$work/a" "$work/b" | "$bin" --stdin -T)
printf '%s\n' "$stdin_lines" | grep -Fxq "$work/a"
printf '%s\n' "$stdin_lines" | grep -Fxq "$work/b"
[ -z "$(printf '' | "$bin" --stdin -T)" ]
stdin_nul=$(printf '%s\0%s\0' "$work/a" "$work/space name" | "$bin" --stdin0 -T)
printf '%s\n' "$stdin_nul" | grep -Fxq "$work/a"
printf '%s\n' "$stdin_nul" | grep -Fxq "$work/space name"

# Generic parser/output behavior. On non-macOS filesystems Foundation normally
# reports no Finder tags, so mutation parsing is exercised with --dry-run.
[ "$("$bin" --match '' "$work/a")" = "$work/a" ]
"$bin" --jsonl "$work/a" | grep -q '"tags"'
"$bin" --ndjson "$work/a" | grep -q '"path"'

quoted=$("$bin" --set '"Orange","Project, Alpha","Needs review"' --dry-run --jsonl "$work/a")
printf '%s\n' "$quoted" | grep -Fq '"after":["Orange","Project, Alpha","Needs review"]'
"$bin" --set 'orange,Orange' --dry-run --jsonl "$work/a" \
    | grep -Fq '"after":["orange","Orange"]'
"$bin" --set '"He said ""Hi"""' --dry-run --jsonl "$work/a" \
    | grep -Fq 'He said \"Hi\"'

# Opt-in sorting affects the prospective stored array on mutations.
"$bin" --set 'B,A,C' --sorted-tags --dry-run --jsonl "$work/a" \
    | grep -Fq '"after":["A","B","C"]'

# Ordinary shell quoting is naturally accepted too.
"$bin" --set "Orange" --dry-run --jsonl "$work/a" | grep -Fq '"after":["Orange"]'

if "$bin" --set '"unterminated' --dry-run "$work/a" >/dev/null 2>&1; then
    echo "expected malformed quoted TAGS to fail" >&2
    exit 1
fi

newline_tag='Line one
Line two'
if "$bin" --set "$newline_tag" --dry-run "$work/a" >/dev/null 2>"$work/newline.err"; then
    echo "expected newline-containing tag to fail" >&2
    exit 1
fi
grep -q 'may not contain CR, LF, or NUL' "$work/newline.err"

cr_tag=$(printf 'Line one\rLine two')
if "$bin" --set "$cr_tag" --dry-run "$work/a" >/dev/null 2>"$work/cr.err"; then
    echo "expected CR-containing tag to fail" >&2
    exit 1
fi
grep -q 'may not contain CR, LF, or NUL' "$work/cr.err"

# --usage requires TAGS.
if "$bin" --usage >/dev/null 2>&1; then
    echo "expected --usage without TAGS to fail" >&2
    exit 1
fi
"$bin" --usage '*' "$work/a" >/dev/null

# Removed buffered JSON mode should not silently survive under the old name.
if "$bin" --json "$work/a" >/dev/null 2>&1; then
    echo "expected removed --json option to fail" >&2
    exit 1
fi

"$bin" --add 'First,Second' --at 0 --dry-run --jsonl "$work/a" \
    | grep -Fq '"after":["First","Second"]'
"$bin" --add First --at left --dry-run "$work/a" >/dev/null
"$bin" --add First --at bottom --dry-run "$work/a" >/dev/null
"$bin" --add First --at right --dry-run "$work/a" >/dev/null
"$bin" --add First --at top --dry-run "$work/a" >/dev/null
"$bin" --prepend First --dry-run "$work/a" >/dev/null
"$bin" --append First --dry-run "$work/a" >/dev/null

if "$bin" --list --at first "$work/a" >/dev/null 2>&1; then
    echo "expected --at without --add/--move to fail" >&2
    exit 1
fi

if "$bin" --copy "$work/a" >/dev/null 2>&1; then
    echo "expected malformed --copy to fail" >&2
    exit 1
fi

if "$bin" --dry-run "$work/a" >/dev/null 2>&1; then
    echo "expected --dry-run with list to fail" >&2
    exit 1
fi

# Spotlight --find is macOS-only. On other platforms it should fail cleanly,
# rather than failing to compile or masquerading as an empty successful search.
if [ "$(uname -s)" != Darwin ]; then
    if "$bin" --find '*' >/dev/null 2>"$work/find.err"; then
        echo "expected --find to be unavailable off macOS" >&2
        exit 1
    fi
    grep -q 'available only on macOS' "$work/find.err"
fi

# Real Finder-tag integration checks when running on macOS. Everything remains
# inside Tests/.cli-work.*, including symlink targets.
if [ "$(uname -s)" = Darwin ]; then
    "$bin" --set 'First,Second' "$work/a"
    [ "$("$bin" -N "$work/a")" = 'First,Second' ]

    "$bin" --add 'Third,First' "$work/a"
    [ "$("$bin" -N "$work/a")" = 'First,Second,Third' ]
    [ "$("$bin" -VN "$work/a")" = 'Third,Second,First' ]

    "$bin" --remove 'Second' "$work/a"
    [ "$("$bin" -N "$work/a")" = 'First,Third' ]

    "$bin" --copy "$work/a" "$work/b"
    [ "$("$bin" -N "$work/b")" = 'First,Third' ]

    # --sorted-tags sorts read-only output without rewriting, and sorts the
    # resulting stored array for mutating operations.
    "$bin" --set 'B,A,C' "$work/a"
    [ "$("$bin" --sorted-tags -N "$work/a")" = 'A,B,C' ]
    [ "$("$bin" -N "$work/a")" = 'B,A,C' ]
    "$bin" --set 'B,A,C' --sorted-tags "$work/a"
    [ "$("$bin" -N "$work/a")" = 'A,B,C' ]
    "$bin" --set 'C,A' "$work/a"
    "$bin" --add B --sorted-tags "$work/a"
    [ "$("$bin" -N "$work/a")" = 'A,B,C' ]
    "$bin" --set 'C,B,A' "$work/a"
    "$bin" --remove B --sorted-tags "$work/a"
    [ "$("$bin" -N "$work/a")" = 'A,C' ]
    "$bin" --set 'C,A' "$work/a"
    "$bin" --copy "$work/a" "$work/b" --sorted-tags
    [ "$("$bin" -N "$work/b")" = 'A,C' ]

    # Case-insensitive matching preserves case as data and re-cases a unique
    # match in place instead of appending/merging it.
    "$bin" --set 'red,orange,yellow' "$work/a"
    "$bin" --add 'Orange' "$work/a"
    [ "$("$bin" -N "$work/a")" = 'red,Orange,yellow' ]
    [ "$("$bin" -m orange "$work/a")" = "$work/a" ]

    "$bin" --set 'red,orange,yellow' "$work/a"
    "$bin" -C --add 'Orange' "$work/a"
    [ "$("$bin" -N "$work/a")" = 'red,orange,yellow,Orange' ]
    [ -z "$("$bin" -C -m ORANGE "$work/a")" ]
    [ "$("$bin" -C -m Orange "$work/a")" = "$work/a" ]

    # A small Unicode folding check. This intentionally tests our documented
    # Foundation folding approximation, not an assertion about Finder internals.
    "$bin" --set 'Äpfel' "$work/a"
    [ "$("$bin" --match 'äPFEL' "$work/a")" = "$work/a" ]

    "$bin" --set 'orange' "$work/a"
    "$bin" --add 'orange,Orange' "$work/a"
    [ "$("$bin" -N "$work/a")" = 'orange,Orange' ]

    "$bin" --set 'orange,Orange' "$work/a"
    usage_output=$("$bin" --usage '*' "$work/a")
    printf '%s\n' "$usage_output" | grep -qx '1[[:space:]]orange'
    printf '%s\n' "$usage_output" | grep -qx '1[[:space:]]Orange'
    [ "$("$bin" --usage '*' --sorted-tags "$work/a" | cut -f2 | paste -sd, -)" = 'Orange,orange' ]

    "$bin" -C --remove Orange "$work/a"
    [ "$("$bin" -N "$work/a")" = 'orange' ]
    "$bin" --set 'orange,Orange' "$work/a"
    "$bin" --remove Orange "$work/a"
    [ -z "$("$bin" -N "$work/a")" ]

    # Quoted comma-containing tags round-trip. Foundation does not reliably
    # round-trip CR/LF inside Finder tag names, so those inputs are rejected.
    "$bin" --set '"Project, Alpha","Needs review"' "$work/a"
    [ "$("$bin" -N "$work/a")" = 'Project, Alpha,Needs review' ]
    "$bin" --match '"Project, Alpha"' "$work/a" | grep -Fxq "$work/a"

    # Ordered insertion/movement, including semantic neighbors.
    "$bin" --set 'A,C' "$work/a"
    "$bin" --add B --at 1 "$work/a"
    [ "$("$bin" -N "$work/a")" = 'A,B,C' ]
    "$bin" --add Z --at bottom "$work/a"
    [ "$("$bin" -N "$work/a")" = 'Z,A,B,C' ]
    "$bin" --add X --at top "$work/a"
    [ "$("$bin" -N "$work/a")" = 'Z,A,B,C,X' ]
    "$bin" --add D --before X "$work/a"
    [ "$("$bin" -N "$work/a")" = 'Z,A,B,C,D,X' ]
    "$bin" --add E --after D "$work/a"
    [ "$("$bin" -N "$work/a")" = 'Z,A,B,C,D,E,X' ]
    "$bin" --move B first "$work/a"
    [ "$("$bin" -N "$work/a")" = 'B,Z,A,C,D,E,X' ]
    "$bin" --move B --after D "$work/a"
    [ "$("$bin" -N "$work/a")" = 'Z,A,C,D,B,E,X' ]
    "$bin" --move X --before Z "$work/a"
    [ "$("$bin" -N "$work/a")" = 'X,Z,A,C,D,B,E' ]

    # Paths from stdin can drive mutations too.
    printf '%s\n%s\n' "$work/a" "$work/b" | "$bin" --stdin --set ViaStdin
    [ "$("$bin" -N "$work/a")" = 'ViaStdin' ]
    [ "$("$bin" -N "$work/b")" = 'ViaStdin' ]

    # Symlink operations target the referent by default.
    touch "$work/target-file"
    ln -s target-file "$work/file-link"
    "$bin" --set 'ViaLink' "$work/file-link"
    [ "$("$bin" -N "$work/target-file")" = 'ViaLink' ]
    [ "$("$bin" -N "$work/file-link")" = 'ViaLink' ]

    # Hard links should naturally observe the same file metadata.
    ln "$work/target-file" "$work/hard-link"
    [ "$("$bin" -N "$work/hard-link")" = 'ViaLink' ]

    "$bin" --set 'X,Y' --jsonl "$work/b" | grep -q '"dryRun":false'
    [ "$("$bin" -N "$work/b")" = 'X,Y' ]
fi

echo "CLI tests passed"
