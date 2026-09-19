---
slug: feature-a-the-threadvar-area-is-3072-bytes-of-bss-in-every-program-that-has-no-threadvar
title: "The threadvar area is 3,072 bytes of bss in every program that declares no threadvar — and it is an x86-64-only cost, ZERO on ESP"
type: feature
track: A
prio: 45
status: new
created: 2026-09-18
owner: ""
summary: "ROUTES C AND A BOTH SHIPPED. A Pascal program naming neither `threadvar` nor `uses` now gets a ZERO-byte threadvar area automatically — hello.pas, the hosted umbrella's floor subject, goes bss 38,396 -> 35,324 with no flag and __pxxTlsBlockSize becomes 1152. On top of that -dPXX_TLS_USER_0/_1K/_2K/_4K/_8K/_16K sets it explicitly and always wins. THE SCAN READS THE SOURCE TEXT, NOT TOKENS, and that is forced: the token array is EMPTY at the only moment the size may be chosen (compiler.pas clears TokCount above ApplyTlsUserBytesOption and every frontend lexes below it), and the call cannot move down because EmitTlsMainInstall bakes the size into the BSS reservation and the fold captures it. Source is include-expanded by then, under IsPascalFrontend, which is why this is Pascal-only. Every way the scan can be wrong costs BYTES, never correctness. The `uses` rule stays because dropping it would REFUSE a program that compiles today — a used unit's threadvar is not in the main source — which caps the reach at unit-free programs, 11 of 49 under examples/, counted and not re-counted. STILL OPEN on two pieces: (1) the other frontends, each a flat -3,072 (a NilPy hello 62,724 -> 59,652, a C hello 72,448 -> 69,376), gated on the fact that isNilPy is true for the whole compilation INCLUDING the Pascal RTL units a NilPy program drags in, so "this frontend has no such keyword" is not the same claim as "this compilation cannot declare one"; (2) route B, still the only unsound route, blocker unchanged. Found on the way and filed separately: bug-a-a-threadvar-in-a-units-implementation-section-silently-reads-zero (p55), which predates all of this and reproduces on the pin."
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

## WHAT IS LEFT (frankS parked it 2026-09-19; nobody holds it)

The ticket stays OPEN on two remaining pieces, in value order:

1. **The other frontends.** NilPy, BASIC, Rust, Zig, Erlang, Ada, Algol,
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
