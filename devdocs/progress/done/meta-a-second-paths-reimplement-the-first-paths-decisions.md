---
slug: meta-a-second-paths-reimplement-the-first-paths-decisions
track: A
prio: 60
status: done
owner: frank2
---

# One concept, two mechanisms, and only one carries the capability

**Four distinct subsystems, in one day (2026-08-17).** Filed as a structural
observation rather than four coincidences, because the repo's own rule says two is
a smell and three is a design flaw — and this is four.

| # | concept | path that works | path that doesn't |
| --- | --- | --- | --- |
| 1 | `@procvar` in Delphi mode | the value-context lowering | the `@` factor rebuilt the node kind and walked into the auto-call rule |
| 2 | `*args` unpacking at a call | free functions get `PyStarForwardCall`, a **run-time** arity dispatch that preserves defaults | methods route to a **compile-time** expansion that refuses any callee with defaults |
| 3 | ~~shim attribute resolution~~ **see the correction below — this row was wrong** | | |
| 4 | call-argument marshalling | the written-argument loop computes by-ref from the parameter (`ir.inc:9175`) | the default-fill path forty lines below passed a hardcoded `False` |

## The generalisation (Track A's, and it is the useful half)

> *Wherever a second path constructs call arguments, it reimplements the first
> path's decisions and drifts.*

Not "there are bugs in these four places". The claim is that a **second
construction path is a standing hazard**: it starts as a copy, the original grows
a capability, and the copy does not. Nothing fails at the edit site, because the
copy is still internally consistent.

## The tell, and it is what makes this actionable

**A local workaround sitting next to the general bug.** In case 4, a scalar default
is boxed into a temp whose address is passed regardless of the by-ref flag, and
`= None` **hand-builds a temp and LEAs it one branch over** — the same
address-taking, done manually. Somebody hit this, fixed their case locally, and
never saw the general one. The hand-rolled compensation is the fossil of an
earlier encounter.

So: **when you find a special-case branch doing manually what a nearby general
mechanism does automatically, the general mechanism is probably broken for
everything that does not have its own special case.** That is a grep-able shape,
not a philosophy.

Case 4 is also why the reported symptom was wrong: only a default whose hidden
global is *already* a variant reached the broken load, and a class is the one value
that lands there — so it presented as "a TYPE as a default segfaults" when the type
was incidental.

## What to do

Not a fix ticket. Proposed work, in order of cost:

1. **Enumerate the second paths.** Where does argument construction, name
   resolution, or node lowering have two entry points? Cases 2, 3 and 4 were all
   found by falling over them; none by looking.
2. **For each, ask what capability the first path has that the second lacks** —
   which is how all four were actually resolved: give the deficient path what the
   other has, rather than patch its symptom.
3. **Grep for hand-rolled compensations** next to general mechanisms, per the tell
   above.

`devdocs/dev/normalise-dont-special-case.md` is the principle; this is four days'
worth of evidence for it arriving in one night, and an argument that the audit is
worth doing deliberately rather than waiting to trip over number five.

---

# Row 3 was wrong, and the correction is better evidence than the row

*(frank2, 2026-08-17, on resolving
[[bug-n-assigning-to-a-name-that-collides-with-a-pascal-shim-attribute-fails]]
at `65d26b24c`.)*

Row 3 said "`.py` shims resolve `mod.attr` fine, Pascal-unit shims don't". That
described the symptom's *distribution*, not its mechanism, and it pointed at the
wrong subsystem entirely — there is no second shim-resolution path. The real
defect is one line in `ParseFactor`: a guard that cancels the untyped string-const
table when a same-named variable exists, without asking whether the name had been
reached through an explicit qualifier. `.py` shims looked immune only because
their attributes are not string-table consts. **Corrected row 3: one concept —
"was this name qualified?" — with the answer re-decided independently at every
site that consults it.**

That is worth more than the original row, because unlike the other four it is
**enumerable**, and enumerating it found defects nobody had tripped over yet.

## Step 1 of "what to do", executed, for one axis

`ParseFactor`, lines 12880–16100. Fourteen guards test `FindSym(name)` /
`FindProc(name)` to decide whether a builtin may claim a name. **Four carried a
qualifier exemption; ten did not.**

And the four that had it did not get it by design. The comment on `Ord`/`Chr` and
`Length` names the day someone hit Synapse's `System.Length(buf)` inside a routine
with a `Length` parameter. Each site was broken until somebody fell over that
site.

So the prediction was cheap: `System.High` should fail the same way. It did —
and the oracle settled it rather than an argument:

```pascal
var a: array[0..4] of Integer; High: Integer;
...  WriteLn(System.High(a));
```

```
FPC 3.2.2:  4
pxx (before): pascal26: error: undefined variable (High)
```

**Found by enumerating the guards, not by falling over them** — which is the whole
claim of this ticket, demonstrated once rather than asserted.

## Landed

Five sites given the exemption the other four already had — `High`, `Low`,
`GetMem`, `TypeInfo`, and the identifier-spelled ordinal casts (`QWord`,
`NativeInt`, `Int64`…). Uniformly `(qUnit = -2) or (<the site's own test>)`:
**only** the `System.` marker, never a real `unit.Name` qualifier — `myunit.High`
must keep meaning that unit's routine, so the exemption must not widen to
`qUnit >= 0`.

