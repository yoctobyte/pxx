---
slug: feature-a-the-threadvar-area-is-3072-bytes-of-bss-in-every-program-that-has-no-threadvar
title: "The threadvar area is 3,072 bytes of bss in every program that declares no threadvar — and it is an x86-64-only cost, ZERO on ESP"
type: feature
track: A
prio: 45
status: working
created: 2026-09-18
owner: frankb-8e
summary: "THE NILPY ARM WAS RETIRED THE SAME DAY IT SHIPPED AND THIS SUMMARY ADVERTISED IT AS LIVE FOR THREE DAYS -- corrected 2026-09-22 (frankb-8e) after MEASURING it, not reading it. Re-measured at HEAD: a NilPy hello is bss 62,740 by default and 59,668 under -dPXX_TLS_USER_0, i.e. it still carries the full 3,072 and the flag is the only way to get it back. The retirement is correct and is recorded in ir_codegen.inc's own words: 402d61e0d made the AREAFULL reason a hard ERROR and c5ae069c5 made errno `__thread`, so EVERY C unit now declares a thread-local, and a NilPy program reaches C units through -Fu -- every mixed NilPy+C build refused at HEAD. Letting the C arm degrade instead would hand a NilPy program ONE errno shared across every thread, which is the race c5ae069c5 removed, so the 3,072 bytes are the price (~0.2% of a NilPy program's ~1.35 MB code segment). ONLY ONE ARM IS LIVE AND IT IS `IsPascalFrontend`; there is no NilPy condition in the routine at all. ROUTES C AND A SHIPPED AND ARE UNAFFECTED. A Pascal program naming neither `threadvar` nor `uses` gets a ZERO-byte threadvar area automatically -- hello.pas bss 38,396 -> 35,324 at the time, and 34,600 at HEAD now that bug-a-a-pascal-hello-world-is-63kb has landed -- with __pxxTlsBlockSize 1152 instead of 4224. On top of that -dPXX_TLS_USER_0/_1K/_2K/_4K/_8K/_16K sets it explicitly and always wins. THE PASCAL SCAN READS THE SOURCE TEXT, NOT TOKENS, and that is forced: the token array is EMPTY at the only moment the size may be chosen, and the call cannot move down because EmitTlsMainInstall bakes the size into the BSS reservation and the fold captures it. Source is include-expanded by then, which is why the text scan is Pascal-only. THE ARGUMENT THAT ONCE JUSTIFIED THE NILPY ARM IS PRESERVED BELOW AS HISTORY AND IS NOT THE STATE -- it reasoned only about a threadvar in a PASCAL unit a NilPy program imports (which does error loudly at 0 bytes, naming the unit, the line and the flag), and it never considered a C unit, which is what retired it. The C exclusion's old wording said the C allocator arm WARNS rather than errors; that was true when written and 402d61e0d made it a hard error. Guards: test_tlsnone26 (Pascal, asserts block=1152 -- the arm that IS live) and test_tlsnonenp26 (NilPy, asserts block=4224, i.e. that the area is still PAID). The NilPy fixture was named `test_a_nilpy_program_pays_no_threadvar_area.npy` while asserting the opposite, and was renamed to `..._pays_the_full_threadvar_area.npy` on 2026-09-22 with its header rewritten: whoever retired the arm updated the assertion correctly and left the name and header behind, so a grep for the old sentence found a test proving its negation. Its stated positive control -- \"the pinned compiler answers 4224\" -- was also removed rather than reworded, because it discriminated only while HEAD answered 1152; both answer 4224 now, so that agreement is two compilers doing the same correct thing and not evidence. The `uses` rule stays on the Pascal side because dropping it would REFUSE a program that compiles today, capping that arm's reach at unit-free programs, 11 of 49 under examples/. ROUTE B IS PRICED NOW AND IS NOT BLOCKED -- IT IS UNDERSTOOD AND DECLINED, 2026-09-22, and this summary said 'still the only unsound route' as if a mechanism were missing. Worth 3,072 B to 25 of 28 host example programs that build (mean 2.86% of bss, ceiling 3.32%, and 36 of 36 compile at -dPXX_TLS_USER_0 because there are ZERO threadvar declarations in examples/ or lib/). Costs: defer the BSS_TLS_MAIN offset past parsing, patch two prologue displacements, stop one builtin folding early -- ONE backend, since threadvar refuses off x86-64, and the clone stub's four reads are already late for free. The blocker section in the body overstated this: the fold is one obstacle of four and PatchProcPrologue, not Patch32, is the precedent for a patched NUMBER. Declined because the failure mode is silent gs-relative corruption in the entry prologue every program runs through, for ~3% of bss. AND THE ESP HALF OF THIS TICKET IS WORTH NOTHING AND ALWAYS WAS: TryAssignThreadVarStorage refuses FIRST on TargetArch <> TARGET_X86_64, and the area is not reserved off x86-64 either -- measured delta ZERO on i386, arm32, aarch64, riscv32/esp32c3 and wasm32 against 3,072 on x86_64, with a subject carrying a `uses` so route A had not already removed it. So any blocked-by edge wiring this to an ESP size umbrella transmits an effective p70 for a benefit that does not exist there; RE-JUSTIFY ON THE HOSTED CASE OR CUT THE EDGE. What would revive route B: a threadvar landing in lib/rtl, at which point route A's `uses` term forces the full area on every program that touches a unit. STILL OPEN: the long-tail frontends, one `or Is<X>Frontend` term each, unrequested and unscheduled. Found on the way and fixed separately: bug-a-a-threadvar-in-a-units-implementation-section-silently-reads-zero, which was really the -O2 inliner retaining a threadvar read as a plain global."
verified: 2026-09-22
---

