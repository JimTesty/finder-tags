# finder-tags

`finder-tags` is a small Swift command-line tool for macOS Finder tags. It
builds/installs an executable named **`tag`** and is deliberately
usage-compatible with [`jdberry/tag`](https://github.com/jdberry/tag) where
practical.

Its main difference is intentional: **Finder tag order is preserved by
default** on reads and writes instead of sorting tags or passing them through
unordered sets. `--sorted-tags` provides an opt-in sorted mode when that is
preferred.

## Development status

This project is new and **not thoroughly tested yet**. It has a broad shell test
suite, macOS-only integration tests for real Finder-tag operations, and an
optional differential test suite against `jdberry/tag`, but it has not been
exercised broadly across macOS releases, filesystems, network volumes, or large
data sets.

Most of the source code was written by **OpenAI GPT-5.6 Sol**, under the
maintainer's direction and with iterative human testing/review.

See [`REVIEW.md`](REVIEW.md) for the current source review and known limitations.

## Build and install

The build uses **plain `swiftc` only**. It does not require Swift Package
Manager, XCTest, Xcode, or a `Package.swift` file.

```sh
make                  # build/tag
make test             # self-tests; macOS also exercises real Finder tags
make install          # installs to ~/.local by default
```

To choose another install prefix:

```sh
make install PREFIX=/usr/local
```

`make install` installs the binary, man page, and Bash/Zsh/Fish completions.
For development without installing:

```sh
./tag --help
```

The top-level `./tag` wrapper runs `make build` and then executes `build/tag`.
Unchanged sources are not recompiled.

### Compatibility testing against jdberry/tag

If you have `jdberry/tag` installed separately, run:

```sh
make compat JDBERRY_TAG=/path/to/jdberry/tag
```

`Tests/compat-jdberry.sh` creates its test data **inside this repository's
`Tests/` directory**, compares common behavior, and cleans up afterward. It
does not intentionally modify files elsewhere.

The compatibility suite does not strictly compare `--usage`, because
`jdberry/tag` uses Spotlight while `finder-tags` directly traverses the supplied
paths, and freshly created test files may not yet be indexed by Spotlight.

## Common examples

```sh
tag                                  # list current directory
tag file1 file2                      # list explicit files and ordered tags
tag -c file                          # approximate Finder tag colors
tag -V file                          # display tags in reverse order
tag --sorted-tags file              # sorted display, without rewriting

tag -a 'Work,Important' file         # append new tags
tag --prepend Urgent file            # insert first/left/bottom
tag -a Urgent --at 1 file            # zero-based insertion position
tag -a Review --before Done file      # insert relative to another tag
tag --move Urgent top file            # move to last/right/top
tag --move Urgent --after Review file # neighbor-relative move
tag -r 'Work,Old' file               # remove matching tags
tag -r '*' file                      # remove all tags
tag -s 'First,Second' file           # replace tags in exactly this order
tag --copy src dst                   # destructively copy tag array/order
tag --copy src dst --dry-run         # preview copy, do not write

tag -m 'Work,Important' file1 file2
tag --match '*' -R directory         # files with any tag
tag --usage '*' -R directory         # count tags on tagged files
tag --find Work ~/Documents          # Spotlight-backed search

tag --absolute -R directory          # absolute logical output paths
tag --jsonl file1 file2              # streaming structured output
find files -print0 | tag --stdin0 -T # read NUL-delimited paths

tag --export --exclude .git/ directory > tags.archive
tag --convert tags.archive --slash --space-indent
tag --export directory | gzip > tags.archive.gz
tag --restore tags.archive --root restored-directory --dry-run
gzip -dc tags.archive.gz | tag --restore - --root restored-directory
```

## Export and restore

`--export` writes a versioned, root-relative JSONL archive for one directory.
It includes hidden and untagged items by default and preserves each stored tag
array exactly. Archive storage is JSONL only. Use `--convert` when a
human-readable listing is wanted; converted output is presentation-only and is
not accepted by `--restore`.

`--restore ARCHIVE` accepts an archive path or `-` for stdin. `--root DEST`
relocates the archive's one root. Restore changes only listed existing items;
it does not create or delete files. Empty `tags` arrays explicitly clear tags;
an omitted `tags` field means tags were unavailable and must not be changed.
An archive containing only tagged items does not clear tags from unlisted items.
The final summary reports visited, restored/changed, cleared, unchanged,
missing, errors, and symlink warnings. `--dry-run` performs the same reads and
comparisons without changing tags.

Before a real restore writes anything, the complete JSONL archive is read and
validated. The header records the archive version, symlink following mode,
file-info setting, tagged-only setting, exclusions, and a copy of Finder's
tag-color definitions. Item paths are relative and must not escape the selected root.
Duplicate logical paths and malformed records are rejected before any tag is
changed. This does not make filesystem changes transactional if a later
metadata write fails.

`--file-info` adds each item's byte size and content modification time (`mtime`,
as a UTC-based Unix timestamp) to list and export output. Export enables it by
default; `--no-file-info` disables it. JSONL stores numeric `size` and `mtime`
fields. Restore ignores them, so they are available for later change-detection
tooling without affecting tag restoration.
Human-readable `--file-info` listings render metadata as `[DATE SIZE]`: DATE is
`yyyyMMdd`, and SIZE is a right-aligned, rounded binary-megabyte field
(`~0MB` means a nonempty file below 0.5 MiB). Directories are shown as `0MB`.
JSONL and the archive retain exact numeric values. `--convert` uses the same
human formatter as ordinary listings; `--space-indent` separates a filename
and its tags with two spaces instead of the usual tab/alignment separator.
The human date is for display only; use JSONL/archive values for stable
change detection.