`test/test_pascal_system_qualified_intrinsic.pas` pins all five in one program,
each local named after the intrinsic on the line below it, plus a final line
asserting the BARE names still read the locals — that last line is what catches
an exemption written so broadly it breaks ordinary scoping. Expectations verified
against FPC 3.2.2 directly.

**Deliberately not touched:** the pxx-private intrinsics (`__pxxExceptAddr`,
`__pxxSig*`, `__pxxGetFPUMask`/`SetFPUMask`, `get_frame`, `get_pc_addr`). They
have no FPC counterpart, nobody writes `System.__pxxSigCode`, and there is no
measurement saying they are reachable that way. Left as the remaining known-bare
sites rather than changed unmeasured.

## Where this leaves the ticket

The generalisation still stands and rows 1, 2 and 4 are unchanged. What the
correction adds is a **sharper test for which instances are worth auditing**: the
enumerable ones are those where the second path re-answers a *question* (was this
qualified? is it by-ref? does it have defaults?) rather than re-implementing a
*mechanism*. Those can be listed by grepping for the question and checking who
asks it. Rows 1 and 2 are mechanism duplication and have no equivalent grep.

## Second slice: the statement path, same axis

`ParseStatementAST` (lines 22833–24814) keeps its **own** copy of these guards
and had never been compared against the expression path's. Nine of them; four
carried the exemption, five did not. Predicted, then oracle-confirmed before
changing anything:

```pascal
var Break, Continue, Halt: Integer;
...  if i = 1 then System.Continue;   { pxx: "unexpected token" }
     System.Halt(0);                  { pxx: "unexpected token" }
```

FPC 3.2.2 accepts all of them. Fixed `Halt`, `Exit`, `Break`, `Continue` —
`(qUnit = -2) or (<the site's own test>)`, identical to the expression side —
and the test program now covers both halves in one file, diffed against FPC
rather than compared to a hand-written expectation.

**Left alone, deliberately:** `FreeAndNil` (SysUtils, not System — `System.FreeAndNil`
is not valid FPC, so there is nothing to be compatible with) and
`get_caller_stackinfo` (pxx-private). Both are the remaining known-bare
statement sites.

## Score for this axis

23 guards across the two paths; 8 carried the exemption, 15 did not. **Nine
fixed** (5 expression + 4 statement), six left bare with a stated reason. Every
fix was predicted from the list and confirmed against FPC before it was made —
none was found by a corpus or a bug report, which is the argument the ticket was
filed to make.

## Third slice: `isRefArg` (row 4's question) — a NEGATIVE result

The slice with teeth, because getting this one wrong yields a wrong value or a
segfault rather than a diagnostic. Enumerated all 34 call sites of
`IRLowerCallArg` by the fourth argument they pass. Twenty-eight compute it from
the parameter; **four still pass a hardcoded `False`** (plus the one already
fixed at `ir.inc:9490`). All four were checked, and **none is a live defect**:

- `ir.inc:7274/7276` and `7326/7328` — the `pytruediv_f` and `pyfloormod_i`
  pylib calls. Both routines are declared `(a: Double; b: Double)` /
  `(a: Int64; b: Int64)` in `compiler/builtin/pylib.pas`, i.e. by value, so
  `False` is the correct answer and the sibling sites' computed form evaluates
  to it. Inconsistent spelling, not a defect.
- `ir.inc:9504` and `9550` — the FLOAT and INT arms of the very default-fill
  block whose variant arm was the row-4 bug. Harmless for the reason recorded in
  the comment there: a scalar default is boxed into a temp whose **address** is
  the argument no matter what `isRefArg` says. Only a default that is *already*
  a variant reached the load that broke.

**Left unchanged deliberately.** There is no measured behaviour difference, and
an unmeasured edit to the argument-marshalling path is a bad trade — this is the
one place in the audit where being wrong is silent. Recorded here so the next
reader does not have to re-derive it, and so a future change to the boxed-scalar
path knows these two are relying on it.

So row 4's question is **bounded**: it was asked wrong in exactly one place, and
that place is fixed.

## Closing this out

Step 1 is done for every axis that has a method. Two questions were enumerable —
"was this name qualified?" and "is this parameter by-ref?" — and both were run to
the end: 9 real divergences fixed on the first, 0 found on the second, each
checked against an oracle rather than argued. Step 3 (grep for hand-rolled
compensations) turned up the `= None` branch already named in the original text
and nothing further.

**What is left is rows 1 and 2, and they are left because there is no method for
them** — mechanism duplication has no question to grep for. That is not a task
that fits in a session; if someone finds a way to enumerate it, that is a new
ticket, not this one continuing to sit in `working/` as a lock nobody holds.

The durable output is not the nine fixes. It is the test for which instances of
this pattern are auditable at all: **a second path that re-answers a QUESTION can
be enumerated by grepping for the question and checking who asks it; a second
path that re-implements a MECHANISM cannot.** That distinction is worth carrying
into `devdocs/dev/normalise-dont-special-case.md` the next time someone edits it.

## Log
- 2026-08-17 — resolved, commit PENDING-COMMIT.
