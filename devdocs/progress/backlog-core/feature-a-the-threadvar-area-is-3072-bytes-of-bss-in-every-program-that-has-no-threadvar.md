---
slug: feature-a-the-threadvar-area-is-3072-bytes-of-bss-in-every-program-that-has-no-threadvar
title: "The threadvar area is 3,072 bytes of bss in every program that declares no threadvar — and it is an x86-64-only cost, ZERO on ESP"
type: feature
track: A
prio: 45
status: new
created: 2026-09-18
owner: ""
summary: "ROUTE C SHIPPED 2026-09-18 — the area is a command-line knob (-dPXX_TLS_USER_0/_1K/_2K/_4K/_8K/_16K, default unchanged at 3072), so `-dPXX_TLS_USER_0` gives the whole 3,072 of bss back to any program with no `threadvar` with no detection at all. Measured on an x86-64 hello, bss 38,396 -> 35,324 at rung 0 and exact at every rung; test_atomic_counter is correct at 0, 1K, 8K and 16K; palthread follows without an edit because it reads __pxxTlsBlockSize. STILL OPEN because the knob is OPT-IN: a program that does not pass the flag still pays 3,072 it may not use. Route A (prescan for the `threadvar` token before EmitTlsMainInstall, `uses` forcing it back on) buys the same bytes without the user asking, and reaches 11 of 49 Pascal files under examples/ — 22%, counted, which is the honest ceiling on it. Route B (size the area from what parsing used) buys it on every program and is the only one that is UNSOUND today: it makes the size vary DURING a compile, which is exactly what the reserve and the __pxxTlsBlockSize fold both capture. The soundness rule, measured both directions: the fold works because TLS_BLOCK_SIZE is a compile-time CONSTANT, not because it is 3072 — at 0 bytes test_atomic_counter still prints 800000/800000 over four threads, and a program that outgrows whatever the cap is gets refused at compile with a diagnostic naming the rung to raise to."
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

## WHERE TO PICK THIS UP (frankS parked it 2026-09-18; nobody holds it)

Route C shipped and is the whole of what is done. **The next step is ROUTE A,
and everything it needs has been measured — it is an afternoon, not an
investigation:**

1. Add a `threadvar` scan to `DetectPascalRuntimeNeeds`
   (`pasparser_prog.inc`), beside the `tkUses`/`tkArray`/`tkClass` rows that are
   already there. Absent -> the area is 0. **`uses` must force it back ON**, for
   the same opacity reason the existing prescan treats imports as opaque: a used
   unit's `threadvar` is not in the main source's token array. Non-Pascal
   frontends have no `threadvar` and can always take 0.
2. Set `TlsUserBytes` from that instead of unconditionally, in
   `ApplyTlsUserBytesOption` (`ir_codegen.inc`) — which already exists, already
   runs at the only correct moment, and is already called from `compiler.pas`
   right before `EmitTlsMainInstall`. **Route C built the ordering route A
   needed; there is no plumbing left to do.** An explicit `-dPXX_TLS_USER_*`
   must still WIN over the scan, or a program whose threadvars live in a used
   unit has no way to ask for room.
3. The knob keeps working unchanged and stays the escape hatch for whatever the
   scan gets wrong. That is the point of doing A second.

**Do not skip the `uses` clause in step 1.** It is the whole difference between
route A being safe and route A silently refusing a correct program: the scan
sees the main source's tokens only, and `palthread` itself declares threadvars.

**Known ceiling, counted, do not re-count:** 11 of 49 Pascal files under
`examples/` have no top-level `uses`, so route A reaches 22% of them. That is
the honest value — decide against it on that number if you want to, rather than
discovering it halfway.

**Route B stays unsound** and needs the fold fixed first; nothing measured today
changes that. See "Route B's blocker" below.

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
