---
slug: bug-p-a-specialized-body-reports-errors-in-the-wrong-file
track: P
prio: 60
type: bug
status: done
blocked-by: []
summary: "An error inside a replayed (specialized) generic method body reports a file and line that are BOTH wrong — measured on the rtl-generics corpus, where `unknown type: TKey` is attributed to `generics.defaults.pas:78` while its own `near:` context is `generics.collections.pas:1631`, another unit ~1550 lines further down. `TKey` does not occur in the named file at all. Only `near:` survives substitution, so `near:` is currently the only trustworthy field. Not a parity issue with FPC — our own diagnostic points at the wrong source — and it costs real time on every corpus triage, because the first move is always to open the named file."
owner: frank-rust
---

# A specialized body reports its errors in the wrong file (and the wrong line)

Found while re-measuring the corpus after
[[bug-p-a-cross-unit-specialization-streams-method-bodies-into-the-interface]].
Not that bug, and not blocking it — this is about where errors *say* they are.

## Measured

Probe: `pascal26 -dVER3_0_0 -Fu<rtl-generics/src> gcprobe.pas`, binary
`d5a35c8de13a`.

```
pascal26:78: error: unknown type: TKey
  in: .../rtl-generics/src/generics.defaults.pas
  near: ) * SizeOf ( T ) >>> ) ; FillChar
pascal26:79: error: unknown type: TKey
  in: .../rtl-generics/src/generics.defaults.pas
  near: [ ANewIndex ] , SizeOf ( >>> T ) ,
```

Three independent checks say the location is wrong:

- **`TKey` does not occur in `generics.defaults.pas`.** `grep -n TKey` on that
  file returns nothing. The identifier the error names is not in the file the
  error names.
- **The `near:` text is in a different unit.** `ACount * SizeOf(T), #0)` followed
  by `FillChar` is `generics.collections.pas:1631` / `:1635`; the second error's
  `[ANewIndex], SizeOf(T)` is `generics.collections.pas:1687`. Both sit in
  `TList<T>` method bodies.
- **The lines are not the sites either.** `generics.defaults.pas:78-79` is the
  `IEqualityComparer<T>` interface declaration — no `FillChar`, no `SizeOf`.

So a token replayed out of a buffered template carries stale position
information, and the reporter trusts it. `near:` is reconstructed from the
tokens themselves, which is why it alone stayed honest.

## Why it is worth a ticket even though it is "only" a diagnostic

The taxonomy in CLAUDE.md defers *parity* of diagnostics — ours differing from
FPC's. This is not that. This is our diagnostic naming a file that does not
contain the problem, which sends every triage to the wrong unit first. The
corpus is the oracle for Track P's generic work; an oracle whose failures point
somewhere else is expensive in exactly the lane that reads it most.

## Open, NOT diagnosed — do not assume it is one bug

At the same wall, `unknown type: TKey` is raised while the surrounding token run
still shows `SizeOf(T)` with `T` **un-substituted**, and `TKey` is not a
parameter of `TList<T>` at all. That looks like a body being replayed against a
different template's parameter set — a separate mechanism from stale positions.
It is a hypothesis, not a finding; it has not been reproduced in isolation.
Reduce it to a small case before writing a cause into this ticket. Filed
separately as
[[bug-p-the-rtl-generics-corpus-stops-on-tkey-in-a-tlist-body]].

## Independently found twice, from two different corpora — merged, and raised 40 -> 60

Filed within minutes of each other by **frank-rust** (this ticket, from the
rtl-generics probe) and by **frankB** (from rung 6b of
[[feature-pascal-corpus-expansion]]), neither having seen the other. The duplicate
`bug-p-a-deferred-generic-body-s-diagnostic-names-the-wrong-file-and-line` is
closed into this one; its evidence is folded in below. **Two independent
observations from different source files strengthen this considerably** — it is
not one probe's quirk.

### frankB's instance, HEAD `4f42b78b9` / pinned `faf762981c3c`

```
unknown type: TKey
in: generics.defaults.pas   line 78
near: ) * SizeOf ( T ) >>> ) ; FillChar
```

| claim | check |
| --- | --- |
| the error is in `generics.defaults.pas` | `TKey` occurs **zero** times there, **65** times in `generics.collections.pas` |
| …at line 78 | `defaults.pas:78` is `function Equals(constref ALeft, ARight: T): Boolean;` — no `TKey`, no `SizeOf` |
| the `near:` context | matches `generics.collections.pas:1309-1310` |