`--exclude PATH` skips matching items and their descendants during filesystem
traversal. It may be repeated. A single component such as `.git/` matches that
name at any depth; a path containing `/` is relative to each traversal root.
Trailing slashes are accepted and omitted from the normalized patterns stored
in an export header. Exclusions do not delete anything, and restore never
modifies items that are absent from the archive.

Symlinks are not followed by default. `--follow-symlinks`/`-L` resolves and
follows symlinks, including symlinked directories during recursion. With `-L`,
an item may include the literal stored link destination and target type or
existence information, but target tags are never nested in symlink metadata.
Target descendants reached through a followed symlink are ordinary item
records. Consequently, a physical subtree reachable through both a direct path
and a symlink can occur twice under its two logical paths; v1 does not attempt
inode-based deduplication.
Restore requires the same `-L` setting recorded by the archive. If a followed
symlink now has a different literal destination, restore warns and follows the
current target.
`--no-follow-symlinks` is retained as an explicit defensive spelling.

`--slash` appends `/` to directories and `@` to symlinks, like `ls -F`.
`--print-symlinks` additionally prints the link's stored destination, for
example `link@ -> ../target/`; the target slash follows `--slash`, and missing
targets are marked `(NOT FOUND)` in red when color is enabled. Printing a
symlink target does not cause traversal or tag I/O to follow it.
When converting an archive that did not record target information, the
converter reports that the target was not recorded rather than guessing.

Mutating operations write a per-file undo archive by default in the system
temporary directory. The archive path is printed to stderr when the first
change needs it. Use `--no-backup` to disable this, `--backup PATH` to choose a
path, or `--sync-backup` to sync each undo record before its mutation. Syncing
is intentionally opt-in because it can be expensive.

Export output can be piped through ordinary compressors, and restore can read
such a pipeline through stdin. The default undo archive is a local temporary
file rather than a pipe so each preimage is available immediately before its
corresponding mutation. Managed compressed undo journals and stronger crash
atomicity are future work.

## Ordering

By default, no operation intentionally sorts the stored tag array:

* **list:** outputs the stored array in its returned order.
* **add/append:** preserves existing order; new tags are inserted at the chosen
  position, last by default.
* **prepend:** `--add ... --at first` convenience form.
* **remove:** filters the existing array, preserving survivor order.
* **set:** writes tags in command-line order.
* **move:** removes one matched tag and reinserts it at the chosen position.
* **copy:** writes the source array to the destination unchanged.
* **match/find:** display each matching file's stored order when tags are shown.
* **usage:** aggregate output is in first-seen exact-tag order.
* **reverse:** reverses display. During export it is ignored so archives always
  store the natural order. It never rewrites live metadata merely because it is
  selected.

`--sorted-tags` is explicitly opt-in. For read-only operations it sorts only
the displayed/aggregate output and **does not write metadata**. For mutating
operations it sorts the final array before it is written. Sorting uses
Foundation `String.compare`, corresponding closely to `jdberry/tag`'s
`NSString compare:` sorting.

`--reverse` is applied after display sorting, so `--sorted-tags --reverse`
shows descending order. On mutations, `--reverse` remains display-only.
When `--sorted-tags` is combined with `--at`, `--before`, `--after`, or
`--move`, the edit is applied first and the final mutation result is then
sorted, so the explicit placement is naturally superseded by the sort.

## Placement

`--at` and `--move` accept a zero-based numeric insertion index or:

