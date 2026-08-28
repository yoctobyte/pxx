---
prio: 80
track: P
owner: frankA
status: done
---

# A METHOD called with missing arguments compiles and reads garbage (free routines are checked)

- **Type:** bug — **silent wrong behaviour**, broad surface. Compiles clean,
  runs, prints garbage. No crash to notice.
- **Track P** (Pascal frontend, call resolution).
- **Pre-existing:** identical on **pinned**.
- **Binary:** `4157f75831bb`. Oracle: FPC 3.2.2.

## The defect

A bare method reference — `s.IPick` where `IPick(A: LongInt)` needs an argument
— is compiled as a **zero-argument call**, with whatever happens to be in the
argument register read as `A`. FPC rejects it:

```
Error: Incompatible types: got "TSvc.IPick(LongInt):LongInt;" expected "LongInt"
```

## It is ONE ARM of a double case, and the other arm is correct

| shape | pxx | FPC |
| --- | --- | --- |
| **free** function, missing arg — `n := FPick;` | **compile error** | rejects |
| **method** function, missing arg — `n := s.IPick;` | `1459617816` | rejects |
| **method** procedure, missing arg — `s.IDo;` | `IDo -941621240` | rejects |
| **method** function, missing arg, inside an expression — `n := s.IPick + 1;` | `-1319108583` | rejects |
| method, correct arity — `n := s.IPick(4);` | `12` | `12` |

Free routines are arity-checked. Methods are not, in every position tried. This
is the exact shape `normalise-dont-special-case.md` is about: one concept, two
paths, and the second path is the one that stayed broken.

## Why prio 80

Every one of these compiles and produces a plausible number. There is no
diagnostic, no crash, and nothing at the call site that reads as wrong — a
missing argument list looks like a property read or a parameterless call. In a
corpus the size of `lib/pcl` or Synapse, a single dropped argument list is
invisible and produces a wrong value forever.

Note the two failing shapes that are *not* assignments: a bare `s.IDo;` statement
and a method inside an arithmetic expression. So this is not reachable only
through a method-pointer context — it is any mention of a method without its
arguments.

## It is also the mechanism under the method-pointer bug

[[bug-p-a-class-method-cast-to-a-method-pointer-inline-segfaults]]'s remaining
half ("defect B", the inline cast) is downstream of this. `TSel(s.IPick)` works
in FPC because `s.IPick` without arguments **cannot** be a call there, so it can
only be a method reference. In pxx it silently *can* be a call, so the parser
takes that reading, produces an `Int64`, and the cast reinterprets that integer
as a `Code`/`Data` pair — which is the segfault.

**So fix this first.** Once a bare method mention with missing arguments is no
longer a viable call, the cast site has only one reading left and defect B may
fall out rather than needing its own arm. Worth checking before writing that arm:
there are already **four** near-identical `AN_METHODREF` construction sites
(`pasparser_expr.inc` ×2 for the `@` forms, `pasparser_stmt.inc` ×2 for the
Delphi `@`-optional forms), and a fifth would be past the point where
`root-cause-over-microfix.md` says to count mechanisms rather than add one.

## Repro

```pascal
program ar;
{$MODE DELPHI}{$H+}
type
  TSvc = class
    function IPick(A: LongInt): LongInt;
  end;
function TSvc.IPick(A: LongInt): LongInt; begin Result := A * 3; end;
var s: TSvc; n: LongInt;
begin
  s := TSvc.Create;
  n := s.IPick;      { no argument supplied }
  WriteLn(n);        { FPC: compile error.  pxx: a garbage number }
end.
```

## The check is also a DETECTOR — and that reframes the work

*(frank-coordinator, 2026-08-27; the sequencing below is its call, not mine.)*

Fixing this is a **strictness change**: source that compiles today stops
compiling. That blast radius lands outside Track P — `lib/pcl` is Track B's,
and `compiler/**` is the self-host gate. So the order matters:

1. **Land it as a diagnostic first** — a warning, or behind a flag.
2. **Count the hits** across `compiler/**`, `lib/**`, and the corpus.
3. **Only then promote to an error.**

The reframing that makes this more than caution: **every hit is a live bug.**
A hit inside `compiler/**` is a method call that has been silently reading a
garbage argument *in the compiler itself*, and it has been doing so for as long
as the call existed. Each such hit deserves its **own ticket** — they are not to
be fixed en route to landing the check, because each one is a separate wrong
value with its own blast radius.

