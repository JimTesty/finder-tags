# tag

A small Swift command-line tool for macOS Finder tags. Its main design goal is
**preserving Finder tag order** while remaining usage-compatible with the useful
non-Spotlight parts of [`jdberry/tag`](https://github.com/jdberry/tag).

This is currently named `tag` for command-line compatibility.

## Requirements and build

The build intentionally uses **plain `swiftc` only**. It does not require Swift
Package Manager, XCTest, Xcode, or a `Package.swift` file.

Tested for Swift 5 language compatibility; the intended minimum is Swift 5.5.

```sh
make                 # build/tag
make test            # shell/CLI smoke tests, no XCTest
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

The top-level `./tag` wrapper simply runs `make build` and then executes
`build/tag`; unchanged sources are not recompiled.

## Common examples

```sh
tag                                # list current directory
tag file1 file2                    # list explicit files and ordered tags
tag -c file                        # approximate Finder tag colors
tag -V file                        # display stored tags in reverse order

tag -a 'Work,Important' file      # append missing tags, in this order
tag -r 'Work,Old' file            # remove tags without reordering survivors
tag -r '*' file                   # remove all tags
tag -s 'First,Second' file        # replace tags in exactly this order
tag --copy src dst                 # destructively copy tag array/order
tag --copy src dst --dry-run       # show the intended copy, do not write

tag -m 'Work,Important' file1 file2
tag --match '*' -R directory       # files with any tag
tag --match '' .                   # explicit path with no tags

tag --usage                       # tag counts in current directory
tag --usage '*' -R directory       # counts recursively under directory
tag --usage Work -R directory      # files having Work; count all their tags

tag --json file1 file2            # structured, order-preserving output
tag -R directory                   # recursively process directory + contents
```

## Ordering guarantees

All tag reads/writes use Foundation's `URLResourceKey.tagNamesKey` abstraction.
No operation intentionally sorts the tag array.

* **list:** outputs the stored array in its returned order.
* **add:** preserves existing order, then appends missing requested tags in
  command-line order.
* **remove:** filters the existing array, preserving survivor order.
* **set:** writes tags in command-line order.
* **copy:** writes the source array to the destination unchanged.
* **match:** displays each matched file's stored order.
* **usage:** aggregate output is in first-seen tag order.
* **reverse:** reverses display only; it never rewrites metadata.

Requested duplicate tag names are deduplicated case-insensitively, with the
first spelling/order winning.

## Reliability behavior

A successful Foundation read with no tag value means "no tags". A failed
resource-value read throws and is **never** interpreted as an empty tag list.

Every destructive operation reads the target metadata before writing.
`--copy` completes both the source and destination reads before any destination
write. Every actual write is then read back and compared, including array
ordering. A mismatch is reported as an error.

This is intentionally best-effort rather than transactional. If another process
changes tags between our read and write, or a later file in a multi-file command
fails, earlier successful writes are not rolled back. Finder-tag metadata does
not justify a locking/transaction layer here.

## `--dry-run` / `--dryrun`

Valid with `--add`, `--remove`, `--set`, and `--copy`. It performs all normal
reachability and metadata reads and computes the exact before/after arrays, but
does not write.

Text output shows the before/after arrays. With `--json`, each record contains
`operation`, `path`, `before`, `after`, and `changed`; copy records also contain
`source`.

## JSON

`--json` emits one JSON array and preserves tag-array order:

```json
[
  {
    "path": "example.txt",
    "tags": ["First", "Second"]
  }
]
```

For `--usage`, records contain `tag` and `count`. For dry runs, records contain
before/after arrays. `--reverse` affects displayed list/match arrays and usage
record order.

JSON is structural output, so text-only presentation switches such as color,
filename suppression, one-per-line, slash decoration, and NUL termination do
not change its schema.

## Match semantics

`--match TAGS` / `-m TAGS` follows `jdberry/tag` semantics:

* `A,B` requires all specified tags, case-insensitively.
* `'*'` matches files having at least one tag.
* `''` matches files having no tags.
* With no paths, the current directory is enumerated.
* Explicit directories are treated as directory objects unless `-e` or `-R`
  asks to enumerate their contents.

Match output defaults to filenames only. Use `-t/--tags` to include tags.

## Usage semantics

`--usage [TAGS]` / `-u [TAGS]` counts **all tags on files matching TAGS**, like
`jdberry/tag`. The important difference is scope: this implementation does not
use Spotlight. It traverses the supplied paths directly and honors `-A`, `-e`,
and `-R`.

With no paths, it enumerates the current directory. With no TAGS, TAGS defaults
to `'*'`.

Because the tag expression is optional, an explicit path immediately after
`--usage` would be ambiguous. To count all tags under a path, write:

```sh
tag --usage '*' PATH
tag -u '*' PATH
```

## Option names and backward compatibility

The clearer long names are preferred, while the corresponding `jdberry/tag`
names remain aliases:

| Preferred | Compatible alias | Short |
|---|---|---|
| `--filename` | `--name` | `-n` |
| `--no-filename` | `--no-name` | `-N` |
| `--one-per-line` | `--garrulous` | `-g` |
| `--comma-separated` | `--no-garrulous` | `-G` |
| `--null` | `--nul` | `-0` |
| `--dry-run` | `--dryrun` | none |
| `--reverse` | none | `-V` |

The existing `-d` alias for `-R/--recursive` is also retained.

## Compatibility with jdberry/tag

Commands/options intentionally compatible where implemented:

* default list and `-l/--list`
* `-a/--add`, `-r/--remove`, `-s/--set`
* `-m/--match`, `-u/--usage`
* `-A`, `-e`, `-R`, `-d`
* `-n/-N`, `-t/-T`, `-g/-G`, `-c`, `-p`, `-0`
* comma-separated tag operands, case-insensitive matching, `'*'` wildcard
* current-directory default for list/match

Important differences:

1. **Tag order is preserved.** `jdberry/tag` sorts tags for display and uses
   unordered sets in add/remove paths; this tool deliberately does neither.
2. **No Spotlight search.** `--find`, `--home`, `--local`, and `--network` are
   not implemented.
3. **`--usage` is traversal-based**, not a filesystem-wide Spotlight query.
4. New features are `--copy`, `--reverse`, `--json`, and `--dry-run`.
5. Some long option names have clearer preferred spellings, but old spellings
   remain accepted.

## Colors

`-c/--color` uses the same general best-effort technique as `jdberry/tag`: it
reads Finder's private preference data to map tag names to Finder color codes,
then emits approximate ANSI backgrounds. Failure to read that private color map
only disables coloring; it never affects tag reads/writes.

## Attribution

The CLI shape and Finder-color approach are inspired by `jdberry/tag`, which is
MIT licensed. Its license is included as `jdberry-tag-LICENSE.txt`.
