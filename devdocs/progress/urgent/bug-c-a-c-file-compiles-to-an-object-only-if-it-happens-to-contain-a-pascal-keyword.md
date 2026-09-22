---
prio: 90
track: C
type: bug
status: new
found: 2026-09-22
found-by: frankh-c0
owner: ""
blocked-by: []
summary: "WHETHER A C TRANSLATION UNIT COMPILES TO AN OBJECT ON x86-64 AT HEAD DEPENDS ON WHETHER IT HAPPENS TO CONTAIN A WORD THAT IS A PASCAL KEYWORD. `int f(int x){return x+1;}` fails with `compiler error: call to a runtime stub that was never emitted (code offset 0 is the ELF entry point)` pointing into builtinheap.pas, a file the C author never wrote; adding `int string;` -- or a LOCAL variable named `string`, anywhere -- makes the identical file build. Not a coincidence: the C driver gates x86-64 AnsiString-shim emission at cparser.inc:13079 on `DetectPascalRuntimeNeeds`, a PASCAL token pre-scan, run over a C token stream, and `string` lexes as tkString_T through the shared lexer. So the gate answers by accident in BOTH directions and is not measuring anything about the C program. Affects --emit-obj and --shared; a C EXECUTABLE is unaffected. x86-64 only (i386/aarch64/arm32/riscv32 all build the failing file clean), because only there are the shims emitted machine code rather than direct calls into builtinheap. Regression: pinned v418 builds every shape, because before 523833fde the scan answered True unconditionally. Independent of --dce (--no-dce fails identically on the same binary). Breaks `make test-emit-obj`, which dies at test_shared_lib.c -- and the tier's C rows split exactly on this: the four that fail have ZERO #include, the one that passes has one, so the single passing C row was passing ACCIDENTALLY and the tier never had coverage of the real predicate. The Pascal driver enforces the matching invariant (23fcd326f); the C driver is the sibling arm of that same double case and does not. AND THE TIER HAD A DETECTOR THAT DOWNGRADED ITSELF TO A SKIP: tools/reloc_resolve_check.py's x86_64 row AGREES with GNU ld on 250686 bytes of .text and 1641 relocations under the pinned compiler, with 3 of 3 controls reddening it, and at HEAD reports `SKIP -- pxx cannot emit an object here`, so the strongest x86-64 C row in the tier left the run without reddening anything. Its skip is honest about what it could not do and wrong about why, which is the difference between an unsupported target and a broken compiler; the tier asserts the supported-target list two rows earlier, so the discriminator is available where the skip is taken. MECHANISM traced and controlled, CAUSE NOT BISECTED -- 523833fde is the suspect on three grounds but its parent was never built."
---

# Whether a C file builds to an object depends on whether it contains a Pascal keyword

## The headline, one pair

    $ cat a.c
    int f(int x){return x+1;}
    $ ./compiler/pascal26 --emit-obj a.c a.o
    pascal26:5980: error: compiler error: call to a runtime stub that was never
      emitted (code offset 0 is the ELF entry point). A frontend driver is
      missing its stub-emission call for the current flags/target.
      in: ./compiler/builtin/builtinheap.pas
      note: that unit is appended to every program by the compiler -- you did
            not write it.

    $ cat b.c
    int f(int x){int string = 0; return x + string;}
    $ ./compiler/pascal26 --emit-obj b.c b.o      # ok

A **local variable named `string`** is the whole difference. It is never read by
anything, it is not a type, and it changes whether the compiler can emit an
object at all.

## Measured — one batch, one compiler `3854783c605a`, no `-I`

| source | `--emit-obj` x86-64 |
| --- | --- |
| `int f(int x){return x+1;}` | **FAIL** |
| `int string;` + the same function | ok |
| a LOCAL named `string` inside the function | ok |
| `string` in a COMMENT only | **FAIL** |
| `string` inside a STRING LITERAL only | **FAIL** |
| `#include <stdio.h>` | ok |
| `#include <string.h>` | ok |
| `#include <stdlib.h>` | ok |
| `#include <sys/types.h>` | ok |
| `#include <stddef.h>` | **FAIL** |