* `first`, `left`, `bottom` = index 0
* `last`, `right`, `top` = the end

The Finder wording can feel vertically backwards: the **last/rightmost** tag's
color is drawn **on top**, hence `top = last` and `bottom = first`.

`--before TAG` and `--after TAG` can be used with `--add` or `--move` when a
neighbor is more convenient than calculating an index:

```sh
tag --add Pending --before Done file
tag --move Pending --after Review file
```

Anchor matching follows the normal case-sensitivity rules and reports an
ambiguity instead of guessing among multiple case-fold-equivalent tags.

## Case sensitivity

Finder-style matching is **case-insensitive by default**, but stored spelling is
preserved as data. Case-distinct tags are not globally collapsed or merged.

For example:

```text
existing: red,orange,yellow
tag --add Orange file
result:   red,Orange,yellow
```

Because `orange` is the unique case-insensitive match, `--add Orange` re-cases
it **in place** rather than creating a duplicate.

With `-C/--case-sensitive`, only exact spelling matches:

```text
existing: red,orange,yellow
tag -C --add Orange file
result:   red,orange,yellow,Orange
```

If case-insensitive matching finds multiple stored variants and no exact match,
operations that need one specific tag report ambiguity rather than arbitrarily
choosing one. An add expression that explicitly requests case-distinct variants,
for example `orange,Orange`, preserves both.

`--case-sensitive` affects add/remove/move/placement/match/usage/find matching.
`--set` always stores the exact spellings supplied. Usage counts keep `orange`
and `Orange` as separate entries even in the default matching mode.

## Tags containing spaces, commas, and quotes

Normal shell quoting handles spaces:

```sh
tag --add "Needs review" file
```

The TAGS parser also understands single- or double-quoted CSV-style components,
which allows literal commas inside a tag:

```sh
tag --set 'Red,"Project, Alpha","Needs review"' file
```

That represents exactly three tags. A doubled quote inside a quoted component
represents one literal quote, CSV-style. Unquoted components have surrounding
whitespace trimmed; whitespace inside quoted components is preserved.

Tag names containing CR, LF, or NUL are rejected. In particular, Foundation's
Finder-tag API can accept a write containing a newline but read back only the
prefix, so treating such a write as successful would silently corrupt the tag.

The normal comma-separated **list** output is inherently ambiguous when tag
names contain commas. Use `--jsonl` for machine consumption or
`--one-per-line` when a simple text format is sufficient. JSONL export stores
paths and tags as proper JSON strings and arrays. `--convert` is intended for
human-readable output rather than round-tripping.

`*` remains reserved for wildcard behavior in `--match`, `--usage`, `--find`,
and `--remove`.

## Match, usage, and find

`--match TAGS` / `-m TAGS` follows `jdberry/tag` semantics where applicable:

* `A,B` requires all specified tags.
* matching is case-insensitive unless `--case-sensitive` is supplied.
* `'*'` matches files having at least one tag.
* `''` matches files having no tags.
* with no paths, the current directory is enumerated.

Match output defaults to filenames only. Use `-t/--tags` to include tags.

`--usage TAGS` / `-u TAGS` counts **all tags on files matching TAGS**. Unlike
`jdberry/tag`, it does not use Spotlight; it directly traverses supplied paths
and honors `-A`, `-e`, and `-R`. `TAGS` is intentionally required; use:

```sh
tag --usage '*' PATH
tag --usage Work PATH
```

`--find TAGS` / `-f TAGS` uses macOS Spotlight (`NSMetadataQuery`), then rereads
the current Foundation tag array for each result so displayed ordering does not
come from the metadata index. Supplied paths become Spotlight search scopes.
`--home`, `--local`, and `--network` are not currently implemented.

## Paths, stdin, and symbolic links

With explicit directories, `-e`/`-R` output follows `jdberry/tag`: the explicit
directory is printed using the argument spelling, while descendants are shown
relative to that directory. `--absolute` instead emits absolute logical paths.

Additional paths can be streamed on stdin:

```sh
printf '%s\n' file1 file2 | tag --stdin
generate_paths | tag --stdin0 --set Reviewed
```

`--stdin` is newline-delimited. `--stdin0` is NUL-delimited and is preferred for
arbitrary filenames. Command-line and stdin paths are combined. Explicitly
requesting stdin and providing no paths processes zero files instead of falling
back to the current directory.

Symbolic links are **not followed by default**. `--follow-symlinks`/`-L` makes
Finder generally present the target file's tags and makes recursive traversal
follow symlinked directories while suppressing directory cycles.

