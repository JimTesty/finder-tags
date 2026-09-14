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
```

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
* **reverse:** reverses display only; it never rewrites metadata.

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

The plain comma-separated **output** format is inherently ambiguous when tag
names contain commas. Use `--jsonl` for machine consumption or
`--one-per-line` when a simple text format is sufficient.

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

Symbolic links are **followed by default**. Finder generally presents the target
file's tags, and recursive traversal follows symlinked directories while
suppressing directory cycles.

`--no-follow-symlinks` is the defensive alternative for recursive work: it does
not descend into symlinked directories and does not explicitly resolve symlink
paths before Foundation tag I/O. This is particularly useful to prevent a
recursive mutation from escaping its starting tree through a directory symlink.

## `--dry-run`

Valid with `--add`, `--remove`, `--set`, `--move`, and `--copy`. It performs the
normal metadata reads and computes the exact before/after arrays, but does not
write.

Text output shows the before/after arrays. With `--jsonl`, each record contains
`operation`, `path`, `before`, `after`, `changed`, and `dryRun`; copy records
also contain source path information.

## JSON Lines / NDJSON

`--jsonl` (alias `--ndjson`) emits one JSON object per line and streams results
without buffering an entire recursive traversal.

File records contain:

* `path`: the normal displayed path
* `absolutePath`: the absolute logical path, preserving symlink spelling
* `resolvedPath`: the symlink-resolved absolute path
* `root`: the traversal root when applicable
* `tags`: the displayed tag array

Example:

```json
{"absolutePath":"/tmp/tree/file","path":"file","resolvedPath":"/tmp/tree/file","root":"/tmp/tree","tags":["First","Second"]}
```

For `--usage`, records contain `tag` and `count`. Mutations emit before/after
records after a successful write; dry runs emit the same shape with
`"dryRun":true`.

Text-only switches such as color, filename suppression, one-per-line, slash
decoration, and NUL termination do not change the JSONL schema.

## Reliability behavior

A successful Foundation read with no tag value means "no tags". A failed
resource-value read throws and is **never** interpreted as an empty tag list.

Every destructive operation reads target metadata before writing. `--copy`
completes both source and destination reads before any destination write. Every
actual write is then read back and compared, including array ordering. A
mismatch is reported as an error.

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
