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
"$bin" --help | grep -q -- '--export'
"$bin" --help | grep -q -- '--restore ARCHIVE'
"$bin" --help | grep -q -- '--tagged-only'
"$bin" --help | grep -q -- '--file-info'
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
if printf '%s\n' "$json_recursive" | grep -q '"absolutePath"'; then
    echo "recursive JSONL unexpectedly repeated absolutePath" >&2
    exit 1
fi

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
printf '%s\n' "$file_info_directory" | grep -Eq '\[[0-9]{8} 0MB\]'

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

    # Symlink operations target the referent by default.
    touch "$work/target-file"
    ln -s target-file "$work/file-link"
    "$bin" --set 'ViaLink' --no-backup "$work/file-link"
    [ "$("$bin" -N "$work/target-file")" = 'ViaLink' ]
    [ "$("$bin" -N "$work/file-link")" = 'ViaLink' ]

    # Hard links should naturally observe the same file metadata.
    ln "$work/target-file" "$work/hard-link"
    [ "$("$bin" -N "$work/hard-link")" = 'ViaLink' ]

    # Export/restore uses one root, includes hidden items by default, and
    # preserves the exact stored tag order.
    export_root="$work/export-root"
    restore_root="$work/restore-root"
    mkdir -p "$export_root/sub" "$export_root/real" "$restore_root/sub"
    touch "$export_root/alpha" "$export_root/.hidden" "$export_root/space name" "$export_root/sub/beta"
    touch "$restore_root/alpha" "$restore_root/.hidden" "$restore_root/space name" "$restore_root/sub/beta"
    ln -s real "$export_root/alias"

    "$bin" --set 'Second,First' --no-backup "$export_root/alpha"
    "$bin" --set HiddenTag --no-backup "$export_root/.hidden"
    "$bin" --set 'Nested,Tag' --no-backup "$export_root/sub/beta"
    "$bin" --set '"Project, Alpha","Needs review"' --no-backup "$export_root/space name"
    "$bin" --set Wrong --no-backup "$restore_root/alpha"
    "$bin" --set WrongHidden --no-backup "$restore_root/.hidden"
    "$bin" --set WrongNested --no-backup "$restore_root/sub/beta"
    "$bin" --set WrongSpace --no-backup "$restore_root/space name"
    "$bin" --set Keep --no-backup "$restore_root"

    export_archive="$work/export.archive"
    "$bin" --export "$export_root" >"$export_archive" 2>"$work/export.err"
    grep -Fq '# finder-tags archive v1' "$export_archive"
    grep -Fq '.hidden' "$export_archive"
    grep -Fq 'alpha' "$export_archive"
    grep -Fq '"space name"' "$export_archive"
    grep -Fq '"Project, Alpha"' "$export_archive"
    grep -Fq '@symlink' "$export_archive"
    grep -q 'exported 4 tagged items' "$work/export.err"

    metadata_archive="$work/export-metadata.archive"
    "$bin" --export --file-info "$export_root" >"$metadata_archive" 2>"$work/export-metadata.err"
    grep -q '^@metadata ' "$metadata_archive"
    grep -q 'exported 4 tagged items' "$work/export-metadata.err"
    "$bin" --restore "$metadata_archive" --root "$restore_root" --dry-run --no-backup \
        >"$work/metadata-restore.out" 2>"$work/metadata-restore.err"

    restore_dry_output="$work/restore-dry.out"
    restore_dry_error="$work/restore-dry.err"
    "$bin" --restore "$export_archive" --root "$restore_root" --dry-run --no-backup \
        >"$restore_dry_output" 2>"$restore_dry_error"
    grep -q 'would change' "$restore_dry_error"
    grep -q 'warnings' "$restore_dry_error"
    grep -q '\[dry-run\] restore' "$restore_dry_output"
    [ "$("$bin" -N "$restore_root/alpha")" = 'Wrong' ]
    [ "$("$bin" -N "$restore_root/.hidden")" = 'WrongHidden' ]
    [ "$("$bin" -N "$restore_root/sub/beta")" = 'WrongNested' ]

    "$bin" --restore "$export_archive" --root "$restore_root" --no-backup \
        >"$work/restore.out" 2>"$work/restore.err"
    grep -q 'restored 4 files' "$work/restore.err"
    grep -q 'following the current target' "$work/restore.err"
    [ "$("$bin" -N "$restore_root/alpha")" = 'Second,First' ]
    [ "$("$bin" -N "$restore_root/.hidden")" = 'HiddenTag' ]
    [ "$("$bin" -N "$restore_root/sub/beta")" = 'Nested,Tag' ]
    [ "$("$bin" -N "$restore_root/space name")" = 'Project, Alpha,Needs review' ]
    [ "$("$bin" -N "$restore_root")" = 'Keep' ]

    json_archive="$work/export.jsonl"
    "$bin" --export --jsonl "$export_root" >"$json_archive"
    grep -q '"type":"summary"' "$json_archive"
    if grep -q '"absolutePath"' "$json_archive"; then
        echo "export JSONL unexpectedly contains absolutePath" >&2
        exit 1
    fi
    "$bin" --restore "$json_archive" --root "$restore_root" --jsonl --dry-run --no-backup \
        >"$work/json-restore.out"
    grep -q '"type":"summary"' "$work/json-restore.out"

    colored_archive="$work/colored.archive"
    printf '%s\n' '# finder-tags archive v1' "@root $export_root" >"$colored_archive"
    printf '\033[31malpha\033[0m\t\033[31mColorized\033[0m\n' >>"$colored_archive"
    "$bin" --restore "$colored_archive" --root "$restore_root" --dry-run --no-backup \
        >"$work/colored.out"
    grep -q 'Colorized' "$work/colored.out"
    [ "$("$bin" -N "$restore_root/alpha")" = 'Second,First' ]

    # The complete archive is validated before any listed item is changed.
    malformed_archive="$work/malformed.archive"
    printf '%s\n' '# finder-tags archive v1' "@root $export_root" >"$malformed_archive"
    printf '%s\t%s\n' alpha Rejected >>"$malformed_archive"
    printf '%s\n' 'not an archive record' >>"$malformed_archive"
    if "$bin" --restore "$malformed_archive" --root "$restore_root" --no-backup \
        >"$work/malformed.out" 2>"$work/malformed.err"; then
        echo "malformed archive unexpectedly restored" >&2
        exit 1
    fi
    grep -q 'archive line' "$work/malformed.err"
    [ "$("$bin" -N "$restore_root/alpha")" = 'Second,First' ]

    duplicate_archive="$work/duplicate.archive"
    printf '%s\n' '# finder-tags archive v1' "@root $export_root" >"$duplicate_archive"
    printf '%s\t%s\n' alpha First >>"$duplicate_archive"
    printf '%s\t%s\n' alpha Second >>"$duplicate_archive"
    if "$bin" --restore "$duplicate_archive" --root "$restore_root" --no-backup \
        >"$work/duplicate.out" 2>"$work/duplicate.err"; then
        echo "duplicate archive unexpectedly restored" >&2
        exit 1
    fi
    grep -q 'duplicate archive item' "$work/duplicate.err"
    [ "$("$bin" -N "$restore_root/alpha")" = 'Second,First' ]

    escape_archive="$work/escape.archive"
    printf '%s\n' '# finder-tags archive v1' "@root $export_root" >"$escape_archive"
    printf '%s\t%s\n' ../alpha Hacked >>"$escape_archive"
    if "$bin" --restore "$escape_archive" --root "$restore_root" --no-backup \
        >"$work/escape.out" 2>"$work/escape.err"; then
        echo "path-escape archive unexpectedly restored" >&2
        exit 1
    fi
    grep -q 'invalid archive item path' "$work/escape.err"
    [ "$("$bin" -N "$restore_root/alpha")" = 'Second,First' ]

    # Tag writes must not change mtime on the supported macOS filesystem.
    touch "$work/mtime-file"
    mtime_before=$(stat -f %m "$work/mtime-file")
    "$bin" --set MtimeTest --no-backup "$work/mtime-file"
    mtime_after=$(stat -f %m "$work/mtime-file")
    [ "$mtime_before" = "$mtime_after" ]

    # Explicit undo archives capture the preimage immediately before the
    # mutation and can themselves be restored.
    undo_archive="$work/undo.archive"
    "$bin" --set UndoNew --backup "$undo_archive" "$restore_root/alpha" \
        2>"$work/undo.err"
    grep -Fq 'alpha' "$undo_archive"
    "$bin" --restore "$undo_archive" --no-backup >/dev/null
    [ "$("$bin" -N "$restore_root/alpha")" = 'Second,First' ]

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

echo "CLI tests passed"
