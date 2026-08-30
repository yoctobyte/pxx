---
slug: grant-pasparser-lval-and-rtti-emit-to-frankwasm-for-the-alias-break
title: "GRANT: pasparser_lval.inc + rtti_emit.inc to frankwasm (A+P), for the WideString alias break"
track: A+P
prio: 50
type: grant
status: backlog
owner: "frankwasm"
created: 2026-08-30
found-by: frank-coordinator
summary: "frankwasm holds compiler/defs.inc, compiler/pasparser_lval.inc and compiler/rtti_emit.inc for feature-unicodestring-model. symtab.inc is QUEUED behind frank-optimize. DO NOT CLAIM these files — this ticket is a lock record, not work."
---

# The grant

**DO NOT CLAIM.** This is a lock record. It exists because a grant is a lock the ranker
cannot see (`bug-t-a-grant-is-a-lock-the-ranker-cannot-see`), and an unfiled grant is one
that only lives in a message nobody else can read.

Given 2026-08-30 by the coordinator to **frankwasm**, for `feature-unicodestring-model`:

| file | lane | status |
| --- | --- | --- |
| `compiler/defs.inc` | A | **held** — `tyWideString` landed at ordinal 32, `d61f404f3` |
| `compiler/pasparser_lval.inc` | P | **held** — the alias break, two resolvers at ~:6322 and ~:6424 |
| `compiler/rtti_emit.inc` | A | **held** — the RTTI kind list, ~:942 |
| `compiler/symtab.inc` | A | **QUEUED** behind frank-optimize — TypeSize ~2922, ordinal-ness ~3120, name table ~8949 |
| `compiler/ir.inc` | A | free as of the cdecl handback; take on request |

## Why A+P is safe here, checked rather than assumed

`working/` holds only frankwasm's own ticket. `pasparser_lval.inc` was last touched
2026-08-29 by `121aecee2`, landed and unrelated. frankA is the only other agent in the
P carve-out and is in `pasparser_proc.inc`, disjoint from `_lval`.

**Neither holds `lexer.inc`** — that is the file whose sharing makes "P + anything" the
hazard CLAUDE.md warns about, and the combination is only safe while that stays true.
If either agent finds it needs `lexer.inc`, it stops and asks; it does not take it.

## The correction that produced this grant

The coordinator's original file list was `defs.inc` + `symtab.inc` and **could not have
worked**. frankwasm caught it before editing:

> `symtab.inc` makes a `tyWideString` **well-formed**; `pasparser_lval` is what makes one
> **exist**.

The alias lives in two name->kind resolvers that map `widestring` and `unicodestring` to
`tyAnsiString`. Without that file nothing ever constructs the kind and every symtab case
is unreachable — the type would have been landed, well-formed, and unnameable by any
program.

## The gate the holder must answer for

Both resolver sites are guarded by `PasDefineExists('PXX_MANAGED_STRING')`, so `widestring`
resolves to `tyAnsiString` **or** `tyString` depending on the build. **The acceptance test
must name which arm it ran under, and run both** — otherwise the alias breaks in one
configuration and silently persists in the other, and the tested arm's verdict is
inherited by an arm nobody measured. Same class as the native-green repro that closed a
bug live on four other targets (`bug-a-the-cdecl-soundness-reject-still-has-its-argument-shaped-door-on-four-targets`).

sysutils' `WideString`/`UnicodeString` identity functions are *documented* as the identity;
at the moment the alias breaks that documentation becomes wrong rather than stale. Change
them in the same commit.

## Release

Coordinator releases on frankwasm's word, or when `feature-unicodestring-model` resolves.
