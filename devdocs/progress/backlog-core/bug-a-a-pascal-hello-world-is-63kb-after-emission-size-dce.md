---
slug: bug-a-a-pascal-hello-world-is-63kb-after-emission-size-dce
title: "feature-emission-size-dce is done, and `WriteLn('hello')` still emits 63,760 bytes"
track: A
prio: 30
type: bug
blocked-by: []
status: backlog
owner: ""
created: 2026-08-25
summary: "THE PROMOTION LANDED AT 39ca6ac2a (frankh-c0, 2026-09-22, third attempt) AND THIS TICKET IS NOT DONE -- its ORIGINAL mechanism is untouched and is now the whole of what remains, stated at the end of this summary. --dce is the default at -O2, wasm32 carved out. PROOF: full tier at that tree, 4959/4962 pass, 2 flaky, RED on two FAILs and NEITHER attributable to the change -- test-nilpy#675 was recorded NEW-RED by Track T's borg run at pin v417 BEFORE the work (a 1-ULP atan2 difference; byte-identical output under --dce/--no-dce/default so the flag cannot cause it) and test-riscv32#180 is red across FOUR hosts in tstate and compiles rc=0 either way. Attempt 2 was six FAILs; this was two, both outside the change. No green tier was claimed. THE OBJECT-MODEL GATE WAS MEASURED AWAY AND IT WAS MINE: the promotion enacts NEITHER half of decide-a-is-a-pxx-object-..., because --emit-obj keeps all 323 exports (312 WEAK FUNC, identical name sets, UND 0) while dropping 269 LOCAL bodies, and model B's collapse needs RE-ROOTING which an -O level does not do. WASM32 IS CARVED OUT for the TARGET's consumption model, not for our tests: six of seven wasm failures were `inst.exports.<Name> is not a function`, which is what a wasm library IS, and the seventh is flag-INDEPENDENT and already filed. VERIFIED AGAINST frankb-8e's 372dd5113 afterwards (rebuild, every target builds at the default, both correctness rows give their owed codes with no flag, no closure refusal, gate quick GREEN). THE TWO CORRECTNESS REGRESSIONS WERE FIXED BY frankb-8e at 5fccc890a. `--fpc-float-errors` div0 and `--fpc-mem-errors` nilread both give their owed 208/216 under `--dce` now, on all arms (0/208/205/207 and five modes at 216), with `--no-dce` unchanged as the control. The mechanism was EmitCodeAbsToRdx recording no CodeRef for a `call +0 / pop rdx / add rdx, imm32` delta, so the pass neither protected the target nor re-aimed it; the i386 twin and two latent siblings went with it (see bug-a-two-code-to-code-references-are-unrecorded-and-are-safe-only-by-where-they-happen-to-sit, now done). THE EVIDENCE IS THE SLOT BYTES, NOT THE EXIT CODE: before the fix the four deltas were byte-identical in the --dce and --no-dce binaries of one program while the code between them had moved; after, exactly one moves (-66886 -> -24082, 42,804 bytes dropped in that gap) and three do not -- which is the three-survive/two-break split this ticket measured and could not explain. OF THE SIX FAILS FROM ATTEMPT 2, FOUR REMAIN AND NONE IS A CORRECTNESS BUG: two are the `test-emit-obj` `t Hidden` control arms whose subject the promotion deletes and whose repair is `--no-dce` on those rows, NOT weakening the assertion (dropping the row leaves a guard that passes when the symbol is absent); one is test-core#1008, frankb-8e's own wasm32 renumbering guard firing correctly on an unclosed live set; one is not ours (test-riscv32#180, identical rc either way). SO A THIRD ATTEMPT IS: respell those two rows, carve wasm32 out of the default, re-run the tier. THE WASM32 CARVE-OUT IS STILL REQUIRED and is not a defect -- the harness reaches bodies by EXPORT NAME and `--dce` correctly drops an export nothing reaches, so those rows would arrive as failures and read as evidence against the pass. AND THE TRAP IS UNCHANGED: the self-host fixedpoint converges at the promoted setting and converged while both regressions were live -- it converged at all seven builds of the fix too, including the unfixed ones. It is not evidence about this class and it reads exactly like evidence. THE OBJECT-MODEL GATE IS MEASURED AWAY AND IT WAS MINE (frankh-c0, 2026-09-22): the promotion enacts NEITHER half of decide-a-is-a-pxx-object-a-self-contained-runtime-or-a-translation-unit, so a third attempt says THAT in the commit rather than picking a side. I had written that promoting turns per-object DCE on by the back door and therefore answers the fork silently. The first clause is true and the second does not follow. Measured at fd6965890102, x86-64, `--emit-obj` of a C TU pulling the runtime: `--dce` drops 269 of 540 LOCAL FUNC bodies and the export surface is INVARIANT -- 323 exports, 312 of them WEAK FUNC, IDENTICAL NAME SETS, UND 0 both ways; a second TU drops 436 of 489 locals with 2 exports unchanged. The bodies DCE removes are LOCAL and were never part of the object's external contract, so an object still supplies exactly what it supplied before under EITHER answer. The fork's model B -- 298 of 307 exports vanishing -- requires RE-ROOTING at the TU's own exports, which the decide itself had to SIMULATE because `--dce` does not do it; promoting an -O level does not do it either. SCOPE, stated because the decide flags it: x86-64. The xtensa row is VACUOUS and is not counted -- exports were identical there but `--dce` dropped ZERO bytes (390 B both), so it cannot tell a preserved export from a pass that did nothing. PROMISE, WITH ITS POPULATION THIS TIME: at tree fd6965890102, x86-64, `program h; begin WriteLn('hello'); end.`, code= from the ok line, 67,541 B -> 18,790 B, -72.2%. That does not refute the earlier -66% / 74,096 -> 24,944 row -- different tree, moving floor -- so both stand, each with what it measured. THE ORIGINAL MECHANISM THIS TICKET NAMES IS STILL UNTOUCHED AND IS NOT THE BLOCKER: PasApplyDefaults defines PXX_MANAGED_STRING unconditionally so every Pascal program still PULLS builtinheap, and DCE removes the consequence rather than the pull; frankS scoped that half on 2026-09-18 (-98% code on bare esp32c3). THE STATED BLOCKER IS ANSWERED AND IT WAS NOT THE BLOCKER (frankb-8e, 2026-09-22, tree fda77c48b8ee): `string` lexes as tkString_T, a KEYWORD token (paslexer.inc:166), not tkIdent, so a token-kind test reaches it; with that plus eight further type names, PromoInt and the string-valued intrinsics, an evidence scan BUILDS AND RUNS -- x86-64 hello 25016 -> 4472 B (-82.1%), xtensa --esp-profile=bare code 860 -> 58 B and procs 88 -> 0 (-93.3%), riscv32 --esp-profile=bare 336 -> 20 B (-94.0%), all four rows measured against this tree, the pin agreeing on both bare rows. THE REAL BLOCKER IS ORDERING AND NO TOKEN SCAN CAN REACH IT: EmitAnsiStringRuntime is decided at pasparser_prog.inc:1977, while the ambient RTL units that are THEMSELVES written over managed strings are pulled AFTER it -- at :2163 and, for units, from a SECOND pull site at pasparser_proc.inc:7422 -- so `var p: PChar`, `var c: WideChar` and `var s: set of Char` each refuse inside lib/rtl/textfile.pas:1344 with no string in the program at all. The evidence arrives after the decision. WHAT WOULD SPRING IT: any construct that pulls an ambient unit whose body calls a string stub, which is why the fix is to settle the emission after unit pulls (or emit on demand), not to add names. THE FAILURE DIRECTION IS CONFIRMED SAFE AND IS NOW MUCH BETTER EVIDENCED THAN THE ONE riscv32 ROW BELOW: six string shapes x six targets refused 36 of 36 with 0 built, by TWO independent guards (IREmitCodeCall's addr=0 refusal on x86-64; name resolution on the five cross targets), and nine string-valued builtin expressions gave 3 constant-folded agreeing with the oracle, 6 refusals, 0 silently wrong. Work is parked at devdocs/progress/parked/needsansiruntime-evidence-scan.patch (234 lines, quick gate 35/36 with the one failure attributable and diagnosed above). EARLIER HISTORY BELOW."
---