Comment and string-literal rows are the control: they contain the word and do
**not** flip it, which is what makes this a TOKEN effect and not a text effect.

The header rows are reported as measured. **I did not pin which token each
header contributes** — `stdio.h` has zero whole-word `string` tokens and passes,
`stddef.h` has one (inside a comment) and fails, so it is some other Pascal
keyword in each. The identifier mechanism above is proven directly and does not
depend on the header rows.

## Mode and target

| | |
| --- | --- |
| `--emit-obj` | affected |
| `--shared` | affected |
| plain C executable | unaffected |
| x86-64 | affected |
| i386, aarch64, arm32, riscv32 | all build the failing file clean |
| pinned v418, every shape above | ok |
| `--no-dce` at HEAD | fails identically — independent of the pass |

Only x86-64 is affected because only there are the string shims emitted machine
code; the other backends' string IR ops call the `builtinheap` helpers directly,
so there is no emission step to skip.

## Mechanism

`cparser.inc:13079`:

    DetectPascalRuntimeNeeds(cNeedsHeap, cNeedsAnsi, cNeedsDiv);
    if cNeedsAnsi and (TargetArch = TARGET_X86_64) then
    begin
      RegisterEmittedStringRuntimeForwards;
      EmitAnsiStringRuntime;
    end;

Its comment states the design intent plainly: the gate is deliberately *"the
SAME pre-scan the Pascal driver uses rather than a C-specific guess, so a C
translation unit with no Pascal in it carries no shims."*

`DetectPascalRuntimeNeeds` (`pasparser_prog.inc:98`) walks `Tokens[]` and sets
`needsAnsiRuntime := True` on `Tokens[i].Kind = tkString_T`. The token stream it
walks for a C compile is the **C** one, classified by the shared lexer, in which
the identifier `string` — any case; the scan's own comment notes it catches both
spellings — is `tkString_T`.

So the gate is not under-detecting. **It is reading a Pascal-keyword
classification of C text, and answering by coincidence in both directions.** The
false-negative direction is the build break above. The false-POSITIVE direction
is the quieter half and is why nobody noticed: a C file that happens to contain
one of these words gets the shims and builds, for no reason connected to whether
it needs them.

Meanwhile `builtinheap` is pulled regardless, and its own body calls those
shims, so the call lands on address 0 — verbatim the failure `523833fde`'s
comment predicts:

> *"builtinheap's OWN BODY calls the string stubs, so emitting that unit without
> the AnsiString runtime leaves a call to address 0 inside code the compiler
> appended itself."*

The Pascal driver got that invariant enforced in `23fcd326f`. The C driver holds
the sibling gate and did not — `normalise-dont-special-case` at the spelling
level, which is the shape this repo's own rule says to grep for at fix time.

## Why the tier never caught it, which is the part worth keeping

`make test-emit-obj` dies at `test_shared_lib.c`. Its C rows split exactly on
`#include` count:

| tier fixture | `#include` | verdict |
| --- | --- | --- |
| `test/c_function_sections.c` | 1 | ok |
| `test/test_shared_lib.c` | 0 | FAIL |
| `test/c_obj_data_import.c` | 0 | FAIL |
| `test/c_obj_data_export.c` | 0 | FAIL |
| `test/c_obj_data_linkage.c` | 0 | FAIL |

**The one passing C row passes accidentally.** It is not a control for anything
here — it never had coverage of the predicate, because the predicate is not
about C.

## Not an argument to revert `523833fde`