# Why it is a fixed cap, in the code's own words

`EmitTlsMainInstall` emits the program's entry prologue at code offset 0 and is
called from `compiler.pas:2330` — **before any frontend parses anything** — so it
reserves the block and bakes the size into emitted immediates before a single
`threadvar` has been seen. `defs.inc` says so and calls growing it out of scope
for the first rung. That is still true; what follows is about getting the 3,072
back for programs that never needed it.

# ROUTE C SHIPPED 2026-09-18 — the size is a command-line knob

`-dPXX_TLS_USER_0 / _1K / _2K / _4K / _8K / _16K`; default unchanged at 3072.
**`-dPXX_TLS_USER_0` gives the whole 3,072 back to any program that declares no
`threadvar`, which is most of them, and it needs no detection at all.**

It is sound for the reason the measurement below established and nothing more:
the fold and the reserve capture the size at a moment, and a capture is safe
exactly while the value cannot move afterwards. argv is read before any of it,
so a `-d` cannot violate that; **what is forbidden is a size that VARIES DURING
a compile, not a size that differs BETWEEN compiles.** Route B is the one that
breaks it, and it is still the only one that does.

Measured on an x86-64 `hello`, bss at each rung — exactly the area's own
difference every time:

| | 0 | 1K | 2K | **3072** | 4K | 8K | 16K |
| --- | --- | --- | --- | --- | --- | --- | --- |
| bss | 35,324 | 36,348 | 37,372 | **38,396** | 39,420 | 43,516 | 51,708 |
| `__pxxTlsBlockSize` | 1152 | 2176 | 3200 | **4224** | 5248 | 9344 | 17536 |

`test_atomic_counter` prints `ATOMIC OK` at 0, 1K, default, 8K and 16K;
`test_a_threadvar_is_per_thread` is correct at default, 1K and 16K; the
relation-asserting `test_the_tls_carve_constants_are_readable_from_the_rtl`
passes at default and at 8K without editing — palthread reads the real size
through `__pxxTlsBlockSize` and follows the knob.

Quantised to powers of two for the same reason the ESP heap arena is: a define
carries no value usable in an expression, so an arbitrary byte count would mean
a new option and a parser change, and a per-thread variable area is not tuned to
the byte.

Fixture `test_the_threadvar_area_is_a_command_line_knob.pas`, both directions:
385 Int64 threadvars = 3080 bytes, **refused** at the default and **accepted**
at `-dPXX_TLS_USER_4K`, with the LAST-declared name — the one past the default
cap — read back, so a knob that moved the diagnostic without moving the storage
reddens.

**Routes A and B are NOT closed by this and should be read as what they now
are:** route A buys the same 3,072 without the user asking, on the 22% of
`examples/` with no top-level `uses`; route B buys it on every program and still
needs the fold fixed first. Route C is the cheap floor under both.

# ROUTE A SHIPPED 2026-09-19 — no flag needed, and the floor subject is covered

A Pascal program whose source names neither `threadvar` nor `uses` is given a
**zero-byte** area automatically. `hello.pas` — the hosted umbrella's floor
subject — goes **bss 38,396 -> 35,324** with no flag, and `__pxxTlsBlockSize`
becomes 1152, the slot map alone. The size canary records the same -3,072 on
`x86_64-empty`.

**MY OWN RESUME NOTE WAS WRONG ABOUT THE CENTRAL FACT AND THIS IS THE
CORRECTION.** It said to scan in `DetectPascalRuntimeNeeds` and that "route C
built the ordering route A needed; there is no plumbing left to do". The
ordering is right and the instrument was not: **the token array is EMPTY at the
only moment the size may be chosen.** `compiler.pas` clears `TokCount` well
above `ApplyTlsUserBytesOption`, and every frontend lexes inside its own branch
BELOW it; `DetectPascalRuntimeNeeds` runs later still, inside `ParseProgram`.
Nor can the call move down — `EmitTlsMainInstall` bakes `TlsBlockSize` into the
BSS reservation and two immediates, and the fold captures it.

So the scan reads `Source`, which by that point is the main file **with its
includes already expanded** (`ExpandIncludes` then `ExpandPasMacros`, both under
`IsPascalFrontend` — which is why the feature is Pascal-only and that is a
consequence, not caution: a C program's `#include`s are expanded later, so a
`__thread` in a header would be invisible, and NilPy resolves imports later
still).