# The measurement

| program | size |
| --- | --- |
| `10 PRINT "hello"` (.bas, no USES) | 559 B |
| `WriteLn('hello')` (.pas) | **63,760 B** |
| `test_basic_comprehensive.bas` (has USES) | 103,935 B |

The mechanism is known and is not subtle: `DetectPascalRuntimeNeeds` sets
`needsAnsiRuntime := PasDefineExists('PXX_MANAGED_STRING')`, and
`PasApplyDefaults` defines that symbol **unconditionally** — so every Pascal
program pulls `builtinheap`, always, whether or not it touches a managed string.

# Why this is filed as a bug rather than an optimisation

[[feature-emission-size-dce]] is in `done/` and its stated goal is *"emit only
reachable code ... emit a unit routine only if reached from the program entry"*,
with `hello.pas` named in its own text at ~31.6 KB against a ~29 KB reachable
baseline. The current 63,760 bytes is worse than the number the done ticket was
arguing about. Something regressed, or the pass never covered the
unconditional-`PXX_MANAGED_STRING` door, or the ticket closed on a narrower
slice than its title. `root-cause-over-microfix.md` applies: find out which
before writing anything — the answer changes what the fix is.

# What depends on it

[[decide-how-much-string-machinery-the-basic-frontend-gets]] deferred BASIC's
559-byte unit-free binary to this ticket rather than building a BASIC-only
conditional runtime pull. If this lands, that property comes back on its own,
for every frontend, instead of for one.

# Do not

Fix it by making `PXX_MANAGED_STRING` conditional on a source scan in the Pascal
driver. That is the per-frontend special case the BASIC decision rejected, one
language over. The general mechanism is reachability, and it already has a home.

---

## 2026-08-30 — an EMPTY program is 61,279 B, so the hello is ~2 KB of it

Measured at HEAD `4039216a7f25` while building the size canary for
[[bug-a-the-esp32-bare-image-doubled-in-code-and-grew-half-again-in-bss]]:

```
$ printf 'program e;\nbegin\nend.\n' > empty.pas
$ pxx empty.pas out
ok: out  [code=61279B  data=1960B  bss=42452B  procs=129]
```

