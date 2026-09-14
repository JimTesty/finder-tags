# finder-tags

`finder-tags` is a small Swift command-line tool for macOS Finder tags. It
builds/installs an executable named **`tag`** and is deliberately
usage-compatible with the non-Spotlight parts of
[`jdberry/tag`](https://github.com/jdberry/tag) where practical.

Its main difference is intentional: **Finder tag order is preserved** on reads
and writes instead of sorting tags or passing them through unordered sets.

## Development status

This project is new and **not thoroughly tested yet**. It has a fairly broad
shell test suite, macOS-only integration tests for real Finder-tag operations,
and an optional differential test suite against `jdberry/tag`, but it has not
been exercised broadly across macOS releases, filesystems, network volumes, or
large data sets.

Most of the source code was written by **OpenAI GPT-5.6 Sol**, under the
maintainer's direction and with iterative human testing/review.

See [`REVIEW.md`](REVIEW.md) for the current source review, known limitations,
and possible improvements.

## Requirements and build

The build uses **plain `swiftc` only**. It does not require Swift Package
Manager, XCTest, Xcode, or a `Package.swift` file.

The intended minimum compiler is Swift 5.5. The Makefile explicitly selects
Swift 5 language mode.

```sh
make                  # build/tag
make test             # self-tests; macOS also exercises real Finder tags
make install          # installs to ~/.local/bin/tag by default
```

To choose another install prefix:

```sh
make install PREFIX=/usr/local
```

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
`Tests/` directory**, compares the common behavior of both programs, and cleans
up afterward. It does not intentionally modify files elsewhere.

The compatibility suite does not strictly compare `--usage`, because
`jdberry/tag` uses Spotlight while `finder-tags` directly traverses the supplied
paths, and freshly created test files may not yet be indexed by Spotlight.

## Common examples

```sh
tag                                  # list current directory
tag file1 file2                      # list explicit files and ordered tags
tag -c file                          # approximate Finder tag colors
tag -V file                          # display tags in reverse order

tag -a 'Work,Important' file         # append new tags
tag --prepend Urgent file            # insert new tag at first/left/bottom
tag -a Urgent --at 1 file            # zero-based insertion position
tag --move Urgent top file            # move it to last/right/top
tag -r 'Work,Old' file               # remove matching tags
tag -r '*' file                      # remove all tags
tag -s 'First,Second' file           # replace tags in exactly this order
tag --copy src dst                   # destructively copy tag array/order
tag --copy src dst --dry-run         # preview copy, do not write

tag -m 'Work,Important' file1 file2
tag --match '*' -R directory         # files with any tag
tag --match '' .                     # explicit path with no tags
tag --usage '*' -R directory         # counts all tags on tagged files
tag --usage Work -R directory        # matching files; count all their tags

tag --jsonl file1 file2              # streaming structured output
tag -R directory                     # directory, then descendants
```

## Ordering guarantees

All tag reads/writes use Foundation's `URLResourceKey.tagNamesKey` abstraction.
No operation intentionally sorts the stored tag array.

* **list:** outputs the stored array in its returned order.
* **add/append:** preserves existing order; new tags are inserted at the chosen
  position, last by default.
* **prepend:** `--add ... --at first` convenience form.
* **remove:** filters the existing array, preserving survivor order.
* **set:** writes tags in command-line order.
* **move:** removes one matched tag and inserts it at the requested position.
* **copy:** writes the source array to the destination unchanged.
* **match:** displays each matched file's stored order.
* **usage:** aggregate output is in first-seen exact-tag order.
* **reverse:** reverses display only; it never rewrites metadata.

`--at` and `--move` accept a zero-based numeric insertion index or these names:

* `first`, `left`, `bottom` = index 0
* `last`, `right`, `top` = the end

The Finder wording can feel backwards vertically: the **last/rightmost** tag's
color is drawn **on top**, hence `top = last` and `bottom = first`.

`--at` only affects newly inserted tags. If `--add` merely re-cases an existing
unique case-insensitive match, that tag stays in its current position; use
`--move` when you also want to reposition it.

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

If case-insensitive `--add` finds multiple stored variants and no exact match,
it reports the match as ambiguous instead of arbitrarily merging or changing
one. If a single add expression explicitly requests case-distinct variants,
for example `orange,Orange`, both are preserved.

`--case-sensitive` affects add/remove/move/match/usage matching. `--set` always
stores the exact spellings supplied. Usage counts also keep `orange` and
`Orange` as separate entries even in the default matching mode.

## Tags containing spaces, commas, and quotes

Normal shell quoting already handles spaces:

```sh
tag --add "Needs review" file
```

The TAGS parser also understands single- or double-quoted CSV-style components,
which allows literal commas inside a tag:

```sh
tag --set 'Red,"Project, Alpha","Needs review"' file
```

That represents exactly three tags:

```text
Red
Project, Alpha
Needs review
```

A doubled quote inside a quoted component represents one literal quote, in the
usual CSV style. Unquoted components have surrounding whitespace trimmed;
whitespace inside quoted components is preserved.

The plain comma-separated **output** format is inherently ambiguous when tag
names themselves contain commas. Use `--jsonl` for machine consumption, or
`--one-per-line` when tag names do not contain newlines.

`*` remains reserved for wildcard behavior in `--match`, `--usage`, and
`--remove`.

## Match semantics

`--match TAGS` / `-m TAGS` follows `jdberry/tag` semantics where applicable:

* `A,B` requires all specified tags.
* Matching is case-insensitive unless `--case-sensitive` is supplied.
* `'*'` matches files having at least one tag.
* `''` matches files having no tags.
* With no paths, the current directory is enumerated.
* Explicit directories are treated as directory objects unless `-e` or `-R`
  asks to enumerate their contents.

Match output defaults to filenames only. Use `-t/--tags` to include tags.

## Usage semantics

`--usage TAGS` / `-u TAGS` counts **all tags on files matching TAGS**. Unlike
`jdberry/tag`, it does not use Spotlight; it directly traverses the supplied
paths and honors `-A`, `-e`, and `-R`.

`TAGS` is intentionally **required** in `finder-tags`. Although current
`jdberry/tag` accepts an omitted usage operand and defaults it to `*`, requiring
it here avoids the path-vs-tag parsing ambiguity. Use:

```sh
tag --usage '*' PATH
tag --usage Work PATH
tag -u '*' PATH
```

With no paths, the current directory is enumerated.

## Symbolic links

Symbolic links are intentionally **followed**. Finder does not meaningfully set
independent Finder tags on a symlink; its visible tag state follows the target.
Accordingly, listing or mutating a symlink operates on the resolved target.

`-R/--recursive` also follows symlinked directories. Directory cycles are
suppressed using the currently active resolved-directory path, while the same
target may still be reached through a different non-cyclic alias and shown
under that alias.

This also means a recursive operation can follow a symlink **outside the
original directory tree**. Use recursive mutations accordingly.

## `--dry-run` / `--dryrun`

Valid with `--add`, `--remove`, `--set`, `--move`, and `--copy`. It performs the
normal metadata reads and computes the exact before/after arrays, but does not
write.

Text output shows the before/after arrays. With `--jsonl`, each record contains
`operation`, `path`, `before`, `after`, `changed`, and `dryRun`; copy records
also contain `source`.

## JSON Lines / NDJSON

`--jsonl` (alias `--ndjson`) emits one JSON object per line and streams results
without buffering an entire recursive traversal.

Example:

```json
{"path":"example.txt","tags":["First","Second"]}
```

For `--usage`, records contain `tag` and `count`. Mutations emit before/after
records after a successful write; dry runs emit the same shape with
`"dryRun":true`.

Text-only switches such as color, filename suppression, one-per-line, slash
decoration, and NUL termination do not change the JSONL schema.

## Reliability behavior

A successful Foundation read with no tag value means "no tags". A failed
resource-value read throws and is **never** interpreted as an empty tag list.

Every destructive operation reads the target metadata before writing.
`--copy` completes both source and destination reads before any destination
write. Every actual write is then read back and compared, including array
ordering. A mismatch is reported as an error.

This is intentionally best-effort rather than transactional. A concurrent tag
change between read and write can still be lost, and a multi-file operation can
partially complete if a later file fails. See `REVIEW.md` for details.

## Option names and backward compatibility

The clearer long names are preferred, while corresponding `jdberry/tag` names
remain aliases:

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

The existing `-d` alias for `-R/--recursive` is also retained.

## Compatibility with jdberry/tag

Commands/options intentionally compatible where implemented:

* default list and `-l/--list`
* `-a/--add`, `-r/--remove`, `-s/--set`
* `-m/--match`, `-u/--usage` (with the operand difference below)
* `-A`, `-e`, `-R`, `-d`
* `-n/-N`, `-t/-T`, `-g/-G`, `-c`, `-p`, `-0`
* ordinary comma-separated tag operands, default case-insensitive matching, and
  `'*'` wildcard behavior
* current-directory default for list/match/usage
* `-e/-R` display paths relative to each explicit directory argument

Important differences:

1. **Tag order is preserved.** `jdberry/tag` sorts tags for display and uses
   unordered sets in add/remove paths; this tool deliberately does neither.
2. **No Spotlight search.** `--find`, `--home`, `--local`, and `--network` are
   not implemented.
3. **`--usage` is traversal-based**, not a filesystem-wide Spotlight query,
   and its TAGS operand is required here.
4. **Quoted TAGS can contain commas.** This extends the upstream grammar.
5. **Symlinks are followed deliberately**, including recursive symlinked
   directories with cycle suppression.
6. New ordered-tag features include `--copy`, `--move`, `--at`,
   `--prepend/--append`, `--reverse`, `--case-sensitive`, `--jsonl`, and
   `--dry-run`.

## Colors

`-c/--color` uses the same general best-effort technique as `jdberry/tag`: it
reads Finder's private preference data to map tag names to Finder color codes,
then emits approximate ANSI backgrounds. Like `jdberry/tag`, color is emitted
only when stdout is a terminal.

Failure to read the private color map only disables coloring; it never affects
tag reads/writes.

## License and attribution

`finder-tags` is MIT licensed. See [`LICENSE.txt`](LICENSE.txt).

The CLI shape and Finder-color approach are inspired by `jdberry/tag`, which is
also MIT licensed. Its license is retained separately as
[`jdberry-tag-LICENSE.txt`](jdberry-tag-LICENSE.txt).