**Every way the scan can be wrong costs bytes, not correctness**, and that is
the design rather than a hope: the word in a comment or a string reserves an
area that would have been reserved anyway. Demonstrated by accident and kept as
the cheapest illustration anyone will find — the first draft of
`test_a_unit_free_program_pays_no_threadvar_area.pas` explained itself using
both keywords, tripped its own scan, and printed 4224. **The test asserting the
feature had disabled the feature.** The file now says so at the top.

## Why the `uses` rule stays, and what it costs

Kept, and the reason is sharper than "conservatism": **dropping it would refuse
a program that compiles today.** A `threadvar` in a used unit is not in the main
source's text, so without the rule such a program meets the cap and is refused
until someone passes a flag. Trading an acceptance regression for bytes is not
an optimisation. It caps the reach at unit-free programs — 11 of 49 Pascal files
under `examples/`, counted 2026-09-18 and **not re-counted**; `hello.pas`
qualifies, which is the case the umbrella cares about.

**The rule currently defends a hypothetical, and that is worth knowing rather
than acting on: NO unit under `lib/` or `compiler/builtin/` declares a
threadvar** (counted 2026-09-19 — `sockets.pas` says in its own words that there
is none in this dialect, and the three files a naive grep returns are all
PROSE). That matters because a `uses`-free program still pulls builtinheap
ambiently, so the prescan depends on it. It is GUARDED, not merely noted:
`test_a_unit_free_program_pays_no_threadvar_area` asserts `block=1152`, and the
first ambient-unit threadvar turns it red with the cap's own diagnostic.

## Found on the way, and filed rather than chased

`bug-a-a-threadvar-in-a-units-implementation-section-silently-reads-zero` (p55).
A `threadvar` in a unit's IMPLEMENTATION section is allocated storage but never
rewritten, so it reads 0 with no diagnostic; in the INTERFACE it works. It
reproduces on the pinned compiler and is independent of everything here — the
program that exposes it has a `uses` and therefore gets the full default area
under every setting.

## THE NILPY ARM SHIPPED 2026-09-19, AND THE BLOCKER I RECORDED DOES NOT EXIST

> **RETIRED THE SAME DAY IT SHIPPED. HISTORY FROM HERE TO THE END OF THIS
> SECTION — DO NOT READ IT AS STATE** (frankb-8e, 2026-09-22, measured). There
> is no NilPy condition in `ApplyTlsUserBytesOption` at HEAD; a NilPy hello
> still carries the full 3,072. The sentence below saying `test_tlsnonenp26`
> "asserts `block=1152`" is the one a reader is most likely to land on by
> grepping the fixture name, and it is **inverted**: that row asserts
> `block=4224`, and the fixture was renamed on 2026-09-22 because its NAME also
> claimed the opposite of its assertion. Its "pinned compiler answers 4224"
> positive control no longer discriminates — HEAD answers 4224 too. What
> retired the arm is in the dated `2026-09-22` section at the end of this file
> (cited by DATE, not by heading, because I first wrote a heading here that
> does not exist — the same phantom-name class this ticket is being corrected
> for): `errno`
> became `__thread`, so every C unit declares one, and a NilPy program reaches
> C units through `-Fu`. The reasoning preserved here only ever considered a
> threadvar in a PASCAL unit, which is why it did not see it coming.

The section below said this arm was gated on `defs.inc`'s `PyImportLang`
caveat -- `isNilPy` is true for the WHOLE compilation including the Pascal RTL
units a NilPy program drags in, so "the frontend has no such keyword" is not
"this compilation cannot declare one". **The caveat is real and it is not a
blocker, and the reason is one measurement nobody had taken.**

What I was afraid of was a SILENT collision of per-thread state. It is not
silent. A threadvar in a unit a NilPy program imports reaches the PASCAL
allocator, which **errors**:

```
$ pascal26 -dPXX_TLS_USER_0 np.npy o
pascal26:3: error: threadvar counter: the per-thread variable area is full (0 bytes)...
  in: tvnp.pas
  near: ; interface threadvar counter : LongInt >>> ; function Bump
(exit 1)
```

It names the unit, the line, and the flag that fixes it. So the worst case on
this arm is an **acceptance regression that announces itself with its own
remedy** -- the same class as the Pascal `uses` rule, and today over a population
of ZERO, since no unit under `lib/` or `compiler/builtin/` declares one.
`test_tlsnonenp26` is the guard: a NilPy fixture that imports a real Pascal unit
ON PURPOSE, to put one on the chain, and asserts `block=1152`. The day an
ambient unit declares a threadvar it fails to BUILD with the diagnostic above,
rather than shipping a wrong size.

Measured: a NilPy hello goes bss 62,724 -> 59,652, a flat -3,072, and
`__pxxTlsBlockSize` 4224 -> 1152. The pinned compiler answers 4224 for the same
fixture, which is the positive control.

**C IS EXCLUDED, and not out of caution.** Three things, the third deciding:
C has `__thread`; its `#include`s are expanded AFTER the size is chosen, so no
text scan here could see a header's declaration; and -- measured the same hour
-- the C arm of `TryAssignThreadVarStorage` **warns** where Pascal errors:

