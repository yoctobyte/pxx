---
prio: 45  # auto
---

# Dynamic soname discovery (no execve)

- **Type:** feature
- **Status:** done
- **Owner:** agent-A
- **Opened:** 2026-06-06 (from todo.md §2c Pillar 1 remainder)

## Motivation

Library names currently map to versioned sonames via a hardcoded table
(libc/libm/libpthread/libdl/librt/libz/GTK/sqlite3); unmapped names fall back to
`lib<name>.so`. The self-hosted compiler has **no execve**, so pkg-config /
ldconfig shelling is impossible.

## Scope

Probe the soname by reading the host directly via file I/O:

- Parse `/etc/ld.so.cache`, or
- Read `DT_SONAME` from candidate `.so` ELF files.

Resolve an unmapped `external 'name'` / header library to its real versioned
soname without a hardcoded entry.

## Acceptance

A library not in the static table links against its correct versioned soname,
verified on a normal Linux host. Hardcoded table remains the fallback.

## Log
- 2026-06-06 — ticket opened from todo.md §2c.


## Done 2026-08-21 — /etc/ld.so.cache, read directly

`ldconfig -p`'s answer lives in a plain file the loader itself indexes, so no
execve is needed: parse glibc's `cache_file_new` (magic `glibc-ld.so.cache`,
version `1.1`, 48-byte header, 24-byte entries whose `key` is the soname) and
look up the versioned name for `lib<stem>.so`. Every read is bounds-checked
against the real file length rather than the header's claims — this parses a
file written by something else, and a compiler that segfaults on a truncated
`/etc/ld.so.cache` would be worse than the bug being fixed.

**Order is host FIRST, table second** — the reverse of "table, with the cache as
a fallback for unknowns". That is deliberate: it makes "known library" and
"unknown library" stop being different code paths, so a future soname bump
(`libz.so.1` -> `.2`) needs no edit at all. The table stays as the answer when
the cache is missing, unreadable, foreign, or when cross-compiling.

**Cross targets never read it.** What this box has installed says nothing about
the machine an aarch64 binary will run on, and a soname invented from the wrong
host fails at load time, far away, with nothing pointing back here. Native
x86-64 only, same rule the C include-path defaults follow.

**The sibling arm, fixed with it.** `CSystemLibSelectedForSoname` was a second
hardcoded table facing the other way (nine `CaseEqual(soname, 'libz.so.1')`
lines) used to decide whether `--system-libs=<x>` selected a library. Any soname
outside those nine — which is every one the cache can now supply, and every
future version bump — would have answered "not selected" and silently ignored
the flag. It now DERIVES the stem from the soname (`libgtk-x11-2.0.so.0` ->
`gtk-x11-2.0`), so the two directions cannot drift.

### Measured

| | before (pinned) | after |
| --- | --- | --- |
| `external 'libsqlite3.so'` | `libsqlite3.so` | `libsqlite3.so.0` |
| `external 'libcurl.so'` (not in the table) | `libcurl.so` | `libcurl.so.4` |
| `--target=aarch64`, same source | `libgcc_s.so` | `libgcc_s.so` (unchanged — correct) |

Both versioned answers match `ldconfig -p` on this host exactly, and the linked
binary runs. `--system-libs=m` / `=c` still emit exactly one of libm/libc and
not the other, which is what would catch a bad stem derivation.

Locked by rows in `test-quick` (`test/soname_host_discovery.pas`), including the
cross-target row and a loud SKIP — never a silent one — on a host with no
`/etc/ld.so.cache` entry for libgcc_s.

### Note for whoever reads this next
The emitted binary now depends on the HOST's installed libraries, which is the
point of the ticket but is worth saying out loud: two machines with different
library versions will produce different DT_NEEDED strings for the same source.
That is not the invocation-dependence of
`bug-a-the-compilers-output-depends-on-argv0` — it is the same source asking a
different machine a question about itself — but anyone chasing a byte-difference
between two boxes should know this exists.

### One gate finding worth keeping

The first `gate.sh quick` came back RED on the **FPC seed canary** only — pxx
compiled itself fine, and `--tier quick` was green. `ResolveHostSoname` sits at
the bottom of `pasparser_proc.inc` next to the table it replaces, and the
`external 'lib.so'` parser near the TOP of the same file calls it: pxx resolves
that itself, FPC does not. A `forward` declaration fixes it, and the incident is
the same shape as `bug-a-fpc-seed-drift-emitasmx64-forward`.

Worth noting because the canary is the only layer that catches it: the
bootstrap seed is the one consumer that cannot be tested by running pxx.
- 2026-08-21 — resolved, commit PENDING-COMMIT.