Against this ticket's 63,760 B for `WriteLn('hello')`, the whole of
`WriteLn('hello')` — the call, the literal, the string machinery it drags in —
is about **2.5 KB on top of a 61.3 KB floor that a program with no statements
already pays.**

That reframes the question the ticket asks. "Either the pass is not reaching
this, or the done ticket's scope was narrower than its title" — the measurement
says it is not about reaching *this program*, because there is no program here
to reach. Whatever is being emitted is emitted for a unit with an empty body, so
the subject is the RTL/startup floor, not the DCE pass's treatment of
`WriteLn`. Anyone starting from the hello-world will spend the first hour
looking at string machinery that accounts for 4% of the number.

`x86_64-empty` is now a **watched** subject: `tools/size_canary.py`, baseline in
`tools/size_baseline.json`, running in native/limited/full as `size-canary#00`.
It is a delta gate — it freezes 61,279 B rather than blessing it — so when this
ticket is fixed the canary reports the shrink out loud and asks to be
re-baselined, and it reds if the floor grows again meanwhile.

*(Measurement and instrument: Track T. The 61 KB itself is this ticket, and
still Track A's.)*

## Re-measured 2026-08-30 — the subject of this ticket is 0.1% of the number

Measured by frank-coordinator against `stable_linux_amd64/default/pinned`
(`1d69760deabe`), after the size canary added an empty-program row nobody had asked for:

| program | code |
| --- | --- |
| `program e; begin end.` | **61,276 B** |
| `program h; begin WriteLn('hello'); end.` | **61,350 B** |

**`WriteLn('hello')` costs 74 bytes on a 61,276-byte floor.**

This ticket's own open question — *"either the pass is not reaching this, or the
done ticket's scope was narrower than its title"* — has a third answer, and it is
the right one: **there is no *this* to reach.** The body is empty and the number
is unchanged. The subject is the **RTL/startup floor**, not emission-size DCE's
treatment of `WriteLn` or of string machinery.

Anyone starting from the hello-world spends their first hour on the ~0.1% and
concludes DCE is broken. It is not this ticket's fault — a hello-world is the
obvious probe, and *the obvious probe put the entire mass in the part that
varies*. The fix is to re-scope onto the floor, or to close this and open one
named for it.

`x86_64-empty` is now a watched subject in `tools/size_canary.py`, so a genuine
reduction arrives as a reported shrink against a frozen baseline rather than as
prose in a ticket. Note it is **advisory**: it reports and files, it does not fail
a tier.

## Scoped 2026-09-18 (frankS) — the prize, the locus, and the one concrete blocker

**The prize, measured on bare esp32c3** with a UART-only program using
`ShortString` and never allocating:

| | code | data | bss |
| --- | ---: | ---: | ---: |
| default | 58,900 | 736 | 71,452 |
| `-uPXX_MANAGED_STRING` | **1,156** | 432 | **5,288** |

**−98% code and −93% bss, with byte-identical program output** (`noalloc-start
123 noalloc-done` from both, under Espressif qemu). On bare ESP this is the
largest single saving anywhere in
[[umbrella-an-esp32-image-is-as-small-as-it-can-be]] — bigger than the 32 KB
alt stack and bigger than the whole rest of the bss floor combined.

**The detection already exists and is already conservative.**
`DetectPascalRuntimeNeeds` (`pasparser_prog.inc`) sets `needsAnsiRuntime` from
real evidence — `tkUses`, and the identifiers `AnsiString` and `Variant` — and
sets `needsHeap` from `tkUses`/`tkArray`/`tkClass`, `div`/`mod`, floats,
`New`/`Dispose`/`ReallocMem`/`SetLength`/`GetMem`/`FreeMem`, and `write`
formatting. **All of that careful work is discarded by one line:**

```pascal
needsAnsiRuntime := PasDefineExists('PXX_MANAGED_STRING');   { :104 }
```

`PasApplyDefaults` defines that symbol unconditionally, so the variable is True
before the scan starts and the scan can only confirm it.

**The failure direction is safe, and this is what makes the change tractable.**
Under-detecting produces a COMPILE error, never a wrong binary — measured:

    pascal26:7: error: target riscv32: frozen tyString concat unsupported

**THE ONE CONCRETE BLOCKER: the `string` keyword is not in the scan.** `var s:
string; s2 := s + 'y'` has no `AnsiString` identifier and no `uses`, so flipping
`needsAnsiRuntime` to evidence-only breaks it — verified, that exact program
fails under `-uPXX_MANAGED_STRING` today. `tkString` is the string LITERAL
token (see `defs.inc:6802`, *"tkString empty is a legitimate `''`"*), not the
type keyword, so whoever takes this must first establish what `string`,
`ShortString`, `WideString` and `UnicodeString` lex as and add them.

## 2026-09-22 (frankb-8e): the stated blocker is answered, and it was not the blocker

Tree `fda77c48b8ee`, compiler sha printed beside every row below. Parked patch:
`devdocs/progress/parked/needsansiruntime-evidence-scan.patch` (234 lines).

**The lexing question this ticket asks is answered.** `string` is **`tkString_T`,
a keyword token** (`paslexer.inc:166-167`), not `tkIdent` — so the `CaseEqual`
arm the ticket points at could never have seen it, and the test is a token
KIND. Note the 6-char keyword table matches only `string` and `String`, so a scan
wanting every spelling must test the token KIND and the ident NAME, which is
what the parked patch does.

**THERE IS NO DEFECT BEHIND THAT OBSERVATION, AND IT IS WORTH SAYING SO HERE SO
NOBODY WRITES ONE UP.** Found by frankh-c0 and re-derived at `fda77c48b8ee`
rather than transcribed, `var s: <decl>; s := 'ab'; WriteLn(s, ' ', Length(s))`,
all nine rows building and printing `ab 2`:

| declaration | | declaration | |
| --- | --- | --- | --- |
| `string[20]` | ab 2 | `string` | ab 2 |
| `String[20]` | ab 2 | `STRING` | ab 2 |
| `STRING[20]` | ab 2 | `StRiNg` | ab 2 |
| `StRiNg[20]` | ab 2 | `AnsiString` / `ANSISTRING` | ab 2 |

c0's four rows are the FROZEN `string[N]` spelling; the bare and `AnsiString`
rows are added here because bare `string` is the MANAGED type and is the one
this ticket turns on, so the frozen rows alone would not have covered it. The
ident path resolves every non-keyword spelling case-insensitively, so the short
table has **no observable consequence**. Real observation, nothing reachable
behind it — `rejected/`, never a low prio, per the four-terminal-folders rule. `ShortString`/`WideString`/`UnicodeString`/`UTF8String`/
`RawByteString`/`OleVariant` are ordinary identifiers and were all measured to
need the bundle, as was `string[N]` — a frozen string still reaches the concat
and write helpers, so there is no win in telling frozen from managed here.

**The prize is real and reproduces off the ESP profile.** Baseline
`fda77c48b8ee` -> evidence scan, same tree, `program hello; begin
WriteLn('Hello, world!'); end.`:

| target | baseline | evidence scan | delta |
| --- | --- | --- | --- |
| x86-64 (file bytes) | 25,016 | 4,472 | **-82.1%** |
| xtensa `--esp-profile=bare` (code=) | 860 B, procs 88 | 58 B, procs 0 | **-93.3%** |
| riscv32 `--esp-profile=bare` (code=) | 336 B, procs 85 | 20 B, procs 0 | **-94.0%** |
| riscv32 hosted (code=) | 33,244 B | 33,244 B | 0% |

The pinned compiler agrees with this tree on both bare rows (860/336), so no
intervening change contributes to them. The hosted riscv32 row is zero on
purpose: `write`/`writeln` route through `PXXWriteNL`/`PXXWriteDecW` there and
on xtensa, so the scan must pull the heap unit for any program that writes —
measured across all seven targets, and x86-64/i386/arm32/aarch64/wasm32 need
nothing. On the BARE ESP profile `write` emits nothing at all, which is why the
two bare rows keep the whole win.

**THE REAL BLOCKER IS ORDERING, AND NO TOKEN SCAN CAN REACH IT.**
`EmitAnsiStringRuntime` is decided at `pasparser_prog.inc:1977`. The ambient RTL
units that are *themselves* written over managed strings are pulled **after**
it — at `:2163`, and for units from a **second, independent pull site** at
`pasparser_proc.inc:7422`. So the evidence arrives after the decision, and these
three refuse inside `lib/rtl/textfile.pas:1344` with no string anywhere in the
program:

    var p: PChar;        var c: WideChar;        var s: set of Char;

Each pulls a unit whose body calls a string stub. Adding names does not fix a
class where the trigger is *a unit arriving behind the construct*. Two
narrowings were tried and measured, and both are in the parked patch: coupling
`needsHeap`/`needsTextfile`/`needsMath`/`needsThreads`/`needsWide` into
`needsAnsiRuntime`, and broadening the emission condition to every ambient flag.
The first fixed `test_promoint_bitwise.pas` (which needed `PromoInt` added to
the pre-scan, because `needHeapUnit` is computed before `needsPromoInt` exists);
neither reaches the three above. **The fix is to settle the emission after unit
pulls, or to emit the stubs on demand** — the tidy version moves the ~150-line
registration block below the token loop, which is its own verified pass.

**The failure direction is safe — confirmed, and on far more than the one
riscv32 row above.** Under-detection cannot produce a wrong binary:

- six string shapes x six targets: **36 refused, 0 built**, by TWO independent
  guards — `IREmitCodeCall`'s `addr = 0` refusal on x86-64 (a guard that exists
  because `--threadsafe` once shipped broken on every NilPy program), and plain
  name resolution on the five cross targets (`PXXStrDecRef not found`,
  `PXXStrConcat`, `PXXStrEq`, `PXXWriteStrMW`);