```
pascal26:2: warning: __thread counter: the per-thread variable area is full (0 bytes)...
  -- this declaration therefore gets ONE copy shared by every thread, not one
  per thread ... threaded code will read and write another thread's value with
  no further warning
```

and the program compiles, links and runs. A hard refusal naming a flag is a
fine failure mode; a warning that silently converts a thread-local into a shared
global is not. **C keeps the full 3,072 bytes and that is the right answer, not
a gap.** Changing it means giving C's arm the Pascal arm's refusal, which is a
separate decision about a frontend I do not own.

## WHAT IS LEFT (frankS parked it 2026-09-19; nobody holds it)

The ticket stays OPEN on two remaining pieces, in value order:

1. **The other frontends. CORRECTED 2026-09-22 — this item said "NilPy
   SHIPPED", and by the time it was written the arm had already been reverted.**
   NilPy is back on this list, not off it, and it is the one row here with a
   KNOWN reason it is hard rather than merely unrequested: a NilPy program
   reaches C units through `-Fu` and every C unit now declares a `__thread`
   errno, so the zero-byte area refuses the whole mixed build. Do not re-add it
   without answering that. C is excluded for a measured reason and is not
   coming back without a decision about its allocator arm.
   The LONG TAIL is BASIC, Rust, Zig, Erlang, Ada, Algol, Fortran, Lol, Ws --
   each a flat -3,072 and each worth exactly one `or Is<X>Frontend` term once
   someone confirms that frontend's ambient chain refuses loudly. **BASIC is
   the one actually worth doing and it has its own section below**, with the
   three prerequisites in order; the rest are unrequested and unscheduled.
   The original text follows.

   The other frontends. NilPy, BASIC, Rust, Zig, Erlang, Ada, Algol,
   Fortran and the rest cannot declare a thread-local at all — only Pascal
   (`threadvar`) and C (`__thread`) reach `TryAssignThreadVarStorage`, which is a
   two-file census, not a guess. Each of them is a flat **-3,072** (measured: a
   NilPy hello 62,724 -> 59,652; a C hello 72,448 -> 69,376 at rung 0). The
   catch is the one `defs.inc` spells out at `PyImportLang`: **`isNilPy` is true
   for the WHOLE compilation, including the nested `uses` of every Pascal RTL
   unit a NilPy program drags in** — so "the frontend has no such keyword" is
   NOT the same claim as "this compilation cannot declare one", and the same
   ambient-unit argument as above has to carry it.
2. **Route B** remains the only unsound one and its blocker is unchanged.

# Two routes, and they are not equal

**A — conservative prescan, safe in every direction, worth less.** Scan the
token array for an identifier `threadvar` before `EmitTlsMainInstall`, the way
`DetectPascalRuntimeNeeds` already scans for `tkUses`/`tkArray`/`tkClass`. Absent
→ the user area is 0. **`uses` must also force the area back on**, because a used
unit's `threadvar` is not in the main source's tokens; that is the same opacity
rule the existing prescan uses. Non-Pascal frontends have no `threadvar` at all
and can always take 0.

So it wins on unit-free programs — which is exactly the hosted umbrella's floor
subject, and nothing else. **Counted 2026-09-18: 11 of 49 Pascal files under
`examples/` have no top-level `uses`, so route A reaches 22% of them.** That is
the honest ceiling on this route; decide against it rather than discovering it.

**B — exact, worth the full 3,072 on every program, and it hinges on ONE fact
nobody has established.** Reserve the area from what parsing actually used
(`TlsUserUsed`) and patch the handful of size immediates afterwards — the
compiler already patches code with `Patch32`, and the clone stub is emitted
lazily (`CloneStubAddr := 0`) so it may not need patching at all.

## Read this before you delete the reserve, and before you believe it is a guard

Two readings were put to this ticket and **both are half right; the measurement
separates them.**

- *"There is no live corruption today."* **TRUE, measured.** The reserve is a
  CAP and overflow is REFUSED. 400 scalar `Int64` threadvars in a program that
  `uses palthread`: `v384` — the first byte past 3072 — is refused with the
  diagnostic and the program never reaches runtime. Rebuilt with
  `TLS_USER_BYTES = 0`, the same refusal fires on the first threadvar in
  `test_a_threadvar_is_per_thread.pas`. There is no arrangement in which a
  program outgrows the block the fold captured.
- *"So the 3,072 IS the guard that makes the fold sound — the reserve and the
  fold are one mechanism and you cannot touch either alone."* **FALSE, and this
  is the reframe to resist**, because it would park a real 8% of the hosted
  floor behind a safety property it does not actually carry. The fold is sound
  because `TLS_BLOCK_SIZE` is a compile-time **CONSTANT**, not because it is
  3072. **Measured: rebuilt with `TLS_USER_BYTES = 0`, `test_atomic_counter`
  still prints `counter=800000 expected=800000 / ATOMIC OK`** — four threads,
  palthread's mmap, the gs install and the alt stack all correct — with bss
  61,580 -> 58,508. A different constant is just as sound as this one.

