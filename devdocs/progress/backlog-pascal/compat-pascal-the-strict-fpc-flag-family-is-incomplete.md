---
summary: "--strict-fpc reproduces some FPC behaviours and silently not others (Abs/Sqr widths, pointer difference, TypeInfo name), and most flags ignore DialectIsPxx -- the gaps left after the umbrella landed"
type: bug
track: P
prio: 15
---

# The `--strict-fpc` family is incomplete, and the gaps are silent

**Umbrella, opened 2026-08-26.** [[feature-strict-fpc-umbrella]] landed the flag
infrastructure on 2026-07-15 and is `done`. These four tickets are what the
family still does not cover. They are grouped because they share one failure
mode and one gate, and because at prios 8-15 they will never be picked
individually — which is the actual argument for the umbrella: four items nobody
will take is worse than one item somebody might.

## Why the gaps matter more than their prios suggest

A strict flag is a **promise**. Someone porting FPC bit-twiddling turns it on
and gets FPC's shift widths — that works today — and assumes the rest of their
arithmetic is pinned too. It is not: `Abs` and `Sqr` still evaluate at native
width under the flag, and a pointer difference still counts elements. The flag
does not warn that it is only partly implemented. **A partial promise is worse
than an absent one**, because the absent one gets checked.

That is the whole reason these stay open rather than being closed under the
"we do not chase 100% FPC parity" ceiling in `CLAUDE.md`: the ceiling governs
what the DEFAULT dialect owes FPC (nothing), not whether a flag we shipped does
what its name says.

## The four

| gap | prio | shape |
| --- | ---: | --- |
| `Abs`/`Sqr` widths | 8 | default divergence is deliberate and documented; the strict escape hatch is missing, so shift width can be pinned and these cannot |
| pointer difference in bytes | 15 | `p - q` should count bytes when either operand is untyped `Pointer`; derivable from the source, so it is a behaviour strict mode is allowed to emulate |
| `TypeInfo(Integer)^.Name` = `LongInt` | 12 | **already decided by the user, 2026-08-21**: *"in strict FPC mode, we just mangle the name 'Integer' to 'Longint'. we are already compatible about the underlying type. it's just naming."* |
| audit flags vs `DialectIsPxx` | 12 | `DialectIsPxx` exists and **one** check consults it; the rest of `EnableStrictFpc`'s flags do not |

## Start here

**The `TypeInfo` row is the cheapest slice and is already approved** — one row
of a flat `case` in `compiler/rtti_emit.inc:806` plus a `StrictTypeNames` flag
beside the others in `defs.inc`/`EnableStrictFpc`. Doing it first proves the
add-a-flag path end to end at almost no cost.

Do the **audit** row second, not last: it is the one that says which of the
remaining flags are even wired to the right predicate, and its answer changes
how the other two are written.

## Gate

`make compiler/pascal26` + each folded ticket's own measured table, run **twice**
— once with the flag and once without — because a strict-mode change that also
moves the DEFAULT dialect is the failure this family exists to avoid. Plus
`tools/gate.sh quick`.

---

# The folded tickets, verbatim

Each section below is a ticket that was filed separately and is now
part of this one. Nothing is summarised away: the repro tables, the
measured oracle output and the located source lines are the reason
these are worth keeping, and they are reproduced unchanged.

## `--strict-fpc` does not reproduce FPC's `Abs` / `Sqr` widths

*(was `compat-pascal-strict-fpc-abs-and-sqr-widths`, prio 8)*

# `--strict-fpc` does not reproduce FPC's `Abs` / `Sqr` widths

Found 2026-08-22 by an FPC differential sweep over ordinal arithmetic
(`fpc -Mobjfpc -O1` 3.2.2 vs pxx `80bbe2f38`).

Exactly the shape of [[bug-a-strict-fpc-does-not-reproduce-fpc-shift-widths]],
one operator family later: the **default** dialect divergence is deliberate and
documented (`devdocs/dev/pascal-dialect-divergences.md`, the `Abs`/`Sqr`
section) — shifts and these two both evaluate at native width and do not
truncate to the operand's declared type. What is missing is the strict-mode
escape hatch, so someone porting FPC bit-twiddling can pin shift width with the
flag but silently cannot pin these.

## The measurement

`i: Integer`. Third column is the flag that should have changed the answer.

| expression | FPC | pxx default | pxx `--strict-fpc` |
| --- | --- | --- | --- |
| `Abs(i)`, `i = Low(Integer)` | -2147483648 | 2147483648 | **2147483648** |
| `Sqr(i)`, `i = Low(Integer)` | 0 | 4611686018427387904 | **4611686018427387904** |
| `Sqr(i)`, `i = 65536` | 0 | 4294967296 | **4294967296** |

