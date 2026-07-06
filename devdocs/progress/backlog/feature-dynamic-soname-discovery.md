---
prio: 45  # auto
---

# Dynamic soname discovery (no execve)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
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