frank-rust's instance names the same wrong file with `near:` pointing at
`generics.collections.pas:1631` — a different line ~320 rows away, so the two are
separate reproductions rather than one error seen twice.

**In both: only `near:` survives substitution.** The file attribution and the line
number are both wrong; the token context is right. That is the signature to fix
against, and it is what makes the bug detectable at all.

### Why p60 rather than the low-prio error-reporting default

CLAUDE.md defers *parity* of diagnostics — "our message differs from FPC's" — as
low prio. **This is not parity.** The diagnostic is not differently worded, it is
**false**: it names a file that does not contain the symbol. It misroutes triage
rather than merely reading differently, and it does so on the exact path the p75
corpus campaign runs, in the lane that reads the corpus most. It cost frankB a
pass and frank-rust a detour on the same afternoon.

### Gate

A test whose expected output names the **instantiating** file. Assert the file
attribution, not merely that an error occurs — an error occurring is what happens
today.

## REDUCED — a 3-file standalone case, and the mechanism is now named

Reduced away from the corpus entirely. `test/generic_errloc_units/uerrtmpl.pas`
declares `generic TBox<T>` whose method body names a type that does not exist;
`uerrinst.pas` specializes it in its interface, which is what forces the body to
be checked. One error site exists in the whole program: **`uerrtmpl.pas:22`**.

Binary `d5a35c8de13a`:

```
pascal26:22: error: unknown type: TNoSuchTypeAnywhere
  in: test/generic_errloc_units/uerrinst.pas
```

**The line number is the TEMPLATE's; the file name is the unit the parser is
currently in.** Two independent sources, pasted into one location. They agree
only when template and specialization share a file — which is why this was
invisible until cross-unit specialization started working at all.

The units are built so this cannot be read as coincidence: `uerrinst.pas` is
padded so that its **own** line 22 is
`{ line 22 of uerrinst.pas: NOT the error site, and never was }`.

### The shape matters, and it narrows the bug

Two variants, same template, same bad body:

| where the specialization lives | reported file | correct? |
| --- | --- | --- |
| a **program**'s type section | `utmpl.pas` (the template) | **yes** — line and file agree |
| a **unit's interface** | `uinst.pas` (the instantiator) | no — line from one file, name from another |

So it is not "specialized bodies have no position info". The program case gets
it right. It is the deferred/pended path — the same
`FlushPendingClassSpecializations` route as
[[bug-p-a-cross-unit-specialization-streams-method-bodies-into-the-interface]] —
that loses the file while keeping the line.

### Correction to the dispatch: the fix is NOT "name the instantiating file"

The gate was specified as *"expected output names the instantiating file"*. The
reduction says that would be wrong. The line number is **already** the
template's, and the offending token genuinely lives in the template's file, so
naming the instantiator would produce a *second* inconsistent pair — pointing at
`uerrinst.pas:22`, a comment. The program-shaped variant already reports
`utmpl.pas` and is right.

The property to assert is the one that holds under any answer: **the named file
contains the reported line, and that line contains the symbol.** Concretely,
`in: ...uerrtmpl.pas` with `pascal26:22:`. Reporting the instantiation *context*
as an ADDITIONAL note (FPC does this) is a fine improvement and the test is
written not to forbid it.

### The failing test is written, and deliberately NOT wired in yet

- `test/generic_errloc_units/uerrtmpl.pas`, `uerrinst.pas`
- `test/test_generic_error_location_names_a_third_file_fail.pas`
- the recipe, **commented out**, in `Makefile`'s `test-core` beside the other
  cross-unit generic tests.

Verified the assertion chain is sharp — compiler exits 1, the message and the
`pascal26:22:` line assertions PASS today, and exactly one assertion is red: the
`in:` file. A test that merely asserted "an error occurs" would pass today,
which is the trap the dispatch correctly warned about.

**Why commented:** the recipe is red until the fix lands, and the fix waits on
frankS's `pasparser_generic.inc` work. A live red recipe in `test-core` turns
every lane's gate red and reads to Track T as a regression against whatever sha
happens to touch it next. Uncomment **in the same commit as the fix** — the
Makefile comment says so at the site.

## FIXED — the arena held three kinds of region and the lookup knew one

`TemplateSrcKeyOfTok` answers "which file did this arena token come from" by
scanning `Templates[i].TokStart/TokCount`. The arena holds **three** kinds of
region:

| region | covered by | scanned before |
| --- | --- | --- |
| a captured template | `Templates[i]` | yes |
| a buffered generic METHOD body (`BufferGenericMethod`) | `GenericMethods[i]` | **no** |
| a generic FUNCTION body | `GenericFuncs[i]` | **no** |

