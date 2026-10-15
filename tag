#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
make -s -C "$root" build >&2
exec "$root/build/tag" "$@"