`--no-follow-symlinks` is the default for recursive work: it does not descend
into symlinked directories and does not explicitly resolve symlink paths before
Foundation tag I/O. This prevents a recursive mutation from escaping its
starting tree through a directory symlink.

## `--dry-run`

Valid with `--add`, `--remove`, `--set`, `--move`, `--copy`, and `--restore`. It
performs the normal metadata reads and computes the exact before/after arrays,
but does not write.

Text output shows the before/after arrays. With `--jsonl`, each record contains
`operation`, `path`, `before`, `after`, `changed`, and `dryRun`; copy records
also contain source path information.

## JSON Lines / NDJSON

`--jsonl` (alias `--ndjson`) emits one JSON object per line for normal list and
mutation output. `--export` always uses the canonical JSONL archive format,
whether or not `--jsonl` is written. Export streams a header, one root record,
item records, and a final `summary` record.

Example:

```json
{"exclude":[],"fileInfo":true,"followSymlinks":false,"format":"jsonl","purpose":"export","taggedOnly":false,"type":"header","version":3}
{"type":"root","path":"/tmp/tree"}
{"kind":"file","mtime":1780000000,"path":"file","size":1234,"tags":["First","Second"],"type":"item"}
```

With `--file-info`, file records also contain numeric `size` and `mtime`
fields.

For `--usage`, records contain `tag` and `count`. Mutations emit before/after
records after a successful write; dry runs emit the same shape with
`"dryRun":true`.

Text-only switches such as color, filename suppression, one-per-line, slash
decoration, and NUL termination do not change the JSONL schema. `--reverse` is
ignored during export so archives always contain natural tag order. Use
`--convert` to reverse tags for display.

For text output, bare `--color` and `--color=yes` mean automatic terminal
coloring. `--color=always` and `--color=force` force ANSI colors, while
`--color=no`, `--color=none`, and `--color=never` disable them. JSONL is never
colored.

## Reliability behavior

A successful Foundation read with no tag value means "no tags". A failed
resource-value read throws and is **never** interpreted as an empty tag list.

Every destructive operation reads target metadata before writing. `--copy`
completes both source and destination reads before any destination write. Every
actual write is then read back and compared, including array ordering. A
mismatch is reported as an error.

The macOS integration suite also checks that a tag write leaves the file's
content modification time unchanged. Creation time and attribute-change time
are not rewritten by this tool.

This is intentionally best-effort rather than transactional. A concurrent tag
change between read and write can still be lost, and a multi-file operation can
partially complete if a later file fails. See `REVIEW.md` for details.

## Option names and backward compatibility

Clearer long names are preferred while corresponding `jdberry/tag` names remain
aliases:

| Preferred | Compatible alias | Short |
|---|---|---|
| `--filename` | `--name` | `-n` |
| `--no-filename` | `--no-name` | `-N` |
| `--one-per-line` | `--garrulous` | `-g` |
| `--comma-separated` | `--no-garrulous` | `-G` |
| `--null` | `--nul` | `-0` |
| `--dry-run` | `--dryrun` | none |
| `--jsonl` | `--ndjson` | none |
| `--reverse` | none | `-V` |
| `--case-sensitive` | none | `-C` |
| `--sorted-tags` | `--sort-tags` | none |

The existing `-d` alias for `-R/--recursive` is also retained.

## Compatibility with jdberry/tag

Commands/options intentionally compatible where implemented:

* default list and `-l/--list`
* `-a/--add`, `-r/--remove`, `-s/--set`
* `-m/--match`, `-u/--usage`, `-f/--find`
* `-A`, `-e`, `-R`, `-d`
* `-n/-N`, `-t/-T`, `-g/-G`, `-c`, `-p`, `-0`
* ordinary comma-separated tag operands, default case-insensitive matching, and
  `'*'` wildcard behavior
* current-directory default for list/match/usage
* `-e/-R` relative descendant display

Important differences:

1. **Tag order is preserved by default.** `--sorted-tags` gives an explicit
   sorted mode.
2. **`--usage` uses direct traversal**, not Spotlight, and requires TAGS.
3. **`--find` uses Spotlight**, but `--home/--local/--network` are not yet
   implemented.
4. The tool adds ordered placement/movement, copying, case-sensitive matching,
   stdin path input, richer JSONL, dry-run, absolute paths, and symlink control.
5. Quoted TAGS can contain commas.

## License

MIT. See [`LICENSE.txt`](LICENSE.txt). The repository also includes
`jdberry-tag-LICENSE.txt` for attribution to the upstream project whose CLI and
implementation informed compatibility work.