**So the constraint is not "do not change the size". It is "do not let the size
VARY DURING A COMPILE".** That is what decides the two routes below: route A
fixes the size before `EmitTlsMainInstall`, i.e. before palthread is ever lexed,
and is therefore exactly as sound as today at ANY size including 0. Route B
grows it as threadvars are parsed, and is the only one that breaks the fold.

A reader who deletes the reserve without doing route A's prescan gets the
COMPILE ERROR above, not corruption — so the failure direction is safe in both
directions here, which is unusual and worth knowing.

## Route B's blocker

**`__pxxTlsBlockSize` FOLDS EARLY — established 2026-09-18 from the mechanism,
not from a comment.** `lib/rtl/palthread.pas:280`
reads the block size from `__pxxTlsBlockSize` rather than restating it, and
`pasparser_expr.inc:4451` lowers that name to `AllocNode(AN_INT_LIT)` with
`ASTIVal := TLS_BLOCK_SIZE` **at the use site, while palthread is being parsed**.
Its own comment states the intent — *"Constants, not calls — they fold to an
AN_INT_LIT here, so a `const` in the RTL can be defined from them."*

So if the block size becomes a value that GROWS when a `threadvar` is seen —
which is route B and only route B — that literal captures whatever it was when
palthread was parsed, which can be BEFORE the growth. Too small a block means gs-relative slots write past the mapping —
the exact silent corruption palthread's own comment warns about, arriving from
inside one compile instead of between two releases.

**Route B therefore needs the builtin to resolve LATE** — a patched immediate
recorded like the other `Patch32` sites, or a relocation — before any of the
reservation work is worth starting. The `const`-definability the comment cites is
currently unused: `palthread.pas:280` is the ONLY consumer in `lib/**` and it
assigns to a local, so nothing today actually depends on the literal form.

`PAL_MIN_STACK` (palthread.pas:85) restates 4224 as part of a stack FLOOR. A
smaller block only makes that floor more generous, so it blocks neither route —
but it is a second copy of a number that has already moved once, and it should be
derived rather than restated whichever route is taken.

# Do not re-measure these

- The 3,072 is per-PROGRAM bss on x86-64, and also per-THREAD stack, since the
  clone stub carves the same block off every child's stack.
- The full block is 4,240 B (1,152 map + 3,072 user + 16 bytes of `struct
  rlimit` scratch past the end). Only the 3,072 is reclaimable; the slot map is
  an ABI other code reads.
- `--emit-obj` and `--shared` already skip the whole thing.

---

## 2026-09-22 — RE-MEASURED PER FRONTEND, AND BASIC IS THE ONE NOBODY HAS LOOKED AT

The summary claimed the NilPy arm was live. It is not, and has not been since
the day it landed. Found by measuring rather than reading, while `next` handed
me this ticket at effective prio 70.

Every row at HEAD (`7ed7bc249672`), one hello per frontend, `bss=` from the ok
line, default against `-dPXX_TLS_USER_0`:

| frontend | default | `-dPXX_TLS_USER_0` | delta | automatic arm? |
| --- | --- | --- | --- | --- |
| Pascal (`hello.pas`) | 34,600 | 34,600 | **0** | YES — route A already gave it back |
| BASIC (`10 PRINT`) | 37,632 | 34,560 | **3,072** | no |
| NilPy (`print()`) | 62,740 | 59,668 | **3,072** | no — retired, correctly |
| C (`puts`) | 72,448 | — | — | no — `__thread` errno, by design |

**The Pascal row is the control and it is the one that proves the instrument
works**: it shows zero delta because route A has already taken the area away,
so the flag has nothing left to give. A table where every row moved by 3,072
would not have distinguished "the arm is off" from "the flag does nothing".

### BASIC is a real open row and it is NOT the same question as NilPy's

> **ANSWERED AND SHIPPED THE SAME DAY, 2026-09-22 (frankb-8e).** All three
> questions below were measured, in the order written, and the arm is live:
> `isBasic and not SourceMentionsKeyword('uses')`. Unit-free `10 PRINT "hello"`
> is bss 37,632 → **34,560** by default, a flat −3,072, and still prints.
> `### The three questions, answered` immediately below this section has the
> measurements. The short of it: BASIC **can** reach a C unit (question 1 is
> YES — `test_basic_comprehensive.bas` already says `USES my_c_lib`), and the
> arm is safe anyway because BASIC's exposure differs from NilPy's in
> **population, not in failure mode** — NilPy pulls C units ambiently through
> `-Fu`, BASIC only on an explicit `USES`, which is exactly what the arm turns
> off on. Guarded by a PAIR of fixtures that fail for opposite reasons.

Nobody has assessed it — the ticket's "long-tail frontends" line treats them as
one undifferentiated group of `or Is<X>Frontend` terms, and they are not one
group. The retirement reasoning above is specific: it is about **C units
reached through `-Fu`**, because `errno` is `__thread`. Whether that exposure
exists for BASIC is **unmeasured**, and I am not going to assert it either way
from the fact that it retired NilPy.

