---
slug: bug-p-a-class-property-cannot-be-backed-by-a-class-var
title: "A class property can only be backed by a static METHOD — never by a class var, on a class or a record"
track: P
prio: 50
type: bug
status: done
found: 2026-09-05
found-by: frankA
owner: ""
blocked-by: []
summary: "FIXED 2026-09-05. `class property V: T read FV write FV` over a `class var FV: T` now works in EVERY spelling, on a class, a record and a class HELPER: type-qualified (`TCls.V`), unqualified inside an instance method and inside a `class procedure ... static`, Self-qualified, instance-qualified (`a.V`, and a record variable's `r.Val`), and inside a `with` scope -- which additionally could not see a bare class var at all. Thirteen forms, each read and write, each byte-identical to fpc 3.2.2. tstatic2 came OFF the skip list, verified by OUTPUT rather than exit code; terecs3 stays on it behind an unrelated record-constructor wall. The cause was one thing wearing several diagnostics: both declaration parsers put any accessor that is not an instance FIELD into the METHOD slot, so a class-var backing arrived there and every consumer resolved it with FindUMeth alone. Every arm re-enters ParseLValueAST on the backing GLOBAL rather than building a MakeAccessorCall against Self -- not a style choice: a class var is not per-instance, so the reuse-the-surrounding-shape fix would have compiled, run, and read PER-INSTANCE storage where the program asked for the shared slot, a wrong value with no diagnostic. test_class_property_through_an_instance.pas asserts SHARING (every write through one instance, every read back through another) with an ordinary instance field written in the same lines as the control that must NOT be shared. NOT the fix, measured and reverted: widening only the record parse arms yields a declaration that cannot be used."
---

# A class property cannot be backed by a class var

## Measured

    program cp;
    {$mode delphi}
    type
      TR = record
      class var
        FVal: LongInt;
      class property Val: LongInt read FVal write FVal;
      end;
    var a, b: TR;
    begin
      TR.Val := 41;  WriteLn(TR.Val);   { fpc: 41 }
      a.Val := 7;    WriteLn(b.Val);    { fpc: 7  — shared, not per-instance }
                     WriteLn(TR.FVal);  { fpc: 7  }
    end.

fpc 3.2.2 prints `41 / 7 / 7`. pxx refuses at the declaration:

    pascal26:7: error: record property accessor is neither a field nor a method: FVal

## What was tried and did NOT work — recorded so it is not tried again

Widening the two accessor arms in `ParseRecordPropertyDecl` to accept a
`FindClassVar` hit makes the declaration parse. Both accesses then fail at USE:

    pascal26:11: error: class property is read-only: Val      { the write }
    …and the read fails at its own use site too

`pasparser_lval.inc:1073` gates the write on `UPropWriteMLen`, the METHOD
accessor length, so a field-backed class property is read-only by construction
there — and the read path has no field-backed arm either. **The parser
diagnostic is not where the gap is.** The change was reverted; the rebuilt
compiler was byte-identical to the build before it, which is the proof the
revert was exact.

## Why it is worth doing

Three conformance rows stop here as their first error now that the `class var`
half has landed (terecs3, terecs8, tobject6). The storage already exists and
`TR.FVal` resolves today — only the property indirection is missing, so this is
plumbing an existing slot through an existing accessor mechanism rather than a
new storage model.

## Where to start

`UPropReadFOff/FLen` and `UPropWriteFOff/FLen` store a NAME, not an offset, so
the downstream resolution re-looks-up the name. Check whether the lvalue path
can be taught to try the ClassVar registry when the field lookup misses, rather
than adding a third accessor kind — a third kind means every consumer of the
four Upro slots grows an arm, which is the shape this repo calls a second path
that stays broken.


## 2026-09-05, later — it is not record-only, and the title was a hypothesis

The first version of this ticket said "record property accessor" because a
record was where I met it. Measured within the hour, on a CLASS:

    type
      TC = class
      private
        class var FV: Integer;
      public
        class property V: Integer read FV write FV;
      end;
    begin
      TC.V := 9; WriteLn(TC.V);   { fpc 3.2.2: 9 }
    end.

    pascal26:11: error: class property accessor not found: FV

**A different message, from a different file, at a different phase** — the
record spelling is refused while PARSING the declaration, the class spelling
parses and fails at the USE. That is exactly why it looked like two problems and
is one: `pasparser_lval.inc:1063-1084` builds the accessor name from
`UPropReadMOff/MLen` or `UPropWriteMOff/MLen` — the METHOD slots — and then calls
`FindUMeth`. There is no field-backed arm on either side, so **a class property
can be backed by a static method and by nothing else**, whatever declares it.

`tstatic2` joins the row list from that: it is a class with
`class property SomethingStatic: Integer read FSomethingStatic write SetSomethingStatic`,
and the unqualified read inside the static method is the property, not the class
var. It surfaced as `undefined variable (SomethingStatic)` in the
undefined-variable wall, which is why it was not obviously this bug.

**Fix the lvalue path, not the parse arms.** The record-side parse refusal is
the surface; widening it alone produces a declaration that cannot be used.

## 2026-09-05, fixed for the type-qualified spelling — and the third site named

The fix is a `FindClassVar` fallback in the class-property arm of
`ParseLValueAST`: when `FindUMeth` misses, resolve the accessor name as a class
var and **re-enter on the backing global**, exactly as the class-VAR arm forty
lines below already does. That was chosen over a third accessor kind through the
four `UProp` slots because every consumer of those slots would grow an arm — the
shape this repo calls a second path that stays broken. Re-entering also means
read and write both work from one line, and suffixes parse, so `TC.V[0]` over a
class-var array behaves like `TC.FV[0]` already did.

