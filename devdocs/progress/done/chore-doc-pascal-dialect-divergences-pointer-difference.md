---
slug: chore-doc-pascal-dialect-divergences-pointer-difference
title: "Record two chosen Pascal dialect divergences: pointer-difference units, and the one-tag Null/Unassigned"
track: D
prio: 25
type: chore
blocked-by: []
status: done
owner: frankD
created: 2026-08-25
summary: "Re-filed from decide-pointer-difference-unit and decide-should-a-null-variant-raise-like-fpc, both decided 2026-08-25. Two divergences from FPC are now CHOSEN rather than merely inherited, and a chosen divergence that is not written down is indistinguishable from a bug to the next reader. Both entries land in devdocs/dev/pascal-dialect-divergences.md."
---

# Why this is a real ticket and not bookkeeping

`frontend-compat-philosophy.md` draws the whole line here: the dialect *"licenses
different SEMANTICS **chosen on purpose**; it never licenses a wrong answer
nobody chose."* The difference between the two halves of that sentence is
whether the choice is recorded. Undocumented, both of these read to the next
session as bugs and get re-diagnosed.

# Entry 1 — `p - q` counts ELEMENTS, always

Per [[decide-pointer-difference-unit]]. FPC answers **bytes** when either
operand is an untyped `Pointer` — which under its default `{$TYPEDADDRESS OFF}`
includes `@x`. pxx scales by the left operand's stride whatever the right
operand is.

```pascal
var a: array[0..7] of Integer; p, p0: ^Integer; u: Pointer;
p0 := @a[0]; p := @a[2]; u := @a[0];
{ p - p0   : fpc 2   pxx 2  }
{ p - u    : fpc 8   pxx 2  }
{ p - @a[0]: fpc 8   pxx 2  }
```