There is direct precedent in this repo for the failure mode, in another
frontend: `WarnCrossBindArity` (`lexer.inc:227`) exists because a C declaration
binding to a Pascal routine of different arity made `time(NULL)` fault inside
`Time` and `exp(x)` return e^(previous result) — *"the call compiles and crashes
somewhere else entirely"*, *"the argument never arrived"*. Same mechanism, same
silence, already diagnosed once. This ticket is that check's missing sibling on
the Pascal method path.

## The measurement (2026-08-28)

Probe: `PXXDBG=p.arity`, `PxxArityProbe` in `ir.inc`, **off by default**, a
pure `writeln` that deliberately does not touch `WarnCount` or interact with
`-Werror` — a measurement must not perturb what it measures.

**Why it lives in IR lowering and not in the parser.** The Pascal frontend
writes the method-call argument loop out **eight** times (`pasparser_call` ×1,
`pasparser_expr` ×2, `pasparser_lval` ×5), and `pyparser` six more. A
parser-side check therefore costs fourteen edits and fourteen chances to miss an
arm. AN_CALL lowering is the one place every arm converges with both the proc
index and the argument chain in hand. *(That 8× duplication is itself a
`root-cause-over-microfix.md` "three is a design flaw" signal, and is the reason
the eventual real fix should probably not be written fourteen times either.)*

**Two corrections the probe needed before its numbers meant anything** — both
found by asking what the measurement was blind to, not by trusting a zero:

- **`AN_CALL:` is one of three call arms.** `AN_VIRTUAL_CALL:` and
  `AN_CLASS_VIRTUAL_CALL:` lower separately, so the first "zero hits across
  `compiler/**`" had silently excluded *every virtual method call* — most of the
  interesting surface in a class-heavy codebase. All three arms are now wired.
- **A short argument chain is not by itself a defect.** The METHOD paths
  materialise trailing defaults as real AN_ARG nodes (`FillDefaultArgs`), so a
  short chain there means garbage; the FREE-routine path leaves the chain short
  and lets **codegen** supply the defaults. Measured directly: an interface
  declaring `F(a; b=77; c=99)` called as `F(1)` from inside its own
  implementation returns the correct `17799`. Without accounting for this the
  probe reported every defaulted free call — `urlopen(url)` in
  `lib/rtl/mimic_urllib_request.pas:855` was the first false positive. The probe
  now consults `ProcParamHasDefault[]` for the first missing parameter (defaults
  are trailing in Pascal, so one flag settles the tail).

Validated in both directions: it fires on all four true positives (instance
function, instance procedure, virtual, class-virtual) and is silent on
correct-arity calls and on legitimate default-argument calls.

### Result: **zero hits. This is a fix, not a campaign.**

| corpus | coverage | hits | weight |
| --- | --- | --- | --- |
| `compiler/**` (206k lines) | full self-compile | **0** | **vacuous — see below** |
| `lib/rtl` | 110/110 units, 367 method impls | **0** | strong |
| `lib/pcl` | 22/23 units, 412 method impls | **0** | strong |
| `examples/**` | 38/41 programs | **0** | strong |
| `library_candidates/**` | 12/55 files produced a binary | **0** | **weak — 43 never compiled** |

**The `compiler/**` zero is vacuous and must not be quoted as "the compiler is
clean".** `compiler/**` declares **no classes and no methods at all** — it is
written in a purely procedural Pascal subset. (The two greps that appear to find
a class declaration and a method implementation both land *inside doc comments*:
`pasparser_decl.inc:4618`, `pasparser_call.inc:1432`.) A method-arity probe over
method-free source can only return zero. Nothing was learned about compiler
correctness here.

What it *does* settle, completely, is the risk that prompted the diagnostic-first
sequencing: **the arity fix cannot break the self-host fixedpoint**, because the
construct it restricts does not occur in the compiler's own source.

The `lib/**` zeros are the real ones — 779 method implementations across 132
units, which is where a live hit would have been. The detector found no existing
bug to file. So the promotion to an error carries no known blast radius, and
`lib/pcl` does not need Track B woken.

**Where the count is weak, stated plainly:** only 12 of 55 corpus files compiled
far enough to lower any IR (43 blocked on missing dependencies — `fpcunit`, and
softfloat internals such as `float_raise` / `TFPURoundingMode`). The corpus row
is close to no evidence, not evidence of absence. Also unmeasured: `lib/pcl/tk`
(fails standalone), 2 ESP mains (need a real build harness), 1 example whose
`klondike` unit does not exist anywhere in the tree, and any **generic** method
body that is never instantiated (uninstantiated generics are never lowered, so
the probe cannot see them).