- nine string-valued builtin expressions naming no type: 3 constant-folded and
  **agreed with the oracle**, 6 refused, **0 silently wrong**.

**AND THE MEASUREMENT OFFERED FOR THAT CLAIM TESTS A DIFFERENT MECHANISM —
BOTH TIMES IT WAS TAKEN.** The row above cites `-uPXX_MANAGED_STRING`, and so
did the seat re-checking it today, before noticing.

**NOT INDEPENDENTLY — CORRECTED 2026-09-22 BY THE SEAT THAT CLAIMED IT, AGAINST
ITS OWN TRANSCRIPT.** That seat told two peers the two of us had reached the
wrong lever independently, from recollection, and it is false: in its session
jsonl the literal `-uPXX_MANAGED_STRING` is in context at record 29522 — its own
`cat` of THIS FILE, carrying the claim and, in the same paragraph, this route
offered as how to check it — and the first invocation is at record 30640, 1,118
records later. The route was inherited, not converged on. **Which makes the
mechanism worse rather than better: a wrong verification route recorded beside a
claim is picked up by exactly the person who comes to AUDIT that claim, because
auditing means reading the claim and the route is the adjacent sentence.** The
audit inherits the instrument the audit is about, it needs no second seat, and
it recurs on every future re-check until the route is corrected in place — which
is what the paragraph above is for. That flag is
consulted in ~15 places to decide what `string` **means** (`util.inc:148`
`BareStringKind`, `symtab.inc:3297/3349`); undefining it makes `string` a frozen
255-byte type. Under-detection changes **one** consumer, `needsAnsiRuntime`,
and never touches the type. The two routes give opposite answers: with
`-uPXX_MANAGED_STRING` a concat loop **builds clean and silently truncates** —
`n=26` prints `len=255` against an owed `260`, rc=0, no diagnostic, boundary
exactly at 255 — which reads as a refutation of the safety claim and is not one.
Simulated properly (a compiler built with `needsAnsiRuntime := False`) the same
program **refuses to compile**. The conclusion was right both times and the
evidence was about something else, which is this repo's own "an instrument lies
by being correct about something else" in a claim that a check is unnecessary.
To re-verify this claim, build the compiler with that initialiser forced False;
do not reach for the define.