Its 82.1% size win is real, its own comment predicted this failure class in
terms (*"a name missing from this scan is a BUILD BREAK, never a miscompile --
loud, attributable, and fixed by adding the name"*), and nothing miscompiles.
But note the repair this case wants is **not** "add the name": adding names to a
Pascal keyword list cannot make it a correct predicate for a C translation unit.
The C driver needs its own answer to *does this object's appended `builtinheap`
call the shims* — which, since builtinheap is pulled unconditionally, may simply
be *yes, always, on x86-64*.

## Two things NOT established

- **NOT BISECTED.** `523833fde` is the suspect on three grounds — pinned
  predates it and works, the error text matches its own predicted failure, and
  the C driver calls the routine it rewrote — but its parent was never built.
  Do not quote it as the cause on this ticket's say-so.
- **Why a plain C EXECUTABLE is unaffected.** Something on that path pulls the
  runtime for another reason. This decides whether the fix belongs in the gate
  or in the object path, so it is worth one command before fixing.

## Ownership

`frankb-8e` holds this topic — its routine, its invariant, its commit — and has
the repro and this correction. `owner:` left empty so the ranker does not read
it as claimed.

## How I got the quantifier wrong, which is the reusable part

**I filed this as "EVERY x86-64 C `--emit-obj` fails."** That word was wrong,
and it was wrong in the way CLAUDE.md names: *"the clause to go measure is the
QUANTIFIER, not the verb beside it."* The verb was sound — those files really do
fail, under a pinned control, with `--dce` excluded. The quantifier came from
three samples that **shared a property I had not varied**: none of them had an
`#include`. Every file I reached for while reducing was minimal, and minimal is
precisely the arrangement that omits headers.

What caught it was not re-reading. It was noticing that a tier row at relative
254 was also a C `--emit-obj` on x86-64 and sat *before* the failing one — the
tier's own ordering refuted my summary, from a file I had already looked at.

Two further self-inflicted costs, both recorded because they were cheap to avoid:

- **I inverted a row I had measured.** `#include <stddef.h>` answered FAIL in the
  batch where I then wrote that it passed, and I spent a header bisect on that
  inversion before re-reading the output. The bisect's uniform FAIL was the tell.
- **A grep for a name matched prose.** `grep -now string stddef.h` returned line
  15 and I read it as the trigger; it is inside a comment, and my own control row
  two probes earlier had already established that comments do not flip the gate.
  The rule fired on me while I held the counterexample.

## The regression HAD a detector, and the detector downgraded itself to SKIP

This is the most useful row in the ticket and it was found by accident, reading
the tier log for something else.

`tools/reloc_resolve_check.py x86_64 test/reloc_resolve_probe.c` is the tier's
strongest x86-64 C row. Under the **pinned** compiler it reports:

    reloc-resolve[x86_64]: AGREE with GNU ld on 250686 bytes of .text,
      1641 .text relocations (0 undefined, ld-only); 3 of 3 controls reddened it
      linked binary runs: rc=0 out='42 0x44fa30 0x44fa38 0x4445f8'

Under **HEAD** the same row reports:

    reloc-resolve[x86_64]: SKIP -- pxx cannot emit an object here

`test/reloc_resolve_probe.c` has zero `#include`, so it is squarely inside this
bug's population. The row did not fail. It concluded that x86-64 object emission
is **not a supported capability** and skipped itself — and the tier counts a SKIP
as not-a-failure, so a row carrying 1,641 verified relocations and a
three-control positive suite vanished from the run without reddening anything.

**The SKIP text is honest and its reason is wrong**, which is this file's
instrument rule exactly: the probe is correct that it could not emit an object,
and incorrect that the cause is a missing capability. That is the difference
between "this target cannot do this" and "this compiler just broke", and the
skip collapses them.

Worth fixing independently of the cause: a probe that cannot distinguish an
unsupported target from a broken compiler will mask the next one too. The tier
already knows which targets support object emission — `emit-obj-target-set`
asserts the list two rows earlier, x86-64 included — so the discriminator is
available at the point the skip is taken.
