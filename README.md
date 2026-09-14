# tag

A small Swift command-line tool for macOS Finder tags. Its main design goal is
**preserving tag order** while providing the useful non-Spotlight parts of
[`jdberry/tag`](https://github.com/jdberry/tag).

## Run / build

For immediate use from the extracted source tree:

```sh
./tag --help
```

The top-level `tag` is only a tiny launcher around Swift Package Manager. For a
regular command-line installation, compile once:

```sh
swift build -c release
```

The executable is at the path printed by:

```sh
swift build -c release --show-bin-path
```

For example, install it somewhere on your `PATH`:

```sh
install -m 755 "$(swift build -c release --show-bin-path)/tag" ~/bin/tag
```

## Examples

```sh
tag                         # list current directory
tag file1 file2             # list explicit files
tag -c file                 # show Finder tag colors
tag -V file                 # display tags in reverse order
tag -a 'Work,Important' f   # append missing tags
tag -r 'Work,Old' f         # remove tags
tag -r '*' f                # remove all tags
tag -s 'First,Second' f     # replace tags in this exact order
tag --copy src dst          # destructively copy tag array/order
tag -R directory            # process recursively
```

Use `tag --help` for the complete CLI.

## Ordering behavior

* **list:** displays Foundation's `tagNames` array without sorting. `--reverse`
  reverses display only.
* **add:** preserves existing order and appends new tags in command-line order.
* **remove:** filters the existing array, preserving survivor order.
* **set:** stores tags in command-line order.
* **copy:** stores the source array on the destination unchanged.

Duplicate requested tags are deduplicated case-insensitively, with the first
spelling/order winning.

## Reliability behavior

Tag reads use `URLResourceKey.tagNamesKey`. A successful read with no value is
"no tags"; a failed resource-value read throws and is never treated as an empty
list.

Every destructive operation reads the target metadata before writing. `--copy`
fully reads the source before touching the destination. Writes are read back and
compared with the requested ordered array; mismatch is reported as an error.

Operations over multiple paths are not transactional: an error on a later path
does not roll back earlier successful paths. This intentionally avoids complex
transaction/locking machinery for Finder metadata.

## Colors

`-c/--color` uses the same general best-effort technique as `jdberry/tag`: it
reads Finder's private preference data to map tag names to Finder color codes,
then emits approximate ANSI backgrounds. Failure to read the private color map
only disables coloring; it never affects tag reads/writes.

## Attribution

The CLI shape and Finder-color approach are inspired by `jdberry/tag`, which is
MIT licensed. Its license is included as `jdberry-tag-LICENSE.txt`.