**Why it was not done in the same pass as the rest of today's ESP work:** the
change flips a default for **every Pascal program on every target**, the
detection set is a judgement call whose wrong answers reach users as compile
errors, and the quick gate covers x86-64. It wants its own pass with a real
sweep, not a bolt-on. The manual lever is documented meanwhile
(`docs/targets/esp32.md`, bare-profile notes).

## RE-MEASURED 2026-09-19 (frankS)

| program | plain `-O` | `--dce` |
| --- | --- | --- |
| `WriteLn('hello')` | 74,096 | 24,944 |
| `begin end.` | 74,040 | 24,888 |

`-O3` gives 24,944, identical to `--dce`.

Two things follow, and the second is the one that changes the ranking.

**The table at the top of this ticket is stale upward.** 63,760 was measured
2026-08-25; the floor has grown 10,336 bytes since, and nobody re-measured
because the number in the summary was never contradicted by anything. A figure
only gets checked when someone disagrees with it, and nobody disagrees with a
number in a summary.

**The general answer the `decide` ticket bet on exists and delivers.** That
decision accepted ~100 KB BASIC binaries on the grounds that size is a general
problem with a general answer — reachability-gated emission. It is written, it
runs on five of six targets, and it takes two thirds off this floor.

What it does not do is change the mechanism this ticket names: the pull is
still unconditional, and DCE only removes what the pull dragged in. So the
residual is narrower than the title — whether the default `-O` should enable
the pass — and that is not a flag flip. Turning the analogous default on for
`--emit-obj` surfaced
[[bug-a-dce-under-emit-obj-crashes-a-two-object-i386-link-before-main]]: an
existing shipping path that links cleanly and dies before `main` on a
two-object i386 link, invisible because every single-object row passes. The
same per-target evidence is wanted here.

## 2026-09-22 (frankb-8e) — A CONSTRAINT ON ANY RETRY: wasm32 MUST NOT INHERIT THE DEFAULT

Recorded here rather than in the C-cross bug because it is not a defect and it
will not surface as one: it is a property of the **harness**, and it would land
as a mysterious row of failures on whoever retries the promotion.

**The wasm harness reaches bodies by EXPORT NAME**, and `--dce` correctly drops
an export that nothing reaches. So a wasm32 program that is right, and a pass
that is right, produce a harness that cannot find the thing it was going to
call. Nothing is broken; the entry contract differs from every other target's.

So a `-O2` promotion needs an explicit wasm32 carve-out or a harness that
names its roots, and **the failures it would otherwise produce are not
evidence against the pass** — which is exactly how they would read, arriving in
the same tier run as real ones.

For the same reason, 8e's wasm32 `--dce` work guards the renumbering seam with
a refusal when `WasmPatchCalls` is asked for the index of a dropped body. That
guard found its own bug on the first run, and the failure it prevents is a
**valid module calling the wrong function** — the silent arm, one target over.

## 2026-09-22 — SECOND PROMOTION ATTEMPT, ALSO REFUSED. 4949/4955 pass, RED.

The first attempt reduced to one bug (cross-target C entry, fixed by frankb-8e
at `a79934842`, confirmed here by mutation). With that fixed the tier was re-run
at `--dce` on by default at `-O2`. **101 hard FAILs became 6.** Still RED, and
the six sort into three groups that want three different things.

**TWO CORRECTNESS REGRESSIONS — these are what refuse it.** Both are instances of
`bug-a-compiler-emitted-runtime-stubs-are-invisible-to-every-gate-we-run`, which
names them in its own summary, and both reproduce in one line:

| test | flag | want | `--dce` | `--no-dce` |
| --- | --- | --- | --- | --- |
| `test-core#519` | `--fpc-float-errors` div0 | 208 | **139** | 208 |
| `test-core#2353` | `--fpc-mem-errors` nilread | 216 | **139** | 216 |

**The mechanism is NOT "an installed-only handler is invisible" — that was my
first reading and a two-sided control refutes it.** `test_signal_handler_callback_b336`
and `test_setsignalhandler_call` are installed-only and come out **rc=0 under
`--dce`**. frankb-8e root-caused it: `EmitCodeAbsToRdx` (`ir_codegen.inc:1001`)
materialises a code address with `add rdx, imm32` where the imm32 is **a delta
fixed at emit time**, and records no `CodeRef`, so the pass neither protects the
target range nor re-aims the delta. Only sites with a droppable body in the gap
break — exactly the three-survive / two-break split measured. There is an
unmeasured i386 twin at `ir_codegen386.inc:335`.

Recorded in the p55 ticket as two casualties **of the gate blindness**, which is
that ticket's real claim, and explicitly NOT as instances of its mechanism.

**ONE REAL BUG CAUGHT BY A GUARD — `test-core#1008`, wasm32.** The backend
refuses the build outright: *"--dce dropped slot 0 (PXXHdrInit) and something
live still references it -- the live set is not closed under the call graph"*.
That is frankb-8e's own renumbering guard, added the same day, firing on
somebody else's change. **Note it is NOT the failure 8e predicted** (it predicted
an export nothing reaches being dropped, giving a module that builds and cannot
be called); it is a compile-time refusal of an unclosed live set, which is
worse and was caught for free.

**TWO ROWS WHOSE SUBJECT THE PROMOTION DELETES — `test-emit-obj#37` and `#38`,
and they are NOT bugs.** Both assert `nm ... | grep -q ' t Hidden$'`: that a
non-exported routine is emitted as a LOCAL symbol. Under the pass `Hidden` is
inlined and its dead body correctly removed, so the symbol is absent — and
**the behaviour is unchanged**, both objects link against the C host and print
`42 / 42 / -42`. Exports are untouched (`PxxLibAdd`/`Mul`/`Negate` all present,
0 undefined), which independently confirms the measurement in
`decide-a-is-a-pxx-object-a-self-contained-runtime-or-a-translation-unit`:
**exports ARE the root set**, so the pass can only remove locals — 142 symbols
to 50 here.

These are the SEVENTH and EIGHTH control arms using the default invocation as
their baseline, after the five respelled at `311ebde9e` and the sixth at
`65c3df610`. **The repair is `--no-dce` on those two rows, NOT weakening the
assertion.** Dropping the `' t Hidden$'` row and keeping only
`! ... ' T Hidden$'` would leave a guard that PASSES WHEN THE SYMBOL IS ABSENT —
"if the machinery did nothing at all, would this row still pass?" is yes, and
the row exists to ask whether a non-exported routine is local rather than
global, which needs the symbol to exist.

**ONE NOT OURS — `test-riscv32#180`** (`cunsigned_semantics_sweep_b138.c`):
identical rc with and without the pass, and it had already taken a flake-guard
retry earlier in the same run.

**THE TREE IS REVERTED.** `compiler.pas` is back to `OptLevel >= 3` and the
binary is byte-identical to the pre-attempt one (`f7dedaea694f`). The `-O3`
comment is rewritten to carry both refusals so a third attempt starts from the
evidence.

**AND THE ONE THING A THIRD ATTEMPT MUST NOT REPEAT:** the self-host fixedpoint
converges at the promoted setting, in 2 rounds, and it converged while both
correctness regressions above were live. It is not evidence about this class.

## A CONSEQUENCE OF THE REFUSAL THAT IS NOT ABOUT SIZE (raised by frankz-e5, 2026-09-22)

Refusing the promotion also declines to answer an open owner fork by the back
door, which is worth more than it costs.

`decide-a-is-a-pxx-object-a-self-contained-runtime-or-a-translation-unit` asks
one question: *do we promise that a pxx object can supply the runtime for
SOMETHING ELSE, or only for ITSELF?* Its own summary records the consequence —
answer "for something else" and per-object DCE stays off the table until the
runtime is shared.

**The `-O` rule is unconditional on OUTPUT MODE.** That is deliberate, and
frankuser confirmed it should not be special-cased away. So `--dce` arriving at
the default `-O2` turns per-object DCE on **by the back door** — enacting one of
the two answers to a question the owner has not been asked.

The exposure is narrow and the decide ticket says so: the pxx-to-pxx pair is
**not** at risk, both objects carrying everything they reach with zero undefined
symbols; the risk is a **non-pxx consumer** or the `libcrtl.a` direction. **And
it is not source-auditable** — 20 of the 298 exports that would vanish under the
re-rooted model are routines a backend lowers onto and **no source names**, so no
consumer can grep for whether it is affected.

**A third attempt must say which half it enacts, in the commit**, so the
decision reads as MADE rather than BYPASSED. It is not this ticket's question
and is not answered here.

## 2026-09-22 (frankb-8e) — THE TWO CORRECTNESS REGRESSIONS ARE FIXED. The remaining work is the tier re-run.