**Why zero is nevertheless plausible rather than suspicious:** this defect
produces a garbage value, not a compile error. Any *working, exercised* code path
that hit it would be visibly wrong and would already have been fixed. The
population of live hits in code that currently works is expected to be near
zero. The bug's cost is borne by code not yet written, and by rarely-exercised
paths — which is an argument for the check, not against it.

### Where the real check belongs — NOT where the probe is

The probe sits in IR lowering because that was the cheap complete place to
*count*. It is the wrong place to *diagnose*: `ASTLine` is 0 for every node from
an appended unit, so a hit inside a unit reports `line 0` and cannot tell the
user where the call is. A user-facing error needs a parser position.

The hole is narrower than the ticket first implied. Too-few arguments *inside*
parens is already rejected (`Expect(tkComma)` / `ExpectCallRParen`). The only
unchecked shape is **no parentheses at all**: seven sites share the pattern

```pascal
if CurTok.Kind = tkLParen then
begin
  ...parse args...
end;          { <-- no else: the call node is returned holding only Self }
```

at `pasparser_call.inc:1359` (the one site that *does* have an `else`, for
defaults), `pasparser_expr.inc` ×2, `pasparser_lval.inc` ×4.

**The care this needs, and why it is not a one-line fix:** `obj.Method` with no
parentheses is *legitimately* not a call in a method-pointer context
(`p := obj.Method`). The check must fire only where a CALL was genuinely
intended, or it breaks the very construct
[[bug-p-a-class-method-cast-to-a-method-pointer-inline-segfaults]] depends on.
That interaction is the reason this ticket and that one are entangled, and it
must be tested in both directions before the error lands.

## Fixed (2026-08-28)

`CheckMethodCallArity` in `pasparser_call.inc` — **one** procedure holding the
call-or-reference decision, delegated to from the seven no-paren sites rather
than seven sites each deciding for themselves. The seven call sites are one line
apiece with no logic in them, so there is nothing at those sites to drift.

All four shapes from the table now report with a real source line and agree with
FPC; `rc=1`, no binary emitted:

```
pascal26:42: error: wrong number of parameters in call to TSvc.IPick
pascal26:43: error: wrong number of parameters in call to TSvc.IDo
pascal26:44: error: wrong number of parameters in call to TSvc.VDo
pascal26:45: error: wrong number of parameters in call to TSvc.CDo
```

It shares `ExpectCallRParen`'s wording deliberately: it is the same defect
reported from the other side, and two messages for one concept is how the two
paths drifted apart in the first place.

**A sibling defect I predicted and the measurement refuted.** Reading
`CanFillDefaultsFrom` (which requires `CurTok.Kind = tkRParen`, false when there
are no parens at all), I concluded the static class-method path would fail to
fill defaults for a parenless all-defaulted call — the unfixed sibling of
[[bug-p-a-parenless-call-to-an-all-defaulted-virtual-method-segfaults]]. It does
not: `TD.Baz` against `Baz(a: Integer = 7)` prints `Baz 7` and matches FPC, as do
the instance and virtual spellings. The defaults arrive by another route. The
reasoning was clean and wrong, which is the case `debugging-playbook.md` is
about; no scope was expanded on the strength of it.

### Both directions pinned in the suite, permanently

- `test/test_method_missing_args_report_fail.pas` — the deficit direction, all
  four call paths, asserted by line number with "no binary produced".
- `test/test_method_parenless_still_valid.{pas,expected}` — the must-NOT-break
  direction: method pointers, parameterless methods, and all-defaulted methods
  on the instance, virtual and class paths. Output verified against the FPC
  oracle, not just against ourselves.

The second file is the one that earns its keep: **a rejection test alone would
pass just as well if the check were far too strict**, and the method-pointer
shape it pins is the construct
[[bug-p-a-class-method-cast-to-a-method-pointer-inline-segfaults]] depends on —
the thing most at risk from this very change.

### Regression evidence

Re-ran the identical sweep with the check live and diffed against the
pre-change run: **compiles per section unchanged** (compiler 1, lib/rtl 110,
lib/pcl 22, examples 38) and **zero** new arity diagnostics anywhere. Nothing
that compiled before stopped compiling. `gate.sh quick` GREEN; self-host
fixedpoint verified.

### Still open, deliberately

The 8× duplicated method-call argument loop (`pasparser_call` ×1,
`pasparser_expr` ×2, `pasparser_lval` ×5, plus `pyparser` ×6) is untouched. That
duplication is the reason this defect could hide in seven places at once, and
collapsing it is a real Track P/A refactor — worth its own ticket, not worth
smuggling into a bug fix.

## Log
- 2026-08-28 — resolved, commit PENDING-COMMIT.
