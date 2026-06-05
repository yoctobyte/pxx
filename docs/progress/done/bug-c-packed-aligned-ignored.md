# C `__attribute__((packed))` / `aligned` ignored → field-offset drift

- **Type:** bug
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-06 (from c-skipped-features-audit.md, Class A/B)

## Symptom

The C importer discards `__attribute__((packed))` and `__attribute__((aligned(N)))`.
A packed or specially-aligned C struct is then laid out with standard C natural
alignment, producing **different field offsets** than the real C library. When
such a struct's fields are accessed directly across the boundary, reads/writes
hit the wrong offsets → silent memory corruption (not a crash, not a fallback).

## Why it matters

Unlike the bitfield/anonymous-union cases (which fall back to an opaque pointer,
never a silently-wrong layout), packed/aligned attrs currently produce a
plausible-but-wrong record. Flagged High risk in the audit.

## Scope

- Honor `packed` (1-byte alignment, no padding) and `aligned(N)` when laying out
  an imported C struct, **or** fall back to opaque for such structs (matching the
  bitfield policy) until layout is honored. Never emit a silently-wrong layout.

## Relation

Part of [`feature-c-header-import-complex`](feature-c-header-import-complex.md);
filed as a bug because the current behavior is silently incorrect, not merely
unimplemented.

## Acceptance

A packed C struct either lays out at correct offsets or falls back to opaque; a
test confirms no silent offset drift; POD structs in the same header unaffected.

## Log
- 2026-06-06 — ticket opened from c-skipped-features-audit.md.
