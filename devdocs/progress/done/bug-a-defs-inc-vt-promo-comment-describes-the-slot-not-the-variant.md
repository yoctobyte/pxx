---
prio: 20
track: A
type: bug
blocked-by: []
summary: "compiler/defs.inc:1150-1151 annotates the VT_PROMO_INT32/INT64 VARIANT tags with `payload = inline Int64, or a bignum ref` — which is the SLOT storage discriminator's semantics, the very thing the paragraph four lines above says the variant tags are distinct from. In a variant the payload is a managed STRING holding the exact decimal, per pylib.pas, which defs.inc itself names as the authority. No compiled behaviour is wrong; the cost is that a reader trusting the comment concludes a correct tool is broken. Measured: it sent the Track T agent to suspect pxx-gdb.py:109 of silently decoding a number as an address. tools/pxx-gdb.py is CORRECT and must not be 'fixed'."
status: done
owner: ""
---

# `defs.inc`'s VT_PROMO comment describes the SLOT, not the VARIANT

- **Type:** bug (wrong comment in a shared core file) — **Track A**. Filed
  2026-08-30 by the Track T agent, from a stale-constant sweep. Comment-only:
  no compiled behaviour is affected.

## The contradiction, within fifteen lines of one file

`compiler/defs.inc` defines the slot discriminator and says plainly what it is
not:

```pascal
{ The in-memory storage discriminator of a promotable-int SLOT — distinct from
  the VT_PROMO_* variant tags above, which only apply when a promotable int is
  boxed inside a variant. ... }
PROMO_TAG_INLINE = 0;   { payload = the machine integer itself }
PROMO_TAG_HEAP   = 1;   { payload = pointer to the heap bignum (stage 2b) }
```

Four lines later it annotates the variant tags with **exactly those slot
semantics**:

```pascal
VT_PROMO_INT32    = 8192;  { payload = inline Int32, or a bignum ref when the spill bit is set }
VT_PROMO_INT64    = 8193;  { payload = inline Int64, or a bignum ref }
```

## What the payload actually is

`defs.inc` names `pylib.pas` as the authority for this block ("MUST match
pylib.pas"). Three independent sites there agree, and the code matches the prose:

| site | says |
| --- | --- |
| `pylib.pas:6069` | "VT_PROMO_INT64: payload is the exact decimal in a managed string — compare CONTENT, not the two string refs", then `PPyAnsiString(@p^.Payload)^` |
| `pylib.pas:8522` | "a heap-tier promotable int (payload = exact decimal in a managed string)", then `ds := PPyAnsiString(@p^.Payload)^` |
| `pylib.pas:6497` | "VT_PROMO_INT64 (8193) and VT_STRING (6): by string CONTENT" |

So **inside a variant the payload is a managed string pointer**, grouped with
`VT_STRING` — not an inline machine integer. The comment describes the slot
representation, which is a different thing the same file already separated out.

## Why it is worth a ticket at all

Nothing miscompiles. The cost is that the comment is load-bearing for anyone
reading tag semantics without reading `pylib.pas`, and it points them at a wrong
conclusion about working code.

Measured, on the ticket's author: the sweep flagged
`VT_PROMO_INT64 = 8193` in `tools/pxx-gdb.py` as a stale mirrored constant. The
value matches. But `pxx-gdb.py:109` decodes that tag with
`_read_cstring(payload)` — treating the payload as a pointer — and `defs.inc`
says the payload is an inline `Int64`. Read together, that is a debugger
silently rendering a number as an address, which is the
`debugging-playbook.md` failure mode aimed at the instrument the playbook tells
every lane to reach for. Twenty minutes went into establishing that the
**comment** was wrong and the tool was right.

**`tools/pxx-gdb.py:109` is CORRECT.** Grouping `VT_PROMO_INT64` with
`VT_STRING` and reading the payload as a string is what the implementation does.
Recorded here explicitly so this ticket cannot be read as licence to "fix" it.

## Fix

Annotate the two variant tags with the variant payload (a managed string holding
the exact decimal, as `VT_STRING`), and leave the inline/bignum wording on
`PROMO_TAG_INLINE`/`PROMO_TAG_HEAP` where it is correct. Check `VT_PROMO_INT32`
(8192) at the same time: `symtab.inc:2951` assigns it, and `pylib.pas` handles
only 8193 explicitly plus a `t >= 8192` catch-all, so whether 8192 ever reaches
a variant payload is worth stating rather than leaving implied.

## Acceptance

The comment on each `VT_PROMO_*` line describes what a *variant* payload holds,
and disagrees with no site in `pylib.pas`.

## Log
- 2026-08-31 — resolved, commit 4eb58366c.
