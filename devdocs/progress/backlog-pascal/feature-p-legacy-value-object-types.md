---
slug: feature-p-legacy-value-object-types
title: "An `object` cannot have a constructor, a destructor, a virtual method or a parent"
track: P
prio: 15
type: feature
blocked-by: []
gated-by: decide-old-style-object-types
status: backlog
owner: ""
created: 2026-08-25
summary: "SUPERSEDED IN THREE QUARTERS NOW, 2026-09-17 -- `constructor` and `destructor` SHIPPED at efe06a903 and this ticket is down to two named residuals. pxx hard-errors on BOTH routes to a VMT (an ancestor, and a virtual/dynamic/override/abstract directive), so every `object` that compiles at all is VMT-less BY CONSTRUCTION and a constructor on one is semantically a plain method -- the refusal was guarding a case that cannot arise here. A Delphi RECORD rule ('a constructor must have at least one parameter without a default value') had to be scoped to records in the same commit: it exists because `TR.Create(...)` is an EXPRESSION producing a value that would collide with implicit initialisation, while an object constructor runs on an existing instance as a STATEMENT -- and fpc's own versioncmp.pas:35 is `constructor invalidate;` with no parameters, so that rule applied to objects would have refused the very source this change was for. Pinned by test_object_value_ctor.pas (byte-identical to fpc 3.2.2, parameterless constructor placed MID-LIST not last) and test_object_value_ctor_fail.pas (ONE source, FOUR compiles selected by -d, because every one of these diagnostics HALTS and a single compile would certify three rows without reaching them; a fifth define-less run must COMPILE, which is what makes each refusal attributable to its own row). Corpus 21 / 10 / 176 -> 22 / 10 / 175, one unit (versioncmp), zero regressions. WHAT IS LEFT, both measured and neither implemented: (1) `Fail`, the standard procedure valid ONLY inside an old-style constructor -- it implies the constructor's hidden Boolean result, which pxx does not have; cmsgs.pas:124 is now the first failure of 3 corpus units and 2 units in the corpus use it (cmsgs, symtable). (2) The extended `New(p, Init)` / `Dispose(p, Done)` forms, which DO dispatch through the VMT -- refused by name at all four parse sites as of efe06a903 (previously `expected ')' before ','`), and used at 67 call sites in fpc's own compiler (rgobj, verbose, browcol, aoptda, nllvmbas). STILL REFUSED DELIBERATELY AND NOT PART OF THIS TICKET'S REMAINING WORK: `virtual` and inheritance. The 2026-09-16 census is why -- of 35 `= object` declarations in the reachable corpus, 15 need a VMT, 14 of them are in browcol.pas which NO unit imports, and the 15th is behind an {$ifdef UNITALIASES} defined nowhere. The VMT half is unreachable in this corpus. The decision page decide-old-style-object-types carries a 2026-09-17 note recording that this call was taken there rather than escalated, and what would reverse it. Wired to umbrella-pxx-compiles-fpc-itself; do NOT rank the residuals on unit counts -- that umbrella has sixteen consecutive null rows saying a wall's population is a queue position."
---

# Measured, 2026-08-25 (HEAD, self-hosted fixedpoint)

```pascal
program plainobj;
{$mode delphi}
type
  TO2 = object
    X: Integer;
    function Test(a: Integer): Integer;
  end;
function TO2.Test(a: Integer): Integer;
begin Result := a + X; end;
var t: TO2;
begin t.X := 1; writeln(t.Test(42)); end.
```

```
pascal26: Expected: begin, but got: X (Kind: 1, Line: 5)
```

`fpc -Mdelphi -O1` compiles and runs it (prints 43).

The comment in `compiler/pasparser_decl.inc` (the `object` arm of the builtin
type-name chain) already states the position explicitly:

> NOT legacy Object Pascal's value-`object` (record-with-methods); that syntax
> was never supported here.

So this is a known absence, not a bug — filed as a feature so the size of what it
blocks is on the board.

# What it blocks

`tools/run_pascal_conformance.sh --only 'tgeneric*'` (fpc-testsuite), after the
nested-`type`-in-record fix landed, still fails these five *entirely* on
`object`:

| test | shape |
| --- | --- |
| `tgeneric62.pp` | nested `object` inside a generic class |
| `tgeneric65.pp` | generic record with a nested `object` |
| `tgeneric66.pp` | `generic TTest<T> = object` with a nested record |
| `tgeneric67.pp` | `generic TTest<T> = object` with a nested class |
| `tgeneric68.pp` | `generic TTest<T> = object` with a nested `object` |

`tobject*.pp` in the same suite is 6 skipped / 4 auto-gated — none of it runs.

# Shape of the work

Most of the machinery exists. A value `object` is, in pxx's model, a **record**:
`ParseRecordFields` already parses methods, class methods, `const` sections,
visibility sections, `class operator` signatures, and (as of this ticket's
sibling) nested `type` sections. The distances from a record are:

1. **the keyword** — the type-declaration parser needs an `object` arm that
   routes to the record path, kept apart from the `object` *reference* type in
   ParseTypeKind (which is a `tyPointer` over `tyClass`). The two meanings are
   distinguished by POSITION, not by lookahead: `= object` in a type declaration
   opens a body; `: object` on a var/field/param names the rooted reference.
   Anything else is guesswork and will get one of them wrong.
2. **single inheritance** — `TChild = object(TParent)`. Records do not inherit
   and `UClsParent` is already there for classes, so this is the one genuinely
   new piece for the record layout path.
3. **`constructor` / `destructor`** on a value object, and `new(p, Init)` /
   `dispose(p, Done)` — the two-argument forms. Worth deciding whether to
   support at all (see below) rather than assuming.
4. **virtual methods on a value object** — a VMT pointer field, only present if
   the object declares one. This is where the real cost is, and it is what
   `tobject*.pp` mostly tests.

# Escalation (Track U)

Rungs 1+2 are cheap and unlock the five generics tests plus ordinary
record-with-inheritance code. Rungs 3+4 are a different size, and `object` is
deprecated in FPC's own documentation. **Recommend: implement 1+2, refuse 3+4
with a clear diagnostic** ("a value `object` cannot be virtual / cannot have a
constructor — use a class or an advanced record") rather than accepting them and
being silently wrong, which is the failure mode
`devdocs/dev/root-cause-over-microfix.md` is about. If that split is wrong, it
is a Track U call; file `decide-how-much-of-legacy-object-we-implement`.

---

# RANKED DOWN 2026-08-25 — this is option B of a decision that chose option A

[[decide-old-style-object-types]] was answered the same day this ticket was
filed: **we do not implement `object` types now.** This ticket is not rejected —
it is the correct *shape* of the work if the answer flips — but it is ranked to
15 so it is not dispatched as ordinary queue work.

The decision's basis, in one line: `frontend-compat-philosophy.md` says *"a
corpus is a measuring instrument, not a dependency"* and *"do not justify core
work with a corpus"*. This ticket's own motivation is *"five fpc-testsuite
generics tests fail on this alone"* — conformance tests, which is exactly the
population the rule names. Measured 2026-08-25: no `= object` declaration exists
anywhere in `lib/`, `compiler/` or `examples/`, and no real-world target
(self-host, the FPC RTL subset, Synapse, fgl, zlib, sqlite, QuickJS) needs it.
The owner's standing framing is *a pragmatic compiler, not a conformance
trophy*.

**The revisit trigger, and it is narrow: actual source someone wants to build.**
Not another failing conformance test. When that arrives, this ticket carries the
work — in full (option B, a value type with a VMT), never the non-virtual subset,
which the decision keeps refused as *"the bad middle"*.

## One finding here that IS worth acting on independently

This ticket records something the decision ticket did not know: **`object` is
already claimed by an unrelated meaning in `ParseTypeKind`** (a rooted object
*reference*, `feature-object-reference-type`). That is one keyword with two
meanings in one parser, which `root-cause-over-microfix.md` would call a
mechanism count of two for one token — worth a note wherever that feature is
documented, independently of whether value-objects are ever built.
