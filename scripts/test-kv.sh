#!/bin/sh
set -eu
DB="$(mktemp -u /tmp/deno-pg4e-kv-XXXXXX)"
trap 'rm -f "$DB" "$DB-shm" "$DB-wal"' EXIT
deno eval --unstable-kv "const kv = await Deno.openKv('$DB'); await kv.set(['hello'], 'world'); console.log((await kv.get(['hello'])).value); kv.close();"
