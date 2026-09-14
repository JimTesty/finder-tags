#!/bin/sh
set -eu

ours_arg=${1:?usage: compat-jdberry.sh OUR_TAG JDBERRY_TAG}
ref_arg=${2:?usage: compat-jdberry.sh OUR_TAG JDBERRY_TAG}

case "$ours_arg" in /*) ours=$ours_arg ;; *) ours="$(pwd)/$ours_arg" ;; esac
case "$ref_arg" in /*) ref=$ref_arg ;; *) ref="$(pwd)/$ref_arg" ;; esac

if [ "$(uname -s)" != Darwin ]; then
    echo "compat-jdberry.sh: requires macOS" >&2
    exit 77
fi
if [ ! -x "$ours" ]; then echo "not executable: $ours" >&2; exit 64; fi
if [ ! -x "$ref" ]; then echo "not executable: $ref" >&2; exit 64; fi

repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
work="$repo/Tests/.compat-work.$$"
left="$work/ours"
right="$work/jdberry"
rm -rf "$work"
mkdir -p "$left/tree/sub" "$right/tree/sub"
trap 'rm -rf "$work"' EXIT HUP INT TERM

setup_tree() {
    root=$1
    touch "$root/a" "$root/b" "$root/empty" "$root/space name"
    touch "$root/tree/root-file" "$root/tree/sub/child" "$root/tree/.hidden"
    mkdir -p "$root/tree/dir"
}
setup_tree "$left"
setup_tree "$right"

pass=0
failures=0
soft=0

run_one() {
    bin=$1
    root=$2
    out=$3
    shift 3
    (cd "$root" && "$bin" "$@") >"$out" 2>"$out.err"
}

compare_exact() {
    label=$1
    shift
    lo="$work/left.out"
    ro="$work/right.out"
    if run_one "$ours" "$left" "$lo" "$@" && run_one "$ref" "$right" "$ro" "$@"; then
        if cmp -s "$lo" "$ro"; then
            echo "PASS  $label"
            pass=$((pass + 1))
        else
            echo "FAIL  $label"
            diff -u "$ro" "$lo" || true
            failures=$((failures + 1))
        fi
    else
        echo "FAIL  $label (exit status differs/fails)"
        echo "ours stderr:"; cat "$lo.err" || true
        echo "jdberry stderr:"; cat "$ro.err" || true
        failures=$((failures + 1))
    fi
}

compare_sorted() {
    label=$1
    shift
    lo="$work/left.out"
    ro="$work/right.out"
    if run_one "$ours" "$left" "$lo" "$@" && run_one "$ref" "$right" "$ro" "$@"; then
        LC_ALL=C sort "$lo" >"$lo.sorted"
        LC_ALL=C sort "$ro" >"$ro.sorted"
        if cmp -s "$lo.sorted" "$ro.sorted"; then
            echo "PASS  $label (order-insensitive)"
            pass=$((pass + 1))
        else
            echo "FAIL  $label"
            diff -u "$ro.sorted" "$lo.sorted" || true
            failures=$((failures + 1))
        fi
    else
        echo "FAIL  $label (exit status differs/fails)"
        failures=$((failures + 1))
    fi
}

# Untagged listing/traversal/output formatting.
compare_sorted "default current-directory list" 
compare_exact "explicit untagged file" a
compare_sorted "enter directory (-e)" -e tree
compare_sorted "recursive directory (-R)" -R tree
compare_sorted "recursive alias (-d)" -d tree
compare_sorted "hidden enumeration (-Ae)" -Ae tree
compare_exact "directory slash (-p)" -p tree
compare_exact "filename off (-N) on untagged file" -N a
compare_exact "tags off (-T)" -T a

# Set one tag independently in each tree so order cannot differ.
(cd "$left" && "$ours" --set Red a)
(cd "$right" && "$ref" --set Red a)
compare_exact "set/list one tag" a
compare_exact "no filename (-N)" -N a
compare_exact "one-per-line (-g)" -g a
compare_exact "color in a pipe is plain" -c -N a
compare_exact "long --name alias" --name a
compare_exact "long --garrulous alias" --garrulous a

# Add/remove one tag on a fresh file.
(cd "$left" && "$ours" --add Blue b)
(cd "$right" && "$ref" --add Blue b)
compare_exact "add one tag" b
(cd "$left" && "$ours" --remove Blue b)
(cd "$right" && "$ref" --remove Blue b)
compare_exact "remove one tag" b

# Match semantics, including case-insensitive matching and wildcards.
compare_exact "match one tag" --match Red a
compare_exact "match is case-insensitive" --match red a
compare_sorted "match any tag" --match '*' a b empty
compare_sorted "match no tags" --match '' a b empty
compare_exact "match with tags (-t)" -tm Red a
compare_exact "combined short flags" -tgm Red a

# NUL output is compared byte-for-byte.
compare_exact "NUL termination (-0)" -0 a

# Recursive mutation should touch the explicit directory plus descendants in
# both programs. Use one tag only to avoid the intentional ordering difference.
(cd "$left" && "$ours" --set Walk -R tree)
(cd "$right" && "$ref" --set Walk -R tree)
compare_sorted "recursive mutation + list" -te tree

# Deliberate difference: ours preserves B,A, upstream sorts display as A,B.
(cd "$left" && "$ours" --set 'B,A' a)
(cd "$right" && "$ref" --set 'B,A' a)
lo="$work/order-left.out"; ro="$work/order-right.out"
run_one "$ours" "$left" "$lo" -N a
run_one "$ref" "$right" "$ro" -N a
if [ "$(cat "$lo")" = 'B,A' ]; then
    echo "PASS  intentional ordered-tag difference (ours preserves B,A)"
    pass=$((pass + 1))
else
    echo "FAIL  ours did not preserve requested B,A order"
    failures=$((failures + 1))
fi

# Opt-in sorted display should reproduce jdberry/tag's normal display order
# without changing finder-tags' default stored order.
(cd "$left" && "$ours" --sorted-tags -N a) >"$work/sorted-ours"
(cd "$right" && "$ref" -N a) >"$work/sorted-ref"
if cmp -s "$work/sorted-ours" "$work/sorted-ref"; then
    echo "PASS  --sorted-tags display matches jdberry/tag"
    pass=$((pass + 1))
else
    echo "FAIL  --sorted-tags display differs from jdberry/tag"
    diff -u "$work/sorted-ref" "$work/sorted-ours" || true
    failures=$((failures + 1))
fi

# Sorted mutation result should also display compatibly afterward.
(cd "$left" && "$ours" --set 'B,A' --sorted-tags empty)
(cd "$right" && "$ref" --set 'B,A' empty)
lo="$work/sorted-mutation-ours"; ro="$work/sorted-mutation-ref"
(cd "$left" && "$ours" -N empty) >"$lo"
(cd "$right" && "$ref" -N empty) >"$ro"
if cmp -s "$lo" "$ro"; then
    echo "PASS  sorted mutation display matches jdberry/tag"
    pass=$((pass + 1))
else
    echo "FAIL  sorted mutation display differs from jdberry/tag"
    diff -u "$ro" "$lo" || true
    failures=$((failures + 1))
fi

# --usage is intentionally not a strict compatibility test: jdberry/tag uses
# Spotlight and finder-tags directly traverses the supplied scope. Fresh test
# files may not be indexed by Spotlight yet. Run both and show normalized data.
echo "INFO  --usage differs by design (Spotlight vs direct traversal); sample outputs:"
(cd "$left" && "$ours" --usage '*' .) >"$work/usage-ours" 2>"$work/usage-ours.err" || true
(cd "$right" && "$ref" --usage '*' .) >"$work/usage-ref" 2>"$work/usage-ref.err" || true
echo "  finder-tags:"; sed 's/^/    /' "$work/usage-ours"
echo "  jdberry/tag:"; sed 's/^/    /' "$work/usage-ref"
soft=$((soft + 1))

# --find is also Spotlight-backed in both programs, but fresh fixture indexing
# can lag. Exercise both implementations without making timing a strict test.
echo "INFO  --find sample outputs (fresh Spotlight indexing may differ):"
(cd "$left" && "$ours" --find Red .) >"$work/find-ours" 2>"$work/find-ours.err" || true
(cd "$right" && "$ref" --find Red .) >"$work/find-ref" 2>"$work/find-ref.err" || true
echo "  finder-tags:"; sed 's/^/    /' "$work/find-ours"
echo "  jdberry/tag:"; sed 's/^/    /' "$work/find-ref"
soft=$((soft + 1))

# Upstream does not understand the new quoted-comma grammar, --case-sensitive,
# --copy, ordered placement/move controls, --reverse, --absolute, stdin path
# input, --jsonl, --no-follow-symlinks, or --dry-run; those are covered by
# Tests/cli.sh rather than differential tests. --find is also not strict here
# because fresh fixtures may not be indexed yet.

echo
echo "$pass strict compatibility checks passed; $soft informational difference(s); $failures failure(s)."
[ "$failures" -eq 0 ]
