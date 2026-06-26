# Design question: overloadable compiler intrinsics (the `Copy` precedent)

- **Type:** design / decision record (no action required yet)
- **Status:** rainy-day **deliberately undecided**
- **Owner:** Track A (language semantics)
- **Opened:** 2026-06-20
- **Relates:** [[bug-str-float-broken-by-copy-shadow]],
  [[feature-copy-intrinsic]], [[feature-rtl-conversion-and-bitset-library]]

## What this is

A standing question, not a task. `Copy` is currently **both** a compiler
intrinsic **and** a library-overloadable name. That mixed state is either a nice
feature ("you can override a builtin") or a latent footgun ("a library silently
shadows compiler magic"). We do not know which yet, and we are choosing to keep
both the behaviour and the question open. Develop organic; revisit when it bites
or when a clear policy emerges. This file exists so the decision is *recorded as
undecided*, not rediscovered cold later.

## How it works today (the mechanism — this part is settled fact)

`Copy` resolves with a deliberate precedence, gated on `procIdx` in
`compiler/parser.inc` at two sites (~3106 and ~3485):

- If a user-declared `Copy` routine matches the call (`procIdx >= 0`), the
  **user's overload wins** — the compiler steps aside and emits a normal call.
- Only when **no** user `Copy` is in scope (`procIdx < 0`) does the built-in
  dynamic-array `Copy(arr, idx [, count])` intrinsic fire (lowered to
  `AN_DYN_COPY`).

The in-source comments state the intent explicitly: *"Only when no Copy function
matches (so a string `sysutils.Copy` is never shadowed)... String Copy keeps the
RTL path."* So the precedence is **user routine > intrinsic fallback**, by
design, for this one name.

This is why `lib/rtl/sysutils.pas` can declare `function Copy(const s:
AnsiString; index, count: Integer): AnsiString` and have it coexist with the
dynarray intrinsic: the string form is the user routine (wins when it matches),
the dynarray form is the intrinsic fallback (fires when no user routine matches
the argument shape).

## The split that makes this a *question*

The "intrinsic-as-fallback, user-can-override" pattern is **not general** — it is
hand-wired into `Copy` alone:

- **Overloadable (function-call syntax, name-resolved):** `Copy` today. Candidates
  if generalised: `Pos`, `Concat`, `Length`, etc. — anything called like a normal
  function, where `procIdx` lookup already happens.
- **Not overloadable (keyword / special syntax, parsed before name resolution):**
  `Write` / `WriteLn` / `Read` / `ReadLn`, and `Str(x:width:dec, s)` — the `:w:d`
  form is *syntax*, not a call, so there is no `procIdx` lookup to defer to. These
  cannot be shadowed even in principle without a parser change.

So we have exactly one builtin that is overloadable and the rest that are not.
That inconsistency is the crux.

## Two honest readings (heaven vs hell — kept open on purpose)

**Feature:** "User declarations override intrinsics" is a clean, principled rule.
It lets the RTL grow real, debuggable Pascal implementations of names the
compiler bootstraps with, and lets a user patch around a miscompiling intrinsic
locally. The precedence (user > intrinsic) is the same direction FPC-ish dialects
take for some magic names.

**Hazard:** A library can silently change what a builtin name means, with no
diagnostic. The float-`Str` collision (see the related bug) was exactly this
seam — `Str`'s lowering once tangled with a user `Copy` in scope. Silent
shadowing of compiler magic is the kind of thing that produces a baffling bug
report months later.

## Current decision

**Let it stand.** The behaviour is acceptable and, in practice, useful right now
(the sysutils string `Copy` rides on it). We are **not** generalising it to other
builtins yet, and **not** locking it down either. If a generalisation turns out
to be the practical fix for a concrete case, that is fine to take — organically,
per name, using the same `procIdx < 0` guard pattern.

## When to revisit (triggers, not a schedule)

- A *second* builtin needs the same treatment → at that point decide whether to
  generalise the pattern or keep wiring it per-name.
- A real silent-shadow bug lands (not the stale Str one — a fresh repro) → that is
  the "hell" outcome materialising; consider a diagnostic ("user routine shadows
  builtin `X`") rather than removing the feature.
- The string-model / managed-default flip settles → revisit whether `Copy`/`Str`
  intrinsic entanglement still needs the special casing at all.

## Log
- 2026-06-20 — Opened as a decision-record. Behaviour confirmed in parser.inc
  (`procIdx`-gated `Copy`, user-overload-wins). Question kept deliberately open;
  current call is "let it stand, grow organic." Paired with the non-repro finding
  on [[bug-str-float-broken-by-copy-shadow]].
