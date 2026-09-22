---
slug: bug-a-a-pascal-hello-world-is-63kb-after-emission-size-dce
title: "feature-emission-size-dce is done, and `WriteLn('hello')` still emits 63,760 bytes"
track: A
prio: 30
type: bug
blocked-by: [bug-a-dce-breaks-every-c-program-on-every-cross-target]
status: backlog
owner: ""
created: 2026-08-25
summary: "THE PROMOTION WAS ATTEMPTED AND ITS PROOF GATE REFUSED IT -- DO NOT SPEND THE MECHANICAL WORK AGAIN (frankh-c0, 2026-09-22). `--dce` was promoted to the default `-O2`, a full tier was run on plexus as the O-lane's PROOF gate, and it came back **RED with 101 hard FAILs** in 2328s. The commit was never pushed and was dropped; the tree is unchanged. The 101 are ONE pre-existing bug and it is now `bug-a-dce-breaks-every-c-program-on-every-cross-target` (p75), which this ticket is `blocked-by`: a seven-line C hello world segfaults under `--dce --target=aarch64` and `arm32` and prints NOTHING with exit 0 on `riscv32`, while PASCAL is fine on the same three targets with the same flag and x86-64 C is fine. It reproduces with the pre-promotion binary asking for `--dce` explicitly, so `-O3` has shipped it since 2026-08-21 and no default is implicated. The five control arms ARE respelled (`311ebde9e`) and a SIXTH was found and fixed the same day -- `c_dce_entry_root` asserted `-O3` smaller than `-O2`, the only one of the six spelled as an -O LEVEL rather than as the default invocation, which is why the grep for the other five missed it. AND ONE CONSTRAINT ON THE RETRY THAT IS NOT A DEFECT AND WILL NOT ARRIVE AS ONE (frankb-8e, 2026-09-22): WASM32 MUST NOT INHERIT THE DEFAULT -- the wasm harness reaches bodies by EXPORT NAME and `--dce` correctly drops an export nothing reaches, so a correct program and a correct pass give a harness that cannot find what it meant to call; those rows would arrive in the same tier run as real failures and read as evidence against the pass. SO THE REMAINING WORK IS NOT MECHANICAL: it is one correctness bug, and when that closes this becomes re-run the tier. PROMISE IS UNCHANGED AND STILL THE REASON TO CARE: -66% over nine real `examples/**` programs, 4,424,828 -> 1,475,708 bytes, self-host fixedpoint converging. EARLIER THE SAME DAY (kept because it is what the promotion needed and all of it still holds): the ESP IRAM object that crashed GNU ld was DCE never compacting `IramCallFix`, fixed and guarded the same day, so the promotion is no longer gated on a correctness bug. WHAT REMAINS IS MECHANICAL PLUS PROOF, and it is the whole of this ticket now: respell FIVE Makefile control arms `--no-dce` (riscv32, i386, xtensa, arm, and the NilPy ESP object row -- each uses the DEFAULT invocation as its \"without the pass\" baseline, which the promotion silently empties; they assert a STRICT shrink so they fail loudly rather than certifying nothing), then run a full tier at `-O2`-with-DCE and expect green with `skip_holes == 0`, which is the O-lane's PROOF gate and is satisfiable on plexus now the corpora are installed. DO NOT TREAT THE MEASURED -66% AS THE PROOF -- it is the PROMISE half only. ORIGINAL ANSWER TO THE QUESTION BELOW (frankh-c0, 2026-09-22): the residue this ticket names -- *whether the DEFAULT -O level should enable the pass* -- was tested by turning it on and probing, and the PROMISE half is enormous: nine real `examples/**` programs go 4,424,828 -> 1,475,708 bytes, **-66%**, and the self-host fixedpoint still converges in two rounds. It cannot land because the `-O` rule is unconditional on OUTPUT MODE, so promoting to `-O2` enables the pass for `--emit-obj` by the back door and a plain no-flags ESP object build then CRASHES GNU ld (linker's own rc=1, `signal 11`; `--no-dce` rc=0). This ticket is therefore wired `blocked-by:` that bug, which was sitting at p60 reading as one broken path under one flag while actually gating a two-thirds size cut on every program. DO NOT RE-TEST THIS BY FLIPPING THE LINE: the probe is recorded in the blocker's body with its populations, and the tree was reverted byte-identical. A second, smaller cost is banked there too -- five Makefile rows use the DEFAULT invocation as their \"without the pass\" control arm, so the promotion silently empties them; they assert a strict shrink and fail loudly, which is the only reason anyone finds out. RE-MEASURED 2026-09-19 (frankS): the headline number is stale IN THE UNFAVOURABLE DIRECTION -- a `WriteLn('hello')` is **74,096 B** at the default -O now, not 63,760, and the ticket has been quoting the smaller figure since 2026-08-25. With `--dce` it is **24,944 B (-66%)**, and `-O3` gives exactly 24,944 too, which is the pass being on at -O3 by the free-tier convention rather than a coincidence. `begin end.` is 74,040 / 24,888, so this is the FLOOR and not the program. So the premise this was raised on -- decide-how-much-string-machinery-the-basic-frontend-gets accepting big binaries because \"binary size is a GENERAL problem with a general answer (reachability-gated emission)\" -- is now DISCHARGED where the pass runs: the general answer exists, works on five of six targets, and takes two thirds off. THE MECHANISM NAMED BELOW IS UNCHANGED and is still the right description: PasApplyDefaults defines PXX_MANAGED_STRING unconditionally, so every Pascal program still PULLS builtinheap whether or not it touches a managed string -- DCE removes the consequence (unreachable bodies) without changing the pull. What is left is therefore not this ticket as written but a narrower question: whether the DEFAULT -O level should enable the pass. That is not free and is not a goal question -- flipping the analogous default for --emit-obj surfaced bug-a-dce-under-emit-obj-crashes-a-two-object-i386-link-before-main, an existing shipping path that dies before main on a two-object i386 link -- so it wants the same per-target evidence, not a flag flip. Original framing kept below."
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