Unaffected and must stay unaffected: `i * i` (widens in both), `-i` (widens in
both), `Abs(SmallInt)` (promotes to Integer in both), `Abs(Int64)` (wraps in
both). Only the exactly-32-bit `Abs`/`Sqr` case moves.

## What strict mode has to reproduce

FPC's rule for both is "result keeps the argument's type, after the usual
promotion of anything narrower than Integer". So under `StrictShiftWidth`'s
sibling flag:

- `Abs(x)` where `x` is a declared 32-bit signed type: compute at 32 bits, so
  `Abs(Low(Integer))` is `Low(Integer)` again.
- `Sqr(x)` likewise: a 32-bit multiply that wraps, which is why FPC answers 0
  for both rows above.

Note the wart being copied — `i * i` widens but `Sqr(i)` does not, though they
denote the same product. That is the same "explicitly copy their bugs" clause
the shift decision spelled out, so reproduce it rather than rationalising it.

## Where the code is

`Abs` and `Sqr` are builtin calls, not binops, so this is **not** the shift
arm that `StrictShiftWidth` already gates — expect a different site. Find where
the builtin's result type is assigned (the same place that already promotes
`Abs(SmallInt)` to Integer, since that row agrees with FPC) and make it keep the
argument's type under the flag, then let the existing narrow-back do the rest.
Whether this earns its own flag name or joins `StrictShiftWidth` under the
`--strict-fpc` umbrella is a judgement call; prefer joining, since a caller who
wants one almost certainly wants both.

## Prio

20. This is parity for a mode that exists to copy FPC's warts, and the default
dialect is already correct and documented. Below the compat work whose subject
is compiling real-world code.

## Gate

Every row above matching `fpc -O1` under `--strict-fpc`, the default dialect
unchanged, and self-host byte-identical.

## Pointer difference should count bytes under the flag

*(was `compat-pascal-strict-fpc-pointer-difference-bytes`, prio 15)*

# What to build

Under `--strict-fpc` (and `--mimic-fpc`), `p - q` counts **bytes** when either
operand is an untyped `Pointer`, and elements when both are the same typed
pointer — i.e. use the *smaller* of the two operands' strides, so an untyped
operand (stride 1) forces a byte count. The default dialect is unchanged and
keeps the uniform element rule.

# Why it is owed at all, and why only under the flag

`meta-dialect-extensions-and-fpc-strict` classifies it: *"Behaviour → emulate
under strict. Deterministic and derivable from the source ... Working code can
and does rely on these, so a strict compile must reproduce them even where pxx's
own default is nicer."*

FPC's answer is derivable (`{$TYPEDADDRESS OFF}` makes `@x` a `Pointer`; a
difference with no element type counts bytes), so it is a behaviour, not one of
the bugs strict mode is forbidden to emulate. That makes the strict family its
correct and only home.

# Why prio 15

Per `frontend-compat-philosophy.md`'s corpus rule, *"do not justify core work
with a corpus"* — and here not even a corpus is asking. Nothing depends on this;
it is recorded so the decision is executable if a real FPC port ever needs it,
and ranked so it does not displace work that something depends on.

# Acceptance

```pascal
var a: array[0..7] of Integer; p, p0: ^Integer; u: Pointer;
p0 := @a[0]; p := @a[2]; u := @a[0];
```
Under `--strict-fpc`: `p - p0` = 2, `p - u` = 8, `p - @a[0]` = 8 — matching
`fpc 3.2.2`. Without the flag, all three stay 2. Both polarities tested.

## `TypeInfo(Integer)^.Name` should say `LongInt` under strict-FPC

*(was `feature-a-typeinfo-integer-name-under-strict-fpc`, prio 12)*

# `TypeInfo(Integer)^.Name` should say `LongInt` under strict-FPC

- **Track A** — `compiler/rtti_emit.inc` + `compiler/lexer.inc` (the strict-flag
  bundle). Small and self-contained.
- Implements [[decide-typeinfo-scalar-name-spelling]], answered by the user
  2026-08-21: *"in strict FPC mode, we just mangle the name 'Integer' to
  'Longint'. we are already compatible about the underlying type. it's just
  naming."*

## What to change

`TypeInfoOrdName` (`compiler/rtti_emit.inc:806`) is a flat `case` over
`TTypeKind`. One row moves:

    Ord(tyInteger):  Result := 'Integer';
    ->
    Ord(tyInteger):  if StrictTypeNames then Result := 'LongInt'
                     else Result := 'Integer';