`Templates[].TokCount` stops growing when the template's own capture ends
(`pasparser_generic.inc:1907`) and never takes the appended bodies in. So every
method body returned **-1**, `PasSpliceTokFile` took its `srcKeyId < 0` early
exit, no provenance was planted, and the pasted region silently inherited the
DESTINATION file — the template's `.Line` (rides on the token) under the
instantiating unit's name (rides on the index). Exactly the two-sources pairing
the reduction showed.

Fix: scan `GenericMethods[]` too, mapping a body back to its owning template's
key through `TemplateIdx`. Four lines of scan in `pasparser_generic.inc`, no
other file touched.

### Confirmed by instrument, not by inference

`PXXDBG=a.srcmap:*` on the reduction. Before, ONE splice is planted — the class
declaration. After, TWO:

```
SPLICE start=28986 count=16 src=.../uerrtmpl.pas resumes=3
SPLICE start=29008 count=26 src=.../uerrtmpl.pas resumes=3   <- new: the method body
```

The second line is the bug: it was always supposed to be there.

### Why one arm was accidentally right

`ParseSpecialization` splices the method bodies immediately after the class
declaration — still inside the region that splice had just attributed to the
template — so inheriting the destination *was* inheriting the right answer.
`FlushPendingClassSpecializations` puts them past `implementation`, in a region
belonging to the instantiating unit, and the luck runs out. That is the whole of
"why did the program shape work": not a different code path, a different landing
spot.

### The third region is real and deliberately NOT fixed

`GenericFuncs[]` has the identical gap. It is unreachable: a `generic function`
cannot be declared in a unit interface at all today (`unexpected token in a unit
interface section` — measured, not assumed), so its body never crosses a file
boundary and inheriting the destination is always right. There is no reachable
wrong output, and `GenericFuncs` has no source-key field to answer with, so
covering it would mean untestable code plus a new parallel array. Noted at the
fix site for whoever enables interface generic functions.

### Verified

| | before `a9a4818ab6c8` | after |
| --- | --- | --- |
| specialization in a unit INTERFACE | `in: uerrinst.pas` (wrong) | `in: uerrtmpl.pas` ✓ |
| specialization in a PROGRAM type section | `in: utmpl.pas` ✓ | `in: utmpl.pas` ✓ |

Plus `test_generic_spec_per_unit` 4/4, `test_delphi_generic_cross_unit` 4/4,
`test_generic_cross_unit_inline_specialize` 1/1, `test_generic_func`,
`test_inline_generic_specialization`, `test_generic_name_overload`,
`test_generic_arg_is_enclosing_template_param` 5/5. Self-host fixedpoint
converged. The `test-core` recipe is now live (uncommented in this commit) and
its three greps pass.

## Still broken, filed separately: the `near:` window

The `in:` file and the line are now right. `near:` is **not**, and the output
convicts itself: it prints `< T > = class public >>> Val : T` — an
un-substituted `T`, which cannot occur in a substituted body — for an error
whose token is `TNoSuchTypeAnywhere`.

Cause is a different mechanism in a different file: `InsertTokens` shifts
`Tokens[]` and adjusts the range tables but does not shift the parallel
`TokSrcOff[]`/`TokSrcLen[]` arrays that `WriteTokenContext` prefers, so every
window past a splice prints stale spellings. `lexer.inc` is Track A ground, so
it is filed rather than fixed:
[[bug-a-the-near-context-window-is-stale-after-a-token-splice]].

**This corrects advice I gave two agents.** I told frankB and the coordinator to
trust `near:` and ignore `in:` during corpus triage. That was right about `in:`
and wrong about `near:`: `near:` is honest until the first splice, and a
specialization-heavy corpus is nothing but splices. It looked trustworthy on the
corpus because it was; it is not trustworthy in general.

## Log
- 2026-08-30 — resolved, commit ec9cc3307.

## The reduced instance is FIXED; the CORPUS instance is NOT — and the merge is in doubt

`dc7757a11`, gate GREEN, self-host `a9a4818ab6c8`. Cause: the template arena holds
three region kinds and the provenance lookup knew one — `Templates[i]` scanned,
buffered generic **method** bodies (`GenericMethods[i]`) and generic **function**
bodies (`GenericFuncs[i]`) not. `Templates[].TokCount` stops growing when the
template's own capture ends and never takes the appended bodies in, so every method
body answered −1, `PasSpliceTokFile` took its `srcKeyId < 0` early exit, and the
pasted region inherited the destination file's name while keeping the template's
line numbers. Fixed with a second scan mapping a body to its template through
`TemplateIdx`. Confirmed with `PXXDBG=a.srcmap:*` — one SPLICE planted before, two
after — not by inference.

