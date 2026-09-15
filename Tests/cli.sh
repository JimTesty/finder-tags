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
ln -s missing "$work/tree/dangling"

"$bin" --help | grep -q -- 'finder-tags executable: tag'
"$bin" --help | grep -q -- '--case-sensitive'
"$bin" --help | grep -q -- '--sorted-tags'
"$bin" --help | grep -q -- '--before TAG'
"$bin" --help | grep -q -- '--absolute'
"$bin" --help | grep -q -- '--stdin0'
"$bin" --help | grep -q -- '--no-follow-symlinks'
"$bin" --help | grep -q -- '-L, --follow-symlinks'
"$bin" --help | grep -q -- '--print-symlinks'
"$bin" --help | grep -q -- '--exclude PATH'
"$bin" --help | grep -q -- '--find TAGS'
"$bin" --help | grep -q -- '--jsonl'
"$bin" --help | grep -q -- '--export'
"$bin" --help | grep -q -- '--restore ARCHIVE'
"$bin" --help | grep -q -- '--tagged-only'
"$bin" --help | grep -q -- '--file-info'
"$bin" --help | grep -q -- '--no-file-info'
"$bin" --help | grep -q -- '--convert ARCHIVE'
"$bin" --help | grep -q -- '--space-indent'
"$bin" --help | grep -q -- '--no-backup'
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
printf '%s\n' "$recursive_output" | grep -qx 'link'
if printf '%s\n' "$recursive_output" | grep -q '^link/'; then
    echo "recursive traversal followed a symlink by default" >&2
    exit 1
fi
printf '%s\n' "$recursive_output" | grep -qx 'real/back-to-tree'
[ "$(printf '%s\n' "$recursive_output" | wc -l | tr -d ' ')" -lt 30 ]

# Exclusions skip the matching item and its subtree. A single component is
# useful for names such as .git regardless of their depth.
excluded_output=$("$bin" -R --exclude real/ "$work/tree")
if printf '%s\n' "$excluded_output" | grep -Eq '^real(/|$)'; then
    echo "--exclude failed to skip real subtree" >&2
    exit 1
fi
printf '%s\n' "$excluded_output" | grep -qx 'sub/child'
printf '%s\n' "$excluded_output" | grep -qx 'link'

follow_output=$("$bin" -L -R "$work/tree")
printf '%s\n' "$follow_output" | grep -qx 'link/linked-child'

# --no-follow-symlinks still lists the symlink but does not recurse through it.
nofollow_output=$("$bin" -R --no-follow-symlinks "$work/tree")
printf '%s\n' "$nofollow_output" | grep -qx 'link'
if printf '%s\n' "$nofollow_output" | grep -q '^link/'; then
    echo "--no-follow-symlinks unexpectedly traversed link/" >&2
    exit 1
fi

# Symlink decorations follow ls -F-like rules. Printing a target does not
# enable traversal, and a dangling explicit symlink remains displayable.
[ "$(cd "$work/tree" && "$bin" --slash link)" = 'link@' ]
[ "$(cd "$work/tree" && "$bin" --print-symlinks link)" = 'link -> real' ]
[ "$(cd "$work/tree" && "$bin" --slash --print-symlinks link)" = 'link@ -> real/' ]
[ "$(cd "$work/tree" && "$bin" --slash --print-symlinks dangling)" = 'dangling@ -> missing (NOT FOUND)' ]
print_recursive=$("$bin" -R --print-symlinks "$work/tree")
printf '%s\n' "$print_recursive" | grep -qx 'link -> real'
if printf '%s\n' "$print_recursive" | grep -q '^link/'; then
    echo "--print-symlinks unexpectedly enabled traversal" >&2
    exit 1
fi
esc=$(printf '\033')
colored_symlink=$(cd "$work/tree" && "$bin" --color=force --slash --print-symlinks dangling)
case "$colored_symlink" in
    *"$esc[31m(NOT FOUND)$esc[m"*) ;;
    *) echo "missing symlink target was not colored red" >&2; exit 1 ;;
esac

# Hidden files are skipped unless -A is present.
if "$bin" -e "$work/tree" | grep -q '^\.hidden$'; then
    echo "hidden file unexpectedly listed without -A" >&2
    exit 1
fi
"$bin" -Ae "$work/tree" | grep -q '^\.hidden$'