Both reproduce at HEAD and both are gone. `EmitCodeAbsToRdx` now records its
delta as a CodeRef, which is what the refusal above named and what I had
root-caused without fixing.

| test | flag | want | before `--dce` | after `--dce` | `--no-dce` (control) |
| --- | --- | --- | --- | --- | --- |
| `test-core#519` | `--fpc-float-errors` div0 | 208 | 139 | **208** | 208 |
| `test-core#2353` | `--fpc-mem-errors` nilread | 216 | 139 | **216** | 216 |

All arms, `--dce`: ferr `''`/`div`/`ovf`/`inv` = 0/208/205/207 with the exact
text `Runtime error 208 (division by zero)`; merr nilread/nilwrite = 216/216.

**THE MECHANISM, CONFIRMED BY THE SLOT'S OWN BYTES RATHER THAN BY THE EXIT
CODE.** The site is `call +0 / pop rdx / add rdx, imm32`, and the imm32 is
`target - (the address the call pushed)` — an emit-time constant with no
record, so DCE neither protected the target's bytes nor re-aimed the delta.
Measured before the fix, the four deltas in the `--dce` and `--no-dce` binaries
of the same program were **byte-identical** while the code between them had
moved:

    --no-dce   5bffffff a7feffff bafcfeff c9feffff
    --dce      5bffffff a7feffff bafcfeff c9feffff      (before)
    --dce      5bffffff a7feffff c9feffff eea1ffff      (after)

**One delta moved and three did not, and that is the positive control**:
`bafcfeff` (-66886) became `eea1ffff` (-24082), i.e. 42,804 bytes were dropped
inside that one gap. The other three gaps had nothing droppable in them, which
is the three-survive / two-break split this ticket measured and could not
explain. If the fix had done nothing every row would still read 139.

**THE SHAPE ALREADY HAD A HOME, so the patcher needed no new arm design.**
`target - anchor` measured from a pushed PC is xtensa's long-form slot one
architecture over, and `CodeRefAnchor` already travels per-slot and is remapped
by `DceNewOff` in `DceRun`'s compaction. `PatchCodeRefSlot`'s x86 tail gained
an `anchor >= 0` branch above its rel32 default. No existing x86 slot records
an anchor (every one passes -1), and the three negative sentinels are xtensa
forms that return before the tail, so the branch is unreachable for everything
that existed before this commit — `--no-dce` output is byte-identical to the
pre-fix binary on both repro programs, which is the negative control.

**The i386 twin `EmitCodeAbsToEax386` is fixed in the same commit and was NOT
caught by anything** — there is no i386 `--fpc-*-errors` row for it to break.
It is the same emitter with the same missing record; i386 exception builds run
correctly `--no-dce` and `--dce` (identical output, `1..12` both ways).

**The size prize, with its population, because this ticket has been quoting
numbers without one.** Tree `fd6965890102`, x86-64, `program h; begin
WriteLn('hello'); end.`, `code=` from the compiler's own ok line:
**67,541 B plain `-O` → 18,790 B with `--dce`, −72.2%.** That does NOT refute
the −66% / 74,096 → 24,944 row above — it is a different tree and the floor has
moved again — so both rows stand, each with what it measured. What would retire
mine: any change to the RTL startup floor.

**WHAT IS LEFT IS THE TIER RE-RUN AND NOTHING ELSE MECHANICAL.** Of the six
FAILs from attempt 2: two are these, fixed; two are the `test-emit-obj` control
arms wanting `--no-dce` (the repair this ticket already specifies, and NOT
weakening the assertion); one is `test-core#1008`, a wasm32 guard firing
correctly on an unclosed live set; one is not ours. **The wasm32 carve-out this
ticket records above is still required** and is not evidence against the pass.

**The trap this ticket warns about was respected: the self-host fixedpoint is
NOT quoted as evidence here.** It converged at every one of the seven builds I
made this session, including the ones carrying both live regressions. The
evidence is the two repros, their `--no-dce` controls, and the slot bytes.

Tree `fd6965890102`; `gate.sh quick` green.

## 2026-09-22 (frankh-c0) — THE OBJECT-MODEL GATE WAS MINE AND IT IS MEASURED AWAY

I wrote the blocker this retires, in `8f0a...`'s neighbour section and in this
ticket's summary: *the `-O` rule is unconditional on OUTPUT MODE, therefore
`--dce` arriving at the default `-O2` enacts one half of
`decide-a-is-a-pxx-object-a-self-contained-runtime-or-a-translation-unit`
silently.* **The first clause is true. The second does not follow, and I never
measured it — I reasoned from the rule to the consequence.**

Measured at tree `fd6965890102`, x86-64, `--emit-obj`, `readelf -sW`:

| TU | flag | LOCAL FUNC | exports | UND | export NAME sets |
| --- | --- | --- | --- | --- | --- |
| C TU pulling the runtime | `--no-dce` | 540 | 323 (312 WEAK FUNC) | 0 | — |
| same | `--dce` | **271** | **323 (312 WEAK FUNC)** | 0 | **IDENTICAL** |
| leaf C TU | `--no-dce` | 489 | 2 | 0 | — |
| same | `--dce` | **53** | **2** | 0 | **IDENTICAL** |