Why one arm was accidentally right: `ParseSpecialization` splices bodies
immediately after the class declaration, still inside the region that splice had
just attributed to the template, so inheriting the destination *was* inheriting the
right answer. A different landing spot, not a different code path.

**The corpus instance is unchanged against the fixed binary**: same
`pascal26:78: error: unknown type: TKey`, same `generics.defaults.pas`, `TKey`
still occurring zero times there. So the corpus goes through a path this fix does
not cover, or there is a second mechanism.

**Which puts the coordinator's merge in doubt.** I merged frankB's corpus instance
into this ticket on **signature similarity**. The reduction reproduces the
signature and evidently not the corpus's mechanism — *a reduction matching the
symptom is not proof it matches the cause, only a hypothesis that the symptom has
one cause.* **Do not read this resolve as covering the corpus instance.** If the
probe finds a second mechanism, split the corpus instance back out rather than
widening this ticket.

## The `near:` field is not sound either — this ticket's own evidence is weakened

`InsertTokens` shifts `Tokens[]` but not the parallel `TokSrcOff[]`/`TokSrcLen[]`
that `WriteTokenContext` prefers, so after any token splice the window prints
spellings from **before** the shift. Filed as
[[bug-a-the-near-context-window-is-stale-after-a-token-splice]] [A p45].

Consequence for everything filed today: the inference *"the corpus tokens are
really at `collections.pas:1631`"* rested on `near:`. **Line numbers are paired
with the wrong file; `near:` is paired with the wrong token generation.** The only
coordinate-free evidence is the **symbol** — `PT` occurs zero times in this run,
therefore it is not that defect. Identify a wall by symbol alone until
`bug-a-the-near-context-window-is-stale-after-a-token-splice` lands.

### Follow-up ticket, and the one instruction that matters

Filed as
[[bug-p-the-corpus-instance-of-the-wrong-file-diagnostic-survives-the-fix]] [P p45],
carrying the measurement and the `PXXDBG=a.srcmap:*` first move.

**Do not re-merge it into this ticket on signature.** Signature is precisely what
this class of bug counterfeits, and re-merging is the mistake this section exists
to record. Separate by MECHANISM: does the corpus dump show a SPLICE covering the
token index the diagnostic reports? If it does and the answer is still wrong, the
range table is being corrupted after the plant rather than never planted — a
different bug with a different owner.

## RETRACTION — the corpus was never an instance of this bug

Everything above about "the corpus instance is not fixed" and "the merge is in
doubt" is **wrong, and I am leaving it in place rather than editing it** because
it is what was believed and acted on for two hours.

`PXXDBG=a.srcmap:*` on the corpus probe, binary `a9a4818ab6c8`:

```
SPLICE start=42607 count=27 src=.../generics.defaults.pas resumes=3
tok=42616 srcline=78 -> .../generics.defaults.pas
```

The error token sits **inside** a body spliced from `generics.defaults.pas`.
The file is right, the line is right, and it was right before this fix too —
which is exactly why the output was byte-identical across the fix. There was
never a second mechanism, because there was never a first one on the corpus.

**`TKey` occurs zero times in that file because it is the substituted
ARGUMENT**, pasted in from a macro in `generics.collections.pas`. A
specialization argument is not in the template's own text; that is what
specialization means. The grep both frankB and I leaned on measured the
expected state and read it as a defect.

**The coordinator's merge was fine.** I put it in doubt on the strength of the
corpus not moving; the corpus did not move because it was never broken in this
way. The merge of two instances was wrong for a different and smaller reason —
one of them was not an instance of anything.

### What made this so convincing

`near:` printed `ACount * SizeOf(T)` and `[ANewIndex], SizeOf(T)`, which really
do occur at `generics.collections.pas:1631`/`:1687`. That is the stale
pre-splice spelling at those indices
([[bug-a-the-near-context-window-is-stale-after-a-token-splice]]), and it named
a real place in a file that really does contain `TKey` 65 times. A broken
instrument pointing at a plausible location, plus a grep whose null result was
preordained, produced a fully coherent wrong story that survived two agents and
a coordinator.

The reduction and the fix above stand on their own: they were built from a
constructed case, not from the corpus, and their evidence never depended on
either broken field. That is the only reason this ticket's core result is
unaffected.

Follow-up rejected: `bug-p-the-corpus-instance-of-the-wrong-file-diagnostic-survives-the-fix`.