# Absolute paths and compact stateful JSONL path provenance.
absolute_output=$(cd "$work" && "$bin" --absolute a)
[ "$absolute_output" = "$work/a" ]
json_path=$(cd "$work" && "$bin" --jsonl a)
printf '%s\n' "$json_path" | grep -Fq '"type":"root"'
if printf '%s\n' "$json_path" | grep -Fq '"absolutePath"'; then
    echo "JSONL unexpectedly repeated absolutePath" >&2
    exit 1
fi
printf '%s\n' "$json_path" | grep -Fq '"path":"a"'
json_recursive=$("$bin" --jsonl -R "$work/tree")
[ "$(printf '%s\n' "$json_recursive" | grep -c '"type":"root"')" -eq 1 ]
if printf '%s\n' "$json_recursive" | grep -q '"destination"'; then
    echo "default JSONL unexpectedly recorded symlink target metadata" >&2
    exit 1
fi
if printf '%s\n' "$json_recursive" | grep -q '"absolutePath"'; then
    echo "recursive JSONL unexpectedly repeated absolutePath" >&2
    exit 1
fi
json_follow=$("$bin" --jsonl -L -R "$work/tree")
printf '%s\n' "$json_follow" | grep -q '"kind":"symlink"'

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
file_info_json=$("$bin" --file-info --jsonl "$work/a")
printf '%s\n' "$file_info_json" | grep -q '"size"'
printf '%s\n' "$file_info_json" | grep -q '"mtime"'
file_info_text=$("$bin" --file-info "$work/a")
printf '%s\n' "$file_info_text" | grep -q '\['
printf '%s\n' "$file_info_text" | grep -Eq '\[[0-9]{8} [^]]*MB\]'
file_info_directory=$("$bin" --file-info "$work/tree")
printf '%s\n' "$file_info_directory" | grep -Eq '\[[0-9]{8} +0MB\]'
esc=$(printf '\033')
forced_info=$("$bin" --file-info --color=force "$work/a")
case "$forced_info" in
    *"$esc[32m"*"$esc[m"*) ;;
    *) echo "forced file-info color missing" >&2; exit 1 ;;