Add `StrictTypeNames` alongside the other per-behaviour strict flags in
`defs.inc`, and set it in `EnableStrictFpc` (`compiler/lexer.inc:628`) next to
`StrictOperator` / `StrictCase` / `StrictVisibility` / `StrictShiftWidth` /
`StrictVariantChar`.

**Follow that pattern, do not invent a new gate.** There is no single `StrictFpc`
boolean — `EnableStrictFpc` turns on a bundle of individually named flags, so a
new parity behaviour gets its own name and joins the bundle. That is what makes
each one separately testable and separately documentable.

No conflict with the umbrella's contract: `EnableStrictFpc`'s own comment says it
*"does NOT change default name resolution"* — this is an RTTI label, not
resolution.

## Only this one row

Measured against FPC 3.2.2 on x86-64: `Byte`, `Int64` and the rest already match.
`Integer` is the sole divergence, and it exists for a structural reason — FPC's
`Integer` is an alias of `LongInt`, while pxx has `tyInteger` and `tyInt32` as
separate kinds and so has a name of its own to report.

**The widths already agree** (both 4 bytes; native is 8 in both). Nothing about
this ticket changes a type, a size, or a computation — only a string in the RTTI
blob.

## Test

`test/test_typeinfo_named_types.pas` asserts the current answer explicitly and
points at the decision ticket. Extend it to assert **both** directions — `Integer`
by default, `LongInt` under `--strict-fpc` — in the two-row shape
`test_fpc_mem_errors.pas` uses, so a later default flip shows up as a failing row
rather than a silent change.

## Gate

`make compiler/pascal26` + self-host fixedpoint (byte-identical), `tools/gate.sh
quick`. Nothing here reaches a backend.

## Audit the remaining strict flags against `DialectIsPxx`

*(was `feature-a-audit-strict-flags-against-dialectispxx`, prio 12)*

# Audit the remaining strict flags against `DialectIsPxx`

Follow-on from
[[feature-a-strict-flags-scope-to-dialect-ownership-not-program-vs-unit]], which
established the predicate and rescoped exactly one flag.

## State after that ticket

`DialectIsPxx` (`compiler/symtab.inc`) answers "is the code being compiled right
now written in the pxx dialect", driven by `{$MODE PXX}` and already declared by
144 library files. **One** check consults it — the `StrictOverload` test in
`compiler/pasparser_proc.inc`.

The other flags in `EnableStrictFpc` — `StrictOperator`, `StrictCase`,
`StrictVisibility`, `RequireForward`, `StrictShiftWidth`, `StrictVariantChar` —
never tested `CurrentUnitIdx`, so there was no wrong axis to fix and nothing was
changed. They judge every file, our RTL included.

## The question, per flag

That is not automatically wrong, and this ticket is **not** "add
`DialectIsPxx` to all of them". The flags split into two kinds and the split is
the whole job:

- **Rule-shaped** (`StrictOverload`, `RequireForward`, `StrictCase`,
  `StrictVisibility`): "code must be WRITTEN this way". Applying these to our
  RTL means a command-line flag re-judging library source that is already
  written and shipped — the exact thing the parent ticket argued against. These
  are the candidates.
- **Semantics-shaped** (`StrictShiftWidth`, `StrictVariantChar`, and parts of
  `StrictOperator`): "this expression EVALUATES to a different value". Exempting
  the RTL here would be actively harmful — it would give one program two numeric
  behaviours depending on which side of a unit boundary the expression sits,
  which is worse than either answer alone. These almost certainly should stay
  global, and saying so explicitly in the code is the deliverable for them.

So: for each flag, decide which kind it is, and either wire `DialectIsPxx` in or
write the one-line comment explaining why it is deliberately global. A flag that
turns out to be BOTH (a rule whose violation also changes evaluation) is the
interesting case — escalate it as a Track U `decide-*` rather than guessing.

## Why prio 20

Nothing is broken today: these flags are opt-in, off by default, and our RTL
compiles under them (that is what `--strict-fpc`'s corpus claim rests on). This
is consistency work on an experimental surface, worth doing before a second flag
grows its own copy of the ownership condition — which is the failure mode
`NilPyUserCode`'s nine copies already demonstrated in this codebase.

## Gate

Each flag either consults `DialectIsPxx` with a test proving the carve-out, or
carries a comment saying why it does not. `--strict-fpc` still compiles the RTL
and the conformance pass-set.
