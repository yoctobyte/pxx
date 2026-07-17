---
summary: "SEGFAULT: assigning a WideChar VARIABLE to an AnsiString crashes (direct widechar(x) value works)"
type: bug
prio: 50
---

# `s := w` where `w: WideChar` segfaults (WideChar var → AnsiString)

- **Type:** bug (Track A/P — assign lowering / WideChar handling). Crash, not silent, but
  same shape-blind-spot family as the PChar-cast bugs.
- **Status:** backlog
- **Found:** 2026-07-17, conversion-context sweep.

## Repro

```pascal
var s: AnsiString; w: WideChar;
begin
  s := WideChar($41);   { direct value  -> "A"   OK }
  w := WideChar($41);
  s := w;               { via a variable -> SEGFAULT }
end.
```

`s := WideChar($41)` (direct) prints `A`. `w := WideChar($41); s := w` **segfaults**.
Char→string and string concat are fine — only WideChar **variable** → string crashes.

## Root

`NodeIsWideCharVal` (`parser.inc:6243`) matches **only** an `AN_PTR_CAST` node with the
`-3` widechar-cast sentinel — i.e. a literal `widechar(x)` expression. A WideChar
**variable read** is a plain `AN_IDENT`, so `NodeIsWideCharVal` returns False, the
assign path skips `WrapWideCharToUTF8`, and the 16-bit ordinal falls into the
managed-string assign path which treats it **as a pointer** → deref → crash. (This is
exactly the failure the code comment at the WideChar-assign site warns about, for the
sibling case it *does* handle.)

Same class as the PChar-cast bugs: a decision keyed on **node shape** (the `-3` cast
node), missing another shape (the variable read).

## Why there is no clean type-based fix

**WideChar is not a distinct type** — `parser.inc:6612` maps `widechar` to **`tyUInt16`**
(the RTL is byte/ASCII; the type exists only so FPC sources compile). No subtype marker is
recorded on the symbol, so after declaration a `WideChar` variable is **indistinguishable
from a `Word`**. Keying `NodeIsWideCharVal` on "type is tyUInt16" would also fire for
genuine `Word` values.

## Semantic fork (needs a call — flagging, not guessing)

`s := <tyUInt16 value>` cannot be both:

- **Convert as WideChar → UTF-8** (wrap in `WrapWideCharToUTF8`): fixes the common
  `s := widechar_var`, matches the direct-cast behavior, FPC-correct for WideChar. But a
  genuine `Word → string` (invalid in FPC) would silently convert instead of erroring.
- **Reject with "incompatible types; cast with widechar(...)":** never crashes, FPC-correct
  for `Word`, but rejects a valid `WideChar → string` that FPC accepts, and pxx cannot tell
  which it is.

**Recommendation:** *convert-as-widechar*. Rationale: pxx has deliberately collapsed
WideChar→tyUInt16, `Word → string` is invalid code nobody writes, and converting matches
the already-working `s := widechar(x)` path — least-surprise for the real use. Either way
the **crash must go** first; a `Word → string` that currently *segfaults* is strictly worse
than either resolution.

## Fix (once the fork is settled)

If convert: extend `NodeIsWideCharVal` (or the assign-path guard) to also treat a tyUInt16
RHS assigned to a string as a widechar source, wrapping it in `WrapWideCharToUTF8`.
Cover the cast, assign, arg, and return contexts (the shape/context matrix), per
[[refactor-centralize-managed-string-pchar-conversion]].

## Acceptance

- The repro prints `A` twice (or errors cleanly) — never segfaults.
- `test/test_*.pas` regression for WideChar var → string.
- Gate: `make test` + self-host byte-identical.
