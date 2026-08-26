---
track: U
prio: 20
type: decide
blocked-by: []
summary: "`{$WRITEABLECONST}` is not implemented at all — the compiler contains no reference to it. Typed constants are now unconditionally writable, which is FPC's DEFAULT; the question is whether pxx should honour the OFF form and refuse the store, or document typed consts as always writable. A dialect call, not a bug fix."
---

# Should `{$WRITEABLECONST OFF}` be honoured?

- **Track U** (decision) — raised 2026-08-26 while resolving
  [[bug-p-typed-constants-cannot-hold-a-pointer-a-nested-aggregate-or-storage]].
  The folded ticket `bug-p-a-typed-string-constant-cannot-be-assigned` named
  this as "a related, separate question for Track U" and asked for exactly this
  ticket if the taker wanted it settled first. It did not need settling to fix
  the bug, which is why the fix landed without it.

## The measurement

Grepping the compiler for `WRITEABLECONST` finds nothing. The directive is
parsed as an unknown one and ignored, in both spellings.

Before 2026-08-26 the *consequence* was an accident rather than a policy: typed
constants of Integer, Char and array type had real storage and were writable;
a typed STRING constant had no storage at all and was therefore unwritable, and
said so as `undefined variable`. Every typed constant now has storage and every
one is writable.

## Why that is already the right default

`{$WRITEABLECONST ON}` is FPC's default outside `{$MODE DELPHI}`, so pxx's
present behaviour matches an unannotated FPC source. Nothing compiles wrong
today; the gap is only that a source which explicitly asks for `OFF` does not
get it.

## The two answers

1. **Honour it.** A per-unit flag set by the directive, checked at the
   assignment site, with a real diagnostic ("cannot assign to a constant" —
   which is the message the old string behaviour was mistaken for). Costs a flag
   and one check; buys a source that says `OFF` behaving as it says. Also the
   only way `{$MODE DELPHI}` can ever mean what it means in FPC, where OFF is
   the default.
2. **Document it as unsupported.** Note in the divergences doc that pxx's typed
   constants are always writable, and reject this ticket. Per CLAUDE.md's
   FPC-parity ceiling this is defensible: no *correct* Pascal program is
   miscompiled by a compiler that is more permissive here — a program that
   assigns to a constant under `OFF` was already wrong.

The honest tie-breaker is whether any real corpus source sets `OFF` (or uses
`{$MODE DELPHI}` and relies on it). Nobody has looked; that measurement should
come before the decision.

## Not blocking anything

Filed so the question is parked rather than carried. No ticket is waiting on it.