Say why: the uniform rule is derivable from the language ("a pointer difference
counts elements"), FPC's is derivable only from `{$TYPEDADDRESS OFF}`. Give the
porting advice the rejected diagnostic would have printed — *cast the untyped
operand to the pointer type, or to `PtrUInt` for a byte count* — since a reader
arriving from FPC code is exactly who needs it. Note that FPC's semantics is
available under `--strict-fpc` (see
`compat-pascal-strict-fpc-pointer-difference-bytes`).

# Entry 2 — `Null` and `Unassigned` share one tag, and neither raises

Per [[decide-should-a-null-variant-raise-like-fpc]]. pxx spells FPC's `Null`,
FPC's `Unassigned` and NilPy's `None` with a single `VT_EMPTY` tag. FPC prints
an `Unassigned` as empty but **raises** `EVariantTypeCastError` for a `Null`, in
both `string(v)` and `WriteLn(v)`. pxx prints empty for both and never raises.

Consequences to state, because they are what a reader will hit:
`VarIsNull` and `VarIsEmpty` both answer True for both spellings, and
`VarType` reports `varEmpty` (0). The conflation is currently documented only
in `lib/rtl/variants.pas`' header and in `builtin.pas`' `PXXVarBinOpPas` — note
there that it gives the *right* answer for arithmetic, since FPC propagates both
through arithmetic as themselves and one propagating tag is correct.

# Scope

Prose only. Track D: `devdocs/dev/pascal-dialect-divergences.md`. No
`compiler/**`, no `lib/**`. Verify the code snippets compile against
`$(PXX_STABLE)` rather than transcribing them from the decision tickets.

## Log
- 2026-08-29 — resolved, commit 2809268b5.

---

## RESOLVED 2026-08-29 (frankD)

Both entries appended to `devdocs/dev/pascal-dialect-divergences.md` in the house
format. The ticket said to verify the snippets rather than transcribe them from the
decision tickets — that instruction earned its keep twice: **two things the ticket
asserts are wrong**, and both would have been published as fact.

### Correction 1 — "fpc 8" is mode-dependent, and the snippet as filed prints 4

The ticket's snippet annotates `p - u` and `p - @a[0]` as `fpc 8`. Run under plain
`fpc` it prints **4**, because `Integer` is **16-bit in FPC's default mode** and
32-bit only under `-Mobjfpc` / `-Mdelphi`. The FPC column is a *byte count*, so it
is not a number at all until a `{$mode}` is fixed:

| | `fpc` (default) | `fpc -Mobjfpc` | pxx |
| --- | --- | --- | --- |
| `SizeOf(Integer)` | 2 | 4 | 4 |
| `p - u` | 4 | 8 | **2** |

The divergence is bytes-vs-elements and never a particular integer. Written that
way, with both modes measured — a reader who copies the snippet, runs `fpc`, and
gets 4 would otherwise conclude the page is wrong. This is the same trap the
`GetHashCode` entry directly above already warns about in its own last paragraph
(*"the `{$mode}` line is load-bearing in any probe of this"*), hit independently.

### Correction 2 — `--strict-fpc` does NOT restore byte semantics

The ticket says *"FPC's semantics is available under `--strict-fpc`"*. It is not.
Measured on v393: `--strict-fpc` and `--mimic-fpc` both still print `2`. The
decision *routed* it there; nobody implemented it. Publishing "available" would have
sent a reader to a flag that silently does nothing — worse than silence, since the
page exists to stop re-diagnosis.

The cited ticket `compat-pascal-strict-fpc-pointer-difference-bytes` also **does not
exist**: it was folded into [[compat-pascal-the-strict-fpc-flag-family-is-incomplete]]
(prio 15), which records the absorption on its own line. The entry cites the live
ticket. No new ticket filed — the general problem already has one
(`chore-t-a-wikilink-to-a-ticket-that-does-not-exist-is-never-detected`), and the
dead slug survives only in `decided/`, which is a session record and not mine to
rewrite.

### Everything else in the ticket held, measured on v393 vs `fpc -Mobjfpc`

- pointer difference: pxx `2 / 2 / 2`; FPC `2 / 8 / 8` (objfpc);
- porting advice **checked on both compilers**, which is what makes it advice rather
  than a guess: `p - PInt(u)` gives 2 on both, `PtrUInt(p) - PtrUInt(u)` gives 8 on
  both — both spellings are portable;
- `VarType`: pxx `0`/`0` for `Null`/`Unassigned`; FPC `1`/`0`;
- `VarIsNull` and `VarIsEmpty`: **both True for both spellings** in pxx; FPC answers
  them apart. Stated as the consequence a reader hits — telling a SQL NULL from an
  uninitialised variant cannot be done here;
- `WriteLn(v)` / `string(v)` of `Null`: pxx `[]` exit 0; FPC dies at the `WriteLn`
  with `EVariantTypeCastError: Could not convert variant of type (Null) into type
  (String)`, exit 217. Message and exit code string-compared against real output;
- **the arithmetic justification checked rather than repeated**: FPC propagates
  *both* through arithmetic as themselves and raises for neither (`Null + 1` → Null,
  `Unassigned + 1` → Unassigned), so one propagating tag really is the right answer
  for arithmetic — behaviour agrees, only the `VarType` tag differs. That is the
  claim `PXXVarBinOpPas` rests on and it survives contact with the oracle.

### On the oracle discipline this page demands

The page warns against hand-rolled FPC comparisons because a dead oracle and an
agreeing oracle print the same thing. `tools/fpc_diff_probe.sh` carries a fixed case
list in `tools/` — Track T's file, not mine to extend — so every FPC run here
checked the compile exit status and the existence of the binary before reading any
output, and would have printed `ORACLE DEAD` instead of a silent pass. That is the
substance of the warning without touching another lane's file.

### Lane note

`devdocs/dev/**` is outside Track D's lane as CLAUDE.md draws it (`docs/**`, and
explicitly *not* the internal dev docs). This ticket is filed `track: D` and names
this file as its scope, and the file's own history shows every lane writing its own
entry (`docs(p)`, `docs(O)`, `docs(B)`, `docs(divergences)`), so the convention is
"whoever made the choice records it" rather than exclusive A/B ownership. Nothing
else held the file. Proceeded on that basis and raised it with the coordinator
rather than deciding the boundary silently.