**What has to be established before a BASIC arm is written**, in this order:

1. Can a BASIC program reach a C unit at all? If it cannot, the errno hazard
   that retired the NilPy arm does not apply and the row is cheap.
2. Can a BASIC program reach a Pascal unit that declares a `threadvar`? If it
   can, the Pascal arm's own `uses` test is the precedent, not an obstacle —
   that arm refuses loudly and names the flag.
3. BASIC has no thread-local spelling of its own, which is the NilPy arm's
   starting premise and the only part of it that survived.

**Do not write the arm from the analogy.** The NilPy arm was written from a
sound argument about Pascal units and retired by a C unit nobody had
considered; repeating that with BASIC substituted is the same mistake with a
different letter.

### The three questions, answered — and the BASIC arm is live

Measured 2026-09-22 (frankb-8e) at binary `464ddd6c2b02`, in the order the
section above set, because the section above also said **do not write the arm
from the analogy** and the only way to honour that is to answer its own
questions rather than NilPy's.

**1. Can a BASIC program reach a C unit at all? YES — and it already does.**
`test/test_basic_comprehensive.bas` says `USES my_c_lib` on line 6, against
`test/my_c_lib.c`. This is the exposure that retired the NilPy arm, so the
honest answer to the question as I posed it is the *unfavourable* one, and the
arm had to survive it on some other ground or not be written.

**2. It survives because the two differ in POPULATION, not in failure mode.**
That is the whole finding and it is what the analogy would have got wrong in
both directions. NilPy reaches C units **ambiently** through `-Fu`, and every C
unit declares a `__thread` errno, so a zero-byte area refused *every* mixed
build — that arm was **unusable, not unsafe**. BASIC has exactly one door to a
unit of any language, `USES` during the parse, which is `bparser.inc`'s
`BSourceUsesAUnit` in its own words — and it is the same door the arm switches
off on. A `.bas` with no `USES` cannot reach a C unit by any route.

**3. And the failure is loud if 2 is ever wrong.** Measured directly rather
than inferred from the Pascal side: a `.bas` doing `USES tl_lib`, where
`tl_lib.c` declares `__thread int tl_counter`, compiled at
`-dPXX_TLS_USER_0`:

```
pascal26:2: error: __thread tl_counter: the per-thread variable area is full (0 bytes)...
  near: void   __thread int tl_counter >>>  int tl_bump
(exit 1)
```

naming the file, the line, the declaration and the flag. `402d61e0d` made that
a hard ERROR; `ir_codegen.inc`'s NilPy block still describes it as a WARNING,
which was true when that block was written and is what its own RETIRED note
records. **Reading that comment instead of measuring would have produced the
wrong answer to this question** — it is the same stale-premise trap this
ticket is full of.

**No thread-local scan for BASIC, deliberately.** The Pascal arm scans for
`threadvar` because Pascal can spell one. BASIC cannot, in any spelling, so a
scan for it is a guard that cannot fail and would print PASS forever. `uses` is
the only honest predicate — the same conclusion `BSourceUsesAUnit` reached for
`builtinheap` by a different route.

**`Source` is complete for BASIC** even though `ExpandIncludes` runs only under
`IsPascalFrontend`: BASIC has no include directive at all, so the `.bas` text
*is* the whole program. That is the property C and NilPy lack, and it is why
they stay out — a C header's `__thread` and a NilPy import both arrive after
this point.

| subject | before | after | delta |
| --- | ---: | ---: | ---: |
| `10 PRINT "hello"` (unit-free) | 37,632 | **34,560** | **−3,072** |
| `test_basic_comprehensive.bas` (`USES` ×2) | 38,908 | 38,908 | 0 — correct |
| Pascal `hello.pas` | 34,600 | 34,600 | 0 |
| NilPy `print()` | 62,740 | 62,740 | 0 |
| C `puts` | 72,448 | 72,448 | 0 |

The unit-free row still prints `hello`; the comprehensive row still prints its
21 lines, byte-identical. `-dPXX_TLS_USER_4K` still raises the area on a
unit-free `.bas` (explicit wins, unchanged).

**GUARDED BY A PAIR, AND NEITHER ROW CATCHES WHAT THE OTHER DOES.**
`test_a_unit_free_basic_program_pays_no_threadvar_area.bas` asserts `1152` and
reds at 4224 if the arm is removed;
`test_a_basic_program_with_a_unit_pays_the_full_threadvar_area.bas` asserts
`4224` and reds at 1152 if the arm stops looking at the source, which is the
cheapest wrong widening. The control names a **C** unit on purpose, so the day
a unit arrives without the source saying so it says which half broke. The pin
is a real control for the first row (it answers 4224 where HEAD answers 1152)
and **is not cited as one for the second**, where both answer 4224 — that is
two compilers doing the same correct thing, which is the non-discriminating
control this ticket removed from the NilPy fixture the same day.