**The pass removed 269 and 436 local bodies and not one export.** That is the
decide's own finding — *"`--dce` does not move the export surface at all; the
exports ARE the root set"* — reproduced at HEAD, after today's `CodeRef` fix,
on two TUs it did not use.

### Why it follows that neither half is enacted

The bodies `--dce` removes are **LOCAL**. They were never linkable from outside
and were never part of the object's external contract. So after the pass the
object supplies **exactly what it supplied before**, and that is true under
answer A (*it supplies the runtime for something else*) and under answer B
(*only for itself*) alike. Nothing about the promise changes.

What WOULD change it is model B's **re-rooting** at the TU's own two exports —
298 of 307 weak exports vanishing. The decide had to **SIMULATE** that off the
object's relocations precisely because `--dce` does not do it. **Promoting an
`-O` level does not do it either.** A third attempt therefore states in its
commit that it enacts **neither** half, and the fork stays open and untouched.

### Scope, and one row I am NOT counting

x86-64. The decide flags a Pascal/xtensa object as the gap most likely to
matter, so I tried it: exports came out identical — **and `--dce` dropped zero
bytes on that TU (390 B both), so the row cannot tell a preserved export from a
pass that did nothing.** It is the *"would this still pass if the machinery did
nothing at all?"* case and it is vacuous. The x86-64 rows are the evidence; the
xtensa question is still open and wants a TU with something to remove.

**What would retire this section:** an `--emit-obj` TU on any target where
`--dce` demonstrably removes bodies AND an export disappears. That has not been
observed on any target.

## 2026-09-22 (frankh-c0) — LANDED at `39ca6ac2a`, and what is left is the mechanism this ticket is NAMED for

The promotion is in. **This ticket is not done**, and the remaining half is the
one its title is about: `PasApplyDefaults` defines `PXX_MANAGED_STRING`
unconditionally, so every Pascal program still PULLS `builtinheap`. **DCE
removes the CONSEQUENCE, not the pull.** frankS scoped that half on 2026-09-18
(-98% code on bare esp32c3).

**THE BLOCKER I HANDED ON HERE WAS THE WRONG SHAPE, and frankb-8e answered it
rather than inheriting it** (2026-09-22, banked `b823a08d6`, not landed).
`string` lexes as `tkString_T`, a KEYWORD token (`paslexer.inc:166`), so the
`tkIdent`/`CaseEqual` arm the ticket pointed at **could never have seen it** —
adding the name reaches nothing.

**The real blocker is ORDERING and no token scan can reach it.**
`EmitAnsiStringRuntime` is decided at `pasparser_prog.inc:1977`, while the
ambient RTL units that are themselves written over managed strings are pulled
*after* it (`:2163`, plus a second independent site at
`pasparser_proc.inc:7422`). The evidence arrives after the decision. Three
programs containing no `string` at all still refuse inside
`lib/rtl/textfile.pas:1344`, each because it pulls a unit whose BODY calls a
string stub:

    var p: PChar;      var c: WideChar;      var s: set of Char;

The fix is to settle emission after the unit pulls, or to emit on demand.
Whoever takes this next takes THAT; the size work below is finished.

**Worth noting how the handoff failed, since it is this file's own class:** the
blocker was relayed from a scoping note, read as a task ("add the name to the
scan"), and was really a claim ("the scan is where this is decided"). I passed
it on without checking which. One `grep` of the lexer settles it in a line.

### What the third attempt actually changed

| | attempt 2 | attempt 3 |
| --- | --- | --- |
| FAILs | 6 | **2** |
| of those, attributable to the promotion | 4 | **0** |

The four that were ours: two correctness regressions (frankb-8e, `5fccc890a`),
two `test-emit-obj` `t Hidden` control arms (pinned to `--no-dce`, reason
inline), and one wasm32 row (carved out). The remaining two are pre-existing and
independently recorded — see the summary.

### Three things that were believed and turned out false when measured

Recorded together because they are one shape, and two of the three were mine.

1. **"Promoting enacts half the object-model fork."** Mine, reasoned from the
   `-O` rule to a consequence and never measured. `--emit-obj` is
   export-preserving: 323 exports kept, 312 WEAK FUNC, identical name sets, UND
   0, while 269 LOCAL bodies go. Locals were never part of the contract.
2. **"The `--emit-obj` default is refused because `--dce` segfaults GNU ld on an
   IRAM object."** A hazard block in `compiler.pas`. Its ticket was in `done/`
   and all four links come back rc=0. Retired at `ec8ce7192`.
3. **"wasm32 needs a carve-out because the harness reaches bodies by export
   name."** frankb-8e's, written from a prediction. The mechanism was already
   settled in `dce.inc:799` and is deliberate — and the carve-out is right for a
   BETTER reason: a wasm module's exports are how a host consumes it, so
   default-on breaks the target's normal usage, and `--no-dce` on those rows
   would have hidden that.

**All three were safety or consequence claims, and a safety claim is only ever
exercised by someone doing the thing it forbids.** Believing one produces no
signal, which is why all three survived. The general form is in
`debugging-playbook.md`; what belongs here is that a promotion attempt is an
unusually good instrument for finding them, because it is forced to read past
every refusal in its path.