The record declaration parser also had to stop refusing the accessor: it now
routes a class var to the method slot the way the class parser already routed
anything that was not an instance field, so both declaration paths arrive at the
lvalue fix in the same shape. Its diagnostic for a genuine typo now says
"neither a field, a method nor a class var".

**Result, measured:** `terecs8` and `tobject6` compile, run and produce output
**identical to fpc 3.2.2** — checked as output, not as exit code, because this
harness compares exit codes and a row printing wrong values would land in the
same bucket. Both removed from the skip list.

### The third site, precisely

`a.V := 7` and a bare `SomethingStatic` inside the type's own static method do
NOT go through the arm that was fixed. They reach the instance/unqualified
accessor path in the same file (`pasparser_lval.inc`, the
`UPropWriteMLen[pri] > 0` branch, around line 831), which builds the setter name
and calls its own `FindUMeth` — the identical missing arm, one branch over:

    pascal26:13: error: setter method not found: FVal

Its read sibling is a few lines below it. The lowering differs from the fixed
arm: that branch builds a `MakeAccessorCall` with `selfNode`, and a class var is
not per-instance, so the correct move is again to re-enter on the backing global
and ignore the receiver — not to synthesise a call.

**Two rows wait on it:** `tstatic2`, and `terecs3` behind a record-constructor
wall it hits first. Left undone deliberately rather than attempted at the end of
a session: it is a different lowering in a branch with a live `selfNode`, and
the failure mode of getting it wrong is a silent per-instance read of shared
storage.


## Resolved 2026-09-05 — every spelling, and two arms fewer than the fix started with

**Six sites, not the three the ticket named.** The boundary in the summary was
again a hypothesis about what I had happened to look at. Enumerating FORMS
rather than reading the parser found them in one pass — twelve probe files,
each compiled by pxx and by fpc 3.2.2 and diffed on OUTPUT — and each error site
was attributed exactly by temporarily tagging every `method not found` string
with its own line number, because five sites shared one message and a single
fire could not otherwise say which arm produced it.

| form | pre-fix site | pre-fix diagnostic |
| --- | --- | --- |
| `V := 7` unqualified in an instance method | lval 839 | `setter method not found: FV` |
| `x := V` unqualified in an instance method | lval 912 | `property getter method not found: FV` |
| `a.V := 7`, `Self.V := 7`, `r.Val := 41` | lval 2464 | `setter method not found: FV` |
| `x := a.V` | lval 2501 | `getter method not found: FV` |
| bare name in a `class procedure ... static` | never reached | `undefined variable (SomethingStatic)` |
| `with a do V := 7` / `with a do x := V` | never reached | `undefined variable (V)` |

The last two are the ones the ticket could not have predicted from the first
four, and they fail through a **different mechanism**: those paths are keyed on
`CurSelfClass`, so a static class method — which has no Self and needs none for
shared storage — never enters the property branch at all. The `with` scope had
the wider gap: it could not resolve a bare `class var` either, only the property
over one, so `with a do FV := 7` was `undefined variable` on a name the same
method body resolves fine one line outside the `with`.

**The recursion guard is load-bearing and was found by a segfault, not by
review.** The with-scope block runs on every entry to `ParseLValueAST`,
including the re-entry, and resolves from the same `identTokIdx` — so the first
version recursed until the stack died, on three probes. `cvIdx <> idx` compares
the resolved SYMBOL rather than gating on `idx < 0`, which keeps a with-scoped
class var shadowing an unrelated global of the same name.

**Two of the five arms were then removed as subsumed, and that was measured, not
assumed.** Once the bare-name arm was keyed on `CurMethClass` (beside the
existing bare class-VAR arm, for the same stated reason — a class procedure has
no Self), the `CurSelfClass`-keyed arms at 839 and 912 became unreachable for
this case. Deleting code because it looks dead is the error, so the A/B was:
remove them, rebuild, re-run all thirteen forms plus the sharing test — all
green — and specifically add the **class helper** probe, which is the one shape
where `SelfMemberCi` and `CurMethClass` can disagree. It passes too. The fix is
three arms, not five.

**Direction is not a detail.** `tstatic2`'s property is
`read FSomethingStatic write SetSomethingStatic` — a class var one way and a
static method the other. An arm that resolved a class-var accessor without
asking which direction was being parsed would have silently bypassed the setter.
Only the slot for the direction actually being parsed may answer.

**Negative control.** `test_class_property_through_an_instance.pas` was run
against the pre-fix compiler (`80a583aed8c6`, this tree with only
`pasparser_lval.inc` reverted): refused at the first row. Restoring the patch
rebuilt to `64cd35f4668f`, byte-identical to the build the A/B produced, which
is what makes the revert exact rather than approximately exact.

**What the test asserts and why it is shaped that way.** Every access in the
file would also compile against per-instance storage — one object, one slot,
right answer for the wrong reason — so every write goes through one instance and
every read comes back through **another**, and an ordinary instance field is
written in the same lines as the control that must NOT be shared. That control
prints `1 0` on the same run that the shared rows print `1`, so the file
demonstrates it can distinguish the two, rather than asserting it can.

**Conformance.** `tstatic2` compiles, runs `rc=0`, and prints fpc's own two
lines — burned from the skip list on OUTPUT, not on exit code, which is the only
reading that means anything given the harness compares exit codes. `terecs3`
now fails on `a record constructor must have at least one parameter without a
default`, an unrelated wall, and its skip reason says so. `terecs_u1` is a
harness gap (a unit with no standalone-unit output) and is unaffected.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