Both fixtures read `__pxxTlsBlockSize` as a bare identifier. They have to: the
NilPy row borrows `test/units/utlsblock.pas` to read that number, and importing
anything from the unit-free `.bas` would switch off the very thing under test.
The unit-free fixture also carries a standing warning not to write the
`USES` keyword anywhere in it, **including in a REM** — the decision is a text
scan over the whole source, and this ticket already records the Pascal sibling
destroying itself exactly that way.

### And the 3,072 is now a larger fraction than the ticket assumed

`bug-a-a-pascal-hello-world-is-63kb-after-emission-size-dce` landed today, so a
Pascal hello is 4,528 bytes rather than 25,024. The threadvar area was ~12% of
a hello's bss when this ticket was written and the floor has moved underneath
it. That does not change any decision here, but it does mean **a number quoted
off this ticket before 2026-09-22 has a different denominator** — recorded
because the ticket's own tables carry absolute bss figures with no tree beside
them.

*frankb-8e (Track A). SUPERSEDED BY THE SECTION BELOW, SAME DAY, SAME SEAT:
this said "I did not write the BASIC arm" and the arm shipped a few hours
later -- it is live at `ir_codegen.inc:1877` with both fixtures
(`test_a_unit_free_basic_program_pays_no_threadvar_area.bas`,
`test_a_basic_program_with_a_unit_pays_the_full_threadvar_area.bas`). Left in
place rather than deleted because it is the third sentence of mine falsified by
a later commit of mine in one day, and the shape is worth seeing: a sign-off
records what was true when you stopped, and stopping is exactly when you also
stop re-reading it.*

## 2026-09-22 — ROUTE B IS PRICED NOW, IN BOTH DIRECTIONS, AND IT IS SMALLER THAN THIS TICKET SAYS ON BOTH SIDES

Two numbers were missing and both are here: what route B is WORTH, and what it
actually COSTS. The ticket recorded neither, and the blocker paragraph above
overstates the cost badly enough that nobody was going to look.

### The area is an x86-64-ONLY cost — so the ESP half of this ticket is worth nothing

`TryAssignThreadVarStorage` (`pasparser_decl.inc:2767`) refuses **first**, before
any other check, on `TargetArch <> TARGET_X86_64`: *"a per-thread block is
installed with `arch_prctl(ARCH_SET_GS)` by the clone stub, and the other
targets have a readable thread register (aarch64 tpidr_el0, arm32 tpidruro) but
no way to SET one yet."* So no other target can ever populate the area — and it
is not reserved there either.

Measured 2026-09-22 at binary `48f69d2d285d`, default versus
`-dPXX_TLS_USER_0`, six targets:

| target | default bss | `_0` bss | delta |
| --- | ---: | ---: | ---: |
| x86_64 | 92,340 | 89,268 | **3,072** |
| i386 | 79,576 | 79,576 | 0 |
| arm32 | 79,576 | 79,576 | 0 |
| aarch64 | 88,100 | 88,100 | 0 |
| riscv32 / esp32c3 | 79,576 | 79,576 | 0 |
| wasm32 | 1,096,496 | 1,096,496 | 0 |

xtensa and esp32s3 are NOT in that table and the reason is not TLS: the subject
`uses sysutils`, and those targets refuse an external `calloc` with *"external
(dynamic) symbols are not supported on this target"*. Unmeasured, not zero.

**THE FIRST VERSION OF THAT TABLE WAS TAKEN THROUGH THE WRONG ROUTE AND SAID
THE SAME THING.** It used `test/hello.pas` and answered delta 0 on every cross
target — true, uninformative, and indistinguishable from the finding. `hello.pas`
names no `uses`, so **route A had already zeroed the area on x86-64 too**; the
probe reached the subject by a path that had already removed the thing under
test. The control costs one line and it is the general form: **when every arm
agrees, check that the arm you expected to DISAGREE still does.** Running the
x86-64 arm showed 0 where it had to show 3,072, which is what sent me back for
a subject with a `uses` in it.

**Ranking consequence, and it is not rhetorical.** Whatever `blocked-by` edge
wires this ticket to the ESP size umbrella is transmitting an effective p70 for
a benefit that does not exist on that umbrella's target. `effective_prio` takes
the max over everything a ticket unblocks and nothing in the number says which
edge supplied it. **This ticket has to justify itself on the hosted x86-64 case
alone**, and the section below is the attempt.

### What route B is worth: 25 of 28 host example programs, 3,072 B each, ≤3.32%

Sweep of every `program` under `examples/` — population `find examples -name
'*.pas'` filtered to files whose first keyword is `program`, **46 of 50 `.pas`
files**. Oracle: `-dPXX_TLS_USER_0` reserves a zero-byte area and the compiler
REFUSES (hard error, `402d61e0d`) any compilation that declares a threadvar, so
"compiles at `_0`" == "this whole compilation, RTL chain included, declares no
threadvar" == "route B would reserve 0 here". Control: each subject is compiled
at DEFAULT first, and a `_0` failure is only attributed inside the set whose
default arm succeeded — without it, a missing GL/gtk/tk header reads as a
threadvar refusal.