esac

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
    "$bin" --set 'First,Second' --no-backup "$work/a"
    [ "$("$bin" -N "$work/a")" = 'First,Second' ]
    space_indent_output=$("$bin" --space-indent "$work/a")
    printf '%s\n' "$space_indent_output" | grep -Fq '  First,Second'
    if printf '%s\n' "$space_indent_output" | grep -q "$(printf '\t')"; then
        echo "--space-indent unexpectedly emitted a tab" >&2
        exit 1
    fi

    "$bin" --add 'Third,First' --no-backup "$work/a"
    [ "$("$bin" -N "$work/a")" = 'First,Second,Third' ]
    [ "$("$bin" -VN "$work/a")" = 'Third,Second,First' ]

    "$bin" --remove 'Second' --no-backup "$work/a"
    [ "$("$bin" -N "$work/a")" = 'First,Third' ]

    "$bin" --copy "$work/a" "$work/b" --no-backup
    [ "$("$bin" -N "$work/b")" = 'First,Third' ]

    # --sorted-tags sorts read-only output without rewriting, and sorts the
    # resulting stored array for mutating operations.
    "$bin" --set 'B,A,C' --no-backup "$work/a"
    [ "$("$bin" --sorted-tags -N "$work/a")" = 'A,B,C' ]
    [ "$("$bin" -N "$work/a")" = 'B,A,C' ]
    "$bin" --set 'B,A,C' --sorted-tags --no-backup "$work/a"
    [ "$("$bin" -N "$work/a")" = 'A,B,C' ]
    "$bin" --set 'C,A' --no-backup "$work/a"
    "$bin" --add B --sorted-tags --no-backup "$work/a"
    [ "$("$bin" -N "$work/a")" = 'A,B,C' ]
    "$bin" --set 'C,B,A' --no-backup "$work/a"
    "$bin" --remove B --sorted-tags --no-backup "$work/a"
    [ "$("$bin" -N "$work/a")" = 'A,C' ]
    "$bin" --set 'C,A' --no-backup "$work/a"
    "$bin" --copy "$work/a" "$work/b" --sorted-tags --no-backup
    [ "$("$bin" -N "$work/b")" = 'A,C' ]

    # Case-insensitive matching preserves case as data and re-cases a unique
    # match in place instead of appending/merging it.
    "$bin" --set 'red,orange,yellow' --no-backup "$work/a"
    "$bin" --add 'Orange' --no-backup "$work/a"
    [ "$("$bin" -N "$work/a")" = 'red,Orange,yellow' ]
    [ "$("$bin" -m orange "$work/a")" = "$work/a" ]

    "$bin" --set 'red,orange,yellow' --no-backup "$work/a"
    "$bin" -C --add 'Orange' --no-backup "$work/a"
    [ "$("$bin" -N "$work/a")" = 'red,orange,yellow,Orange' ]
    [ -z "$("$bin" -C -m ORANGE "$work/a")" ]
    [ "$("$bin" -C -m Orange "$work/a")" = "$work/a" ]

    # A small Unicode folding check. This intentionally tests our documented
    # Foundation folding approximation, not an assertion about Finder internals.
    "$bin" --set 'Äpfel' --no-backup "$work/a"
    [ "$("$bin" --match 'äPFEL' "$work/a")" = "$work/a" ]

    "$bin" --set 'orange' --no-backup "$work/a"
    "$bin" --add 'orange,Orange' --no-backup "$work/a"
    [ "$("$bin" -N "$work/a")" = 'orange,Orange' ]

    "$bin" --set 'orange,Orange' --no-backup "$work/a"
    usage_output=$("$bin" --usage '*' "$work/a")
    printf '%s\n' "$usage_output" | grep -qx '1[[:space:]]orange'
    printf '%s\n' "$usage_output" | grep -qx '1[[:space:]]Orange'
    [ "$("$bin" --usage '*' --sorted-tags "$work/a" | cut -f2 | paste -sd, -)" = 'Orange,orange' ]

    "$bin" -C --remove Orange --no-backup "$work/a"
    [ "$("$bin" -N "$work/a")" = 'orange' ]
    "$bin" --set 'orange,Orange' --no-backup "$work/a"
    "$bin" --remove Orange --no-backup "$work/a"
    [ -z "$("$bin" -N "$work/a")" ]

    # Quoted comma-containing tags round-trip. Foundation does not reliably
    # round-trip CR/LF inside Finder tag names, so those inputs are rejected.
    "$bin" --set '"Project, Alpha","Needs review"' --no-backup "$work/a"
    [ "$("$bin" -N "$work/a")" = 'Project, Alpha,Needs review' ]
    "$bin" --match '"Project, Alpha"' "$work/a" | grep -Fxq "$work/a"

    # Ordered insertion/movement, including semantic neighbors.
    "$bin" --set 'A,C' --no-backup "$work/a"
    "$bin" --add B --at 1 --no-backup "$work/a"
    [ "$("$bin" -N "$work/a")" = 'A,B,C' ]
    "$bin" --add Z --at bottom --no-backup "$work/a"
    [ "$("$bin" -N "$work/a")" = 'Z,A,B,C' ]
    "$bin" --add X --at top --no-backup "$work/a"
    [ "$("$bin" -N "$work/a")" = 'Z,A,B,C,X' ]
    "$bin" --add D --before X --no-backup "$work/a"
    [ "$("$bin" -N "$work/a")" = 'Z,A,B,C,D,X' ]
    "$bin" --add E --after D --no-backup "$work/a"
    [ "$("$bin" -N "$work/a")" = 'Z,A,B,C,D,E,X' ]
    "$bin" --move B first --no-backup "$work/a"
    [ "$("$bin" -N "$work/a")" = 'B,Z,A,C,D,E,X' ]
    "$bin" --move B --after D --no-backup "$work/a"
    [ "$("$bin" -N "$work/a")" = 'Z,A,C,D,B,E,X' ]
    "$bin" --move X --before Z --no-backup "$work/a"
    [ "$("$bin" -N "$work/a")" = 'X,Z,A,C,D,B,E' ]

    # Paths from stdin can drive mutations too.
    printf '%s\n%s\n' "$work/a" "$work/b" | "$bin" --stdin --set ViaStdin --no-backup
    [ "$("$bin" -N "$work/a")" = 'ViaStdin' ]
    [ "$("$bin" -N "$work/b")" = 'ViaStdin' ]

    # Symlink operations target the referent only when explicitly requested.
    touch "$work/target-file"
    ln -s target-file "$work/file-link"
    "$bin" -L --set 'ViaLink' --no-backup "$work/file-link"
    [ "$("$bin" -N "$work/target-file")" = 'ViaLink' ]
    [ "$("$bin" -N "$work/file-link")" = 'ViaLink' ]

    # Hard links should naturally observe the same file metadata.
    ln "$work/target-file" "$work/hard-link"
    [ "$("$bin" -N "$work/hard-link")" = 'ViaLink' ]

    # Export/restore uses one root, includes hidden items by default, and
    # preserves the exact stored tag order.
    export_root="$work/export-root"
    restore_root="$work/restore-root"
    mkdir -p "$export_root/sub" "$export_root/real" "$export_root/.git" "$restore_root/sub" "$restore_root/real" "$restore_root/.git"
    touch "$export_root/alpha" "$export_root/.hidden" "$export_root/space name" "$export_root/sub/beta"
    touch "$export_root/real/linked-child"
    touch "$export_root/.git/config"
    touch "$restore_root/alpha" "$restore_root/.hidden" "$restore_root/space name" "$restore_root/sub/beta"
    touch "$restore_root/real/linked-child"
    touch "$restore_root/.git/config"
    ln -s real "$export_root/alias"
    ln -s missing "$export_root/dangling"
    ln -s real "$restore_root/alias"
    ln -s missing "$restore_root/dangling"

    "$bin" --set 'Second,First' --no-backup "$export_root/alpha"
    "$bin" --set HiddenTag --no-backup "$export_root/.hidden"
    "$bin" --set 'Nested,Tag' --no-backup "$export_root/sub/beta"
    "$bin" --set '"Project, Alpha","Needs review"' --no-backup "$export_root/space name"
    "$bin" --set Wrong --no-backup "$restore_root/alpha"
    "$bin" --set WrongHidden --no-backup "$restore_root/.hidden"
    "$bin" --set WrongNested --no-backup "$restore_root/sub/beta"
    "$bin" --set WrongSpace --no-backup "$restore_root/space name"
    "$bin" --set Keep --no-backup "$restore_root"

    default_export_archive="$work/export-default.jsonl"
    "$bin" --export "$export_root" >"$default_export_archive" 2>"$work/export-default.err"
    grep -Fq '"format":"jsonl"' "$default_export_archive"
    grep -Fq '"version":3' "$default_export_archive"
    grep -Fq '"fileInfo":true' "$default_export_archive"
    grep -Fq '"taggedOnly":false' "$default_export_archive"
    grep -Fq '"followSymlinks":false' "$default_export_archive"
    grep -Fq '"tagColors":' "$default_export_archive"
    grep -Fq '"path":".hidden"' "$default_export_archive"
    grep -Fq '"path":"space name"' "$default_export_archive"
    grep -Fq '"tags":["Second","First"]' "$default_export_archive"
    if grep -Fq '"destination"' "$default_export_archive"; then
        echo "default export unexpectedly recorded symlink target metadata" >&2
        exit 1
    fi
    if grep -Fq '"absolutePath"' "$default_export_archive"; then
        echo "export unexpectedly contains absolutePath" >&2
        exit 1
    fi
    grep -Fq '"type":"summary"' "$default_export_archive"

    excluded_archive="$work/export-excluded.jsonl"
    "$bin" --export --exclude '.git/' "$export_root" >"$excluded_archive" 2>"$work/export-excluded.err"
    grep -Fq '"exclude":[".git"]' "$excluded_archive"
    if grep -Fq '"path":".git"' "$excluded_archive" || \
       grep -Fq '"path":".git\\/config"' "$excluded_archive"; then
        echo "--exclude failed to omit .git subtree from export" >&2
        exit 1
    fi
    grep -Fq '"path":"alpha"' "$excluded_archive"

    # Canonical archives remain usable through ordinary compression pipelines.
    compressed_archive="$work/export-default.jsonl.gz"
    "$bin" --export "$export_root" 2>"$work/export-compressed.err" | gzip >"$compressed_archive"
    gzip -dc "$compressed_archive" | "$bin" --restore - --root "$restore_root" \
        --dry-run --no-backup >"$work/restore-piped.out" 2>"$work/restore-piped.err"
    grep -q 'would change' "$work/restore-piped.err"

    no_info_archive="$work/export-no-info.jsonl"
    "$bin" --export --no-file-info "$export_root" >"$no_info_archive" 2>"$work/export-no-info.err"
    grep -Fq '"fileInfo":false' "$no_info_archive"
    if grep -Fq '"mtime"' "$no_info_archive" || grep -Fq '"size"' "$no_info_archive"; then
        echo "--no-file-info unexpectedly emitted metadata" >&2
        exit 1
    fi

    tagged_archive="$work/export-tagged.jsonl"
    "$bin" --export --tagged-only "$export_root" >"$tagged_archive" 2>"$work/export-tagged.err"
    grep -Fq '"taggedOnly":true' "$tagged_archive"
    if grep -Fq '"path":"real"' "$tagged_archive"; then
        echo "--tagged-only unexpectedly emitted an untagged item" >&2
        exit 1
    fi

    reverse_archive="$work/export-reverse.jsonl"
    "$bin" --export -V "$export_root" >"$reverse_archive" 2>"$work/export-reverse.err"
    grep -q -- '--reverse is ignored during export' "$work/export-reverse.err"
    grep -Fq '"tags":["Second","First"]' "$reverse_archive"

    # Conversion is the human-facing view of canonical JSONL.
    "$bin" --convert "$default_export_archive" --slash --space-indent \
        >"$work/converted.out" 2>"$work/converted.err"
    grep -Eq '^\[[0-9]{8} +0MB\] \.?/?$' "$work/converted.out"
    grep -Fq '  Second,First' "$work/converted.out"
    "$bin" --convert "$default_export_archive" --reverse >"$work/reversed.out"
    grep -Fq 'First,Second' "$work/reversed.out"

    # -L records structural symlink metadata and follows symlinked directories.
    export_archive="$work/export-follow.jsonl"
    "$bin" --export -L "$export_root" >"$export_archive" 2>"$work/export-follow.err"
    grep -Fq '"followSymlinks":true' "$export_archive"
    grep -Fq '"destination":"real"' "$export_archive"
    grep -Fq '"targetKind":"directory"' "$export_archive"
    grep -Fq '"targetExists":false' "$export_archive"
    [ "$(grep -F -c '"path":"alias\/linked-child"' "$export_archive")" -eq 1 ]
    [ "$(grep -F -c '"path":"real\/linked-child"' "$export_archive")" -eq 1 ]
    if grep -Fq '"type":"symlink"' "$export_archive"; then
        echo "target metadata was emitted as a separate record" >&2
        exit 1
    fi
    "$bin" --convert "$export_archive" --slash --print-symlinks \
        >"$work/converted-follow.out" 2>"$work/converted-follow.err"
    grep -Fq 'alias@ -> real/' "$work/converted-follow.out"

    # A restore must use the archive's exact symlink-following mode.
    if "$bin" --restore "$export_archive" --root "$restore_root" --no-backup \
        >"$work/mismatch.out" 2>"$work/mismatch.err"; then
        echo "restore unexpectedly accepted an -L archive without -L" >&2
        exit 1
    fi
    grep -q 'follow-symlinks mode' "$work/mismatch.err"

    restore_dry_output="$work/restore-dry.out"
    restore_dry_error="$work/restore-dry.err"
    "$bin" --restore "$default_export_archive" --root "$restore_root" --dry-run --no-backup \
        >"$restore_dry_output" 2>"$restore_dry_error"
    grep -q 'would change' "$restore_dry_error"
    grep -q 'would clear' "$restore_dry_error"
    grep -q '\[dry-run\] restore' "$restore_dry_output"
    [ "$("$bin" -N "$restore_root/alpha")" = 'Wrong' ]

    # Delete one archived item to exercise the easy-to-count missing-item case.
    rm "$restore_root/sub/beta"
    if "$bin" --restore "$default_export_archive" --root "$restore_root" --no-backup \
        >"$work/restore.out" 2>"$work/restore.err"; then
        :
    fi
    grep -q 'missing' "$work/restore.err"
    grep -q '1 missing' "$work/restore.err"
    grep -q 'cleared' "$work/restore.err"
    [ "$("$bin" -N "$restore_root/alpha")" = 'Second,First' ]
    [ "$("$bin" -N "$restore_root/.hidden")" = 'HiddenTag' ]
    [ "$("$bin" -N "$restore_root/space name")" = 'Project, Alpha,Needs review' ]
    touch "$restore_root/sub/beta"

    # The complete archive is validated before any listed item is changed.
    header=$(sed -n '1p' "$default_export_archive")
    root_record=$(sed -n '2p' "$default_export_archive")
    item_record=$(grep '"path":"alpha"' "$default_export_archive")
    duplicate_archive="$work/duplicate.jsonl"
    printf '%s\n%s\n%s\n%s\n' "$header" "$root_record" "$item_record" "$item_record" >"$duplicate_archive"
    "$bin" --set BeforeValidation --no-backup "$restore_root/alpha"
    if "$bin" --restore "$duplicate_archive" --root "$restore_root" --no-backup \
        >"$work/duplicate.out" 2>"$work/duplicate.err"; then
        echo "duplicate archive unexpectedly restored" >&2
        exit 1
    fi
    grep -q 'duplicate archive item' "$work/duplicate.err"
    [ "$("$bin" -N "$restore_root/alpha")" = 'BeforeValidation' ]

    malformed_archive="$work/malformed.jsonl"
    printf '%s\n%s\n%s\n' "$header" "$root_record" '{not-json}' >"$malformed_archive"
    if "$bin" --restore "$malformed_archive" --root "$restore_root" --no-backup \
        >"$work/malformed.out" 2>"$work/malformed.err"; then
        echo "malformed archive unexpectedly restored" >&2
        exit 1
    fi
    grep -q 'archive line' "$work/malformed.err"

    kind_archive="$work/kind-mismatch.jsonl"
    printf '%s\n%s\n%s\n' "$header" "$root_record" \
        '{"kind":"directory","path":"alpha","tags":["Hacked"],"type":"item"}' >"$kind_archive"
    if "$bin" --restore "$kind_archive" --root "$restore_root" --no-backup \
        >"$work/kind.out" 2>"$work/kind.err"; then
        echo "kind-mismatch archive unexpectedly restored" >&2
        exit 1
    fi
    grep -q 'restore item type changed' "$work/kind.err"
    [ "$("$bin" -N "$restore_root/alpha")" = 'BeforeValidation' ]

    escape_archive="$work/escape.jsonl"
    printf '%s\n%s\n%s\n' "$header" "$root_record" \
        '{"kind":"file","path":"../alpha","tags":["Hacked"],"type":"item"}' >"$escape_archive"
    if "$bin" --restore "$escape_archive" --root "$restore_root" --no-backup \
        >"$work/escape.out" 2>"$work/escape.err"; then
        echo "path-escape archive unexpectedly restored" >&2
        exit 1
    fi
    grep -q 'invalid archive item path' "$work/escape.err"
    [ "$("$bin" -N "$restore_root/alpha")" = 'BeforeValidation' ]

    # Explicit undo archives use the same canonical JSONL format, capture the
    # preimage immediately before the mutation, and can themselves be restored.
    undo_archive="$work/undo.jsonl"
    "$bin" --set UndoNew --backup "$undo_archive" "$restore_root/alpha" \
        2>"$work/undo.err"
    grep -Fq '"format":"jsonl"' "$undo_archive"
    grep -Fq '"purpose":"undo"' "$undo_archive"
    "$bin" --restore "$undo_archive" --no-backup >/dev/null
    [ "$("$bin" -N "$restore_root/alpha")" = 'BeforeValidation' ]

    # The default undo archive is created in the system temporary directory.
    "$bin" --set DefaultUndo "$restore_root/alpha" 2>"$work/default-undo.err"
    grep -q 'undo archive:' "$work/default-undo.err"
    default_undo=$(sed -n 's/.*undo archive: //p' "$work/default-undo.err" | tail -n 1)
    if [ -n "$default_undo" ] && [ -f "$default_undo" ]; then
        rm -f "$default_undo"
    fi

    "$bin" --set 'X,Y' --jsonl --no-backup "$work/b" | grep -q '"dryRun":false'
    [ "$("$bin" -N "$work/b")" = 'X,Y' ]
fi

# Tag writes must not change mtime. Keep this outside the macOS-only integration
# block so every supported test environment exercises the invariant.
touch "$work/mtime-file"
if [ "$(uname -s)" = Darwin ]; then
    mtime_before=$(stat -f %m "$work/mtime-file")
else
    mtime_before=$(stat -c %Y "$work/mtime-file")
fi
"$bin" --set MtimeTest --no-backup "$work/mtime-file"
if [ "$(uname -s)" = Darwin ]; then
    mtime_after=$(stat -f %m "$work/mtime-file")
else
    mtime_after=$(stat -c %Y "$work/mtime-file")
fi
[ "$mtime_before" = "$mtime_after" ]

echo "CLI tests passed"