- 36 of 46 build at default. **36 of 36 also build at `_0`. Zero refusals.**
- **Expectation recorded before the run finished**, and it held: there are
  **zero `threadvar` declarations in all of `examples/` and all of `lib/`** —
  the only three occurrences of the word in `lib/` are comments.
- 8 of the 36 are `examples/esp32/**`, which the sweep built **for the host**.
  Their real target answers delta 0 (table above), so they are excluded rather
  than counted; a ticket quoting the raw 28 would have credited route B with
  the three whose share is HIGHEST (5.19%, 5.17%, 3.68%) on the one target
  where it is zero.
- **Of the 28 host programs: 25 gain 3,072 B; 3 already have it from route A.**
  Mean share of bss **2.86%**, range 0.18% (`chess`) to 3.32% (`g2048`,
  `satdemo`, `menudemo`).

The 3.32% is close to a ceiling rather than a sample: the smallest
`uses`-bearing Pascal program measured is ~92 KB of bss, so 3,072 cannot be a
larger fraction than that for anything with a unit in it.

**Denominator note, because this ticket already carries a different one.** The
`uses`-rule paragraph above says the Pascal arm's reach is *"unit-free programs,
11 of 49 under examples/"*. That was counted over 49 `.pas` FILES by source
inspection; this is 3 of 28 host PROGRAMS that build, by measured delta. Both
rows stand, each with its own population — a re-run disagreeing with either is
not a regression.

### The blocker is much smaller than the section above says

That section names one obstacle, the `AN_INT_LIT` fold, and prescribes *"a
patched immediate recorded like the other Patch32 sites, or a relocation"*. A
full map of `TlsBlockSize`'s consumers says the fold is one of four and the
other three are mostly already late:

| consumer | site | when it runs | route B? |
| --- | --- | --- | --- |
| the `AN_INT_LIT` fold | `pasparser_expr.inc:4451` | parse time | **early — must change** |
| BSS reservation | `ir_codegen.inc:1992` | `EmitTlsMainInstall`, before parsing | **early — must change** |
| two prologue displacements | `ir_codegen.inc:2005`, `:2009` | same | **early — must change** |
| clone stub carve, ×4 reads | `thread_emit.inc:114/120/164/182` | `EnsureCloneStub`, at `IR_CLONE` lowering | **already late — free** |

And two of the three early ones are cheaper than they look. The block's
**ADDRESS** is already late: the prologue reaches it through
`mov r9, @glob BSS_TLS_MAIN`, i.e. a `GlobFix[]` entry the ELF writer resolves
at the end — so what is early is the BSS *offset assignment*, not the reference.
The two displacements are plain immediates in already-emitted bytes, and there
is an existing precedent for exactly that: `EmitProcPrologue` emits a
placeholder `0` for the frame size and `PatchProcPrologue`
(`symtab.inc:15533`) writes the real number after the body, with a per-arch
encoder. **`Patch32` is NOT the mechanism to copy** — it is a within-pass
backpatch; `PatchProcPrologue` is the only existing example in this compiler of
a NUMBER, rather than an address, emitted as a placeholder and filled in later.

**And it is one backend, not six.** `threadvar` refuses off x86-64, so every
site above that would need patching is in the x86-64 path. The `AN_INT_LIT`
fold is the only cross-cutting one, and it is 2 of 25 `__pxx*` builtins that
fold to a literal at all — the other 23 already allocate a dedicated node that
survives to IR and emit.

### DECISION: priced, understood, NOT built — and this is not a park for want of a mechanism

Value ~2.9% of bss on 25 of 28 host example programs, x86-64 only, nothing on
ESP. Cost: defer the `BSS_TLS_MAIN` offset assignment past parsing, patch two
prologue displacements, and stop one builtin folding early. The failure mode of
getting it wrong is **silent memory corruption** — gs-relative slots writing
past the mapping — in the entry prologue every program runs through.

That trade does not clear the bar while the owner's stated goals are a full
green pin, working demos, busybox and lekkerzeilen, and it is worth saying
plainly rather than leaving the ticket reading as blocked. **Route B is not
blocked. It is understood and it is not worth 3% today.** What would change
that: a hosted program whose bss is small enough for 3,072 to be a large share
(nothing in `examples/` is), or a threadvar landing in `lib/rtl` — at which
point route A's `uses` term forces the full area on every program that touches
a unit, and route B becomes the only way to pay for what is actually declared.

**Adjacent, and the reason the second condition is not hypothetical.**
`lib/rtl/sockets.pas:204` says *"There is no threadvar in this dialect, so this
is the tid-keyed table"* and `scheduler.pas:350` says *"Per-thread state
without threadvar"*. Both premises are false — threadvar landed — and **both
designs are still correct, for a reason neither comment gives**: threadvar is
x86-64 only, so a threadvar `errno` would break five targets. A stale RATIONALE
is worse than a stale fact: it reads as *impossible* when the truth is
*possible and wrong here*, and it invites exactly the repair that breaks the
cross targets. Comment repair only; the 64-slot tid table stays.

*frankb-8e (Track A), holding this ticket.*
