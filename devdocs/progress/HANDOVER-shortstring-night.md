# Shortstring byte-prefix overhaul — overnight handover (2026-09-02, 21:0x–)

Written by the coordinating session for the owner's morning. **Read this instead
of reconstructing it from ~40 commits.** One screen; detail is in the tickets.

## Where phase 2 stands

**All seven backends converted.** i386 landed last (`c8375f3e7`). Read the count
from `TargetHasByteStrPrefixCodegen` in `compiler/util.inc` — seven rows — **never
from a commit message**; wasm32's own says "STILL OPEN: i386 and xtensa" with
xtensa already in. Verified here with a freshly rebuilt binary: all seven accept
`-dPXX_SHORTSTRING`.

### Do not read that as phase 2 being done

**"Seven of seven" is TRUE about that function's rows and is NOT a claim about
phase 2.** The gap is now larger than when six were in:

- **the walker store-side defect — all seven targets, unfixed**, frankb-a9 sole owner
- **two surviving readers** after the four-cause fix, plus a **fifth cause**
- `p^[1]` reads a blank while `s[1]` and `r.f[1]` read `h` in the same run
- `r.f = 'hello'` **segfaults** on x86-64/riscv32/**i386**, FALSE on aarch64/arm32
  (i386 measured at `c8375f3e7`; it resolves the kind at the decompose and
  crashes anyway, so resolving there is necessary and not sufficient — the field
  case is a third shape rather than either of the two already known)
- compare deliberately unowned; its flag rows deliberately unwired

**Seven converted, ZERO of the three defect classes closed.** Every backend now
emits a one-byte prefix and the shared paths that READ those prefixes are still
wrong on all of them.

### The green light that is not one

`TargetHasByteStrPrefixCodegen`'s own comment says it disappears at phase 4
*"when `string[N]` re-types unconditionally and every backend has been
converted"*. **Every backend has now been converted**, so a reader meeting that
comment in the morning will conclude P4 is ready. **It is not.** frankb-a9's
ready condition is strictly stricter — i386 landed and reviewed against the three
classes, **plus** the two surviving readers and the fifth cause — and it moved
that condition FURTHER AWAY after i386's own review found them. The person who
would know says no.

**Anyone measuring from here needs a rebuild:** frankA's landing is the only
commit in the last fourteen touching `compiler/` or `lib/`, and it touches both.

## The bug that was at least five bugs

Modelled all evening as one shared-walker defect. **It was a CLASS of four
causes** (frankb-a9, `764dc3a30` + `64f230d12`) — a walker-only fix would have
closed one of four:

| # | site | scope |
| --- | --- | --- |
| 1 | `IRFrozenKindOfAddr` — `p^` lowers to a LOAD tagged `tyPointer`, matched neither arm | shared, all 7 |
| 2 | `EmitStrCmpReg` (`symtab.inc:7249`) — signature had no kind at all | x86-64 |
| 3 | arm32 compare callers `:2055 :2095 :2140 :2190` passed `IntToTypeKind` | arm32 |
| 4 | x86-64 `IR_STORE_MEM` — read its dest kind from a stale `symIdx` | x86-64 |

**Verified independently at HEAD, x86-64 under the flag:** `Length(p^) = 5`,
store bytes `1 88 98 99 100 101 0` (FPC's exact bytes), both comparison shapes
TRUE. All four previously wrong.

**TWO READERS SURVIVE THE FIX — phase 2 is NOT all green.** frankh-15's matrix
(`40646620c`) ran before wiring and named them; I reproduced both on x86-64:

```
s[1]    = [h]      r.f[1]  = [h]      p^[1]   = [ ]      <- blank, same run
s=lit   = TRUE     p^=lit  = TRUE     r.f=lit = SEGFAULT
```

- **`p^[1]` reads blank** on all four converted backends, while `s[1]` and
  `r.f[1]` are correct beside it. The index origin follows the width wherever the
  symbol is reachable and **not through a bare pointer whose value IS the buffer
  address** — the same shape that made `Length(p^)` wrong before the fix. Blank
  rather than garbage fits reading at base+8 when chars start at base+1.
- **`r.f = 'hello'` segfaults on x86-64 and riscv32, returns FALSE on aarch64 and
  arm32**, while `s = 'hello'` and `p^ = 'hello'` are green beside it. The compare
  arm now resolves a variable and a deref and **still not a FIELD**. One defect at
  two word sizes: a wrong-width field length is a count in the hundreds of
  millions, which the comparison either walks off or short-circuits on.

**That is a fifth cause, not a remnant of the four.**

**THE TWO SURVIVORS FAIL ON OPPOSITE OPERAND SHAPES — they are two shapes, not
one missing resolution** (frankc-af, corroborated from a second tree):

```
s[1] =[h]      r.f[1] =[h]      p^[1]  =[ ]     <- indexing fails on the DEREF
s=lit  TRUE    p^=lit  TRUE     r.f=lit SEGV    <- comparison fails on the FIELD
```

Indexing handles the variable and the field and fails on the **deref**. Comparison
handles the variable and the deref and fails on the **field**. If they were one
missing resolution they would fail on the same shape.

**And `r.f = 'hello'` SEGFAULTS rather than answering FALSE.** Every other member
of this family tonight failed *generously* — a wrong width gives a length in the
hundreds of millions and the mismatch short-circuits to "no". A segfault means it
is dereferencing something it computed, so it is likely **not** the same mechanism
as the FALSE-answering ones even though it sits on the same arm.
 Both ticketed. The matrix did
exactly what it was built for — it named the readers the fix does not reach.

What separated the layers was **franks-ab's falsifiable prediction** — that the
walker fix would NOT repair comparison. It didn't; comparison needed (2) and (3).

## TWO different "unwired rows" facts — they sound alike and mean opposites

Both phrases appear tonight. **Do not let them merge.**

- **wasm32 (CLOSED, `a322f1552`)** — coverage that was **absent while reading as
  covered**. Its one standing row ran at DEFAULT, the proven no-op path. Nothing
  was withheld; nobody had noticed. Now 26 rows, with a control proving the pair
  is distinguishable.
- **The reader matrix (`40646620c`, OPEN and correct)** — coverage **deliberately
  withheld**, because the rows are known-red on the two surviving readers. That
  session was asked to wire them on the strength of the greens, **ran the matrix
  first, and declined.** Wiring known-red rows paints every lane red and tells
  nobody anything they cannot read in the commit.

The first is a gap. The second is judgement. **Wiring the second is a one-liner
for whoever closes the two survivor tickets** — not a task to hand anyone now.

## Open, with owners

- **i386 — LANDED, `c8375f3e7`.** Six configurations under qemu (byte_prefix
  and mixed_widths at default and `-dPXX_SHORTSTRING`, plus both frozen modes),
  gate GREEN with the FPC canary PASS, self-host converged. Default path proved
  by ISOLATION: only `ir_codegen386.inc` reverted, **10/10 emitted i386 binaries
  byte-identical**, two genuinely different compilers (`4ba5c77aacc7` vs
  `6d8211360923`), positive control **5 of 8 differ in flag mode** so the
  comparison can fail. **Comparison is CORRECT on i386** — `s = 'hello'` is TRUE,
  matching FPC, where x86-64 and arm32 are FALSE; what does it is resolving the
  kind at the `PXXStrEq`/`PXXStrCmp3` **decompose**. (An earlier draft added
  that arm32 still needed this at four call sites — it does not, they read
  `IRStrTkOf` since `764dc3a30`; see the corrected comparison section.)
  Three things that did NOT copy from the 64-bit spec and would bite a copyist:
  the wide prefix is **two stores** on 32-bit; the concat **scratch buffer** must
  KEEP its wide prefix (written unconditionally, returned as a `tyString` value);
  and `lhsTk := IRStrTkOf(...)` breaks the **default** path, not the shortstring
  one, because it resolves `string[8]` to `tyFixedString` with no flag in play —
  the `= tyString` tests had to widen to `TypeIsFrozenString` in the same edit.
  Unrelated i386 bug found while reading and landed separately as `4c44ebb79`:
  `or dword [ecx], 1` emitted where `cmp` was meant (`$83` group-1, ModRM reg=1
  is OR, reg=7 is CMP) — `'a' = s` answered False for every s **and** set bit 0
  of the length prefix. 142 sibling sites swept; exactly one mismatch.
- **Default-path no-op sweep — CLOSED, nothing regressed.** aarch64 CLEAN
  (direct), riscv32 CLEAN (direct), arm32 CLEAN (isolated). Three backends
  upgraded from *asserted* to *proven*, no code touched. arm32's raw
  parent-vs-commit run differed by ~115KB; that is the shared RTL growing
  (`PXXWriteFrozenBW` added to `builtinheap.pas`), demonstrated by compiling an
  untouched target across the same pair — xtensa moved 123936 bytes with the
  blob hash visibly changing.
- **`IntToTypeKind`-where-`IRStrTkOf`-required guard** — frankc-af, Track T.
  Lands green (the violation it fences was just fixed).
- **Reader matrix** — frankh-15, `7d0ef7553`, 28 rows. Flag rows being wired now.
- **Pre-existing, ticketed, none caused by this feature:** `Write(p^)` garbage in
  DEFAULT mode on x86-64 (reproduces **on the pin**); riscv32 missing `SetLength`
  builtin (101) — one builtin, `Pos`/`Copy` compile; wasm32 comparison wrong at
  length 1..8 and `SetLength` trapping (both reproduce on the pin); `r.f = s`
  segfaults riscv32; `Copy(p^,1,3)` OOMs x86-64 under the flag.

## The walker prediction was RUN, and it held — hold released

franks-ab predicted the walker fix would **not** repair comparison. **It did
not.** Comparison was repaired separately, by causes (2) and (3). A prediction
that could have come out either way, and it is what separated the layers.

So the compare ticket's hold (`d23178788`) had done its job and is **released**;
the ticket is closed (`52cefaea2`). Its two prescribed remedies are exactly what
frankb-a9 implemented — `EmitStrCmpReg` gained a type kind on x86-64, arm32's
four callers moved to `IRStrTkOf`. **Re-measured independently** at `c8375f3e7`:
`var=var`, `var=lit` and `lit=var` all TRUE on x86-64, arm32, aarch64 and
riscv32.

**What survives is a different defect, not a remnant** — the record-FIELD operand
and the pointer-deref INDEX fail on *opposite* operand shapes, and are separately
ticketed:
`bug-a-comparing-a-frozen-record-field-to-a-literal-crashes-or-answers-false`
and `bug-a-indexing-a-frozen-string-through-a-pointer-deref-reads-the-wrong-byte`.

One population note that was resolved along the way: **riscv32 IS in the
population.** The "riscv32 refuses the flag" figure was TRUE when measured and
expired when riscv32 was converted — settled by the origin retracting its own
figure, which fails differently, rather than by two sessions agreeing about
backends they had just landed.

## P4 precondition: wasm32 rows — CLEARED (`a322f1552`)

**RESOLVED tonight.** `test-wasm32` is now 26 rows (22 default + 4 shortstring),
re-measured rather than transcribed — two expected strings carry meaningful
trailing spaces, and a `.expected` relayed through chat is where losing one costs
an hour. Verified distinguishable: default binary against the short expectation is
rc=1, short binary rc=0. **The gap it closed was real:**
Rows passing a mode flag: arm32 36, riscv32 31, aarch64 29, xtensa 6, **wasm32 0**.
Its eight configurations were genuinely measured but ad-hoc; nothing holds them.
Its one standing shortstring row runs at **DEFAULT** — by that commit's own
byte-identity proof, exactly the path the change did not touch. **The standing
test covers the proven no-op and none of the conversion.**

Today that is a gap in a path most programs never take. **P4 deletes the flag**,
`string[N]` re-types unconditionally, and wasm32 becomes an unverified DEFAULT.
The window where this is cheap closes at the flip. Owned by frankc-af (owns
`test-wasm32`), rows measured by frankwasm, frankb-a9 on-call fallback.

frankb-a9's own ready-for-P4 condition: **i386 landed and reviewed against the
three classes, PLUS the wasm32 rows wired.** It messages the coordinator at that
point rather than proceeding.

## Comparison against a literal: GREEN EVERYWHERE (corrected)

**`s = 'hello'` answers TRUE on all five runnable targets** — x86-64, i386,
arm32, aarch64, riscv32 — measured together at HEAD with one freshly built
binary. frankb-a9's four-cause fix closed it; nothing is outstanding here.

**CORRECTION, and it was mine.** An earlier version of this section said
comparison was still FALSE on x86-64 and arm32, and offered i386's mechanism as
a ready-to-apply fix shape for arm32's "four call sites passing
`IntToTypeKind`". **Those four sites read `IRStrTkOf` and have since
`764dc3a30`** — which was already an ancestor of the tree I measured i386 on. I
carried a relayed ledger into a written artifact without re-running it against
the tree, while running exactly that probe for my own backend. A reader could
have applied the edit to already-correct code, or concluded arm32 was
unconverted. Caught by frankb-a9; verified here by reading
`ir_codegen_arm32.inc:2049/2085/2126/2184` and by running all five targets.

**The mechanism finding itself stands and is still worth having:** i386's
comparison works because it resolves the operand kind at the
`PXXStrEq`/`PXXStrCmp3` **decompose**, and that is the correct account of the
helper-calling backends. x86-64 genuinely is the different animal — it inlines
through `EmitStrCmpReg`, which is why that one needed a signature change rather
than a substitution.

**It is necessary and NOT sufficient**, which is the useful half now: i386
resolves at the decompose and **still crashes on `r.f = 'hello'`**. So the
surviving field bug is not something a backend got wrong. frankb-a9 measured
the discriminator as HOMOGENEITY of operand shape — `r.f = r.f` is TRUE while
`r.f = s` and `r.f = 'hello'` both crash, symmetric in order — which points at
a clobber or sequencing mismatch between two decompose arms, not at a missing
`IR_FIELD` arm in the walker (`Length(r.f)` = 5 and `r.f[1]` = `h` in the same
binary as the crash). Banked at `ddc4d3d51`, unclaimed.

**And a trap i386 hit that a copyist would not survive:** i386's concat and
compare arms branch on `lhsTk = tyString`. Setting `lhsTk := IRStrTkOf(left)`
breaks the **DEFAULT** path, not the shortstring one — `IRStrTkOf` resolves
`string[8]` to `tyFixedString` with no flag in play, the test goes false, and a
frozen operand falls into the single-character arm. **The tests must widen to
`TypeIsFrozenString` in the same edit.** Two things stay wide by construction: the
concat scratch buffer (written unconditionally, returned as a `tyString` value)
and `Strs[].Offset + 8`, the interned pool.

## The one decision waiting for you

**Why is asking a frozen prefix its width a per-site decision at all?**

Three sites carry a comment telling the next author not to read the width from
`IntToTypeKind` — **cited by construct, never by line**: `IREmitNodeAarch64`,
`EmitFrozenStoreRISCV32`, `EmitArm32StringParts` — **and arm32 violated its own
comment at four call sites.** `IRStrTkOf`'s docstring already
prescribes the remedy verbatim. The fix was designed, named, documented and
applied on aarch64; arm32's sites never got it.

Two is a smell, three is a design flaw. **A comment is not a mechanism.** This
is a normalisation decision, deliberately not taken unattended.

**P3 and the phase-4 flip were NOT started.** frankb-a9 is holding at the
phase-2 boundary; the coordinator is holding a quiet tree. The flip re-types
every string in the compiler and is judged against the tree it lands on — it is
yours to release.

## Method notes worth more than the fixes

- **Liveness is not coverage.** A positive control proves an assertion can detect
  a defect it MEETS; it says nothing about whether it meets one. Three sessions
  hit this in one evening, all careful.
- **A relation between two things that can fail TOGETHER is not a guard.**
  frankh-15's "deref store writes the same bytes as a direct store" passes while
  the slot is corrupt. Remedy: DERIVE the width (`SizeOf` minus capacity) and
  assert byte positions absolutely, staying target-independent.
- **A partition is evidence that causes differ, never evidence of what they are.**
  Cost us a wrong single-cause model that three sessions "corroborated" — all
  three were readings of one inference.
- **The census counted WRITERS.** Comparison and `SetLength` are READERS and were
  in nobody's count.
- **What runs a rule?** Six stated rules did not fire tonight across six sessions
  with CLAUDE.md loaded; the one that fired was a mechanical step inside a build
  procedure. Where the answer is "the reader, if they remember", expect it to
  miss — the moment you reach for an instrument is the moment you are confident,
  and confidence is the state the rule exists to interrupt.
- **A control must VARY the thing it controls for, and say in advance what it
  prints if you are WRONG.** Two controls tonight had the same description —
  "compile an untouched target" — and opposite evidentiary value. The vacuous one
  held both arms at the same commit, so it printed IDENTICAL whether the
  explanation was true or false, *and the script echoed the conclusion as if it
  were a result*. The real one varied the commit and printed DIFFERS with the
  changed blob hash. **Never let a script echo a conclusion.**
- **Row ordering is a HARNESS property, not one file's quirk.** A row that ends
  the process costs every row behind it, so **a crashing test reports LESS the
  worse the state is** — backwards from what a diagnostic should do. Re-check it
  whenever a fix moves which row crashes; it already moved once (first killer was
  `assign from field`, now `compare field to literal`), and that single row is
  currently hiding the verdict of eleven rows behind it on two backends.
- **Cite by CONSTRUCT, not by line.** Two of the three line numbers this document
  originally carried had already drifted within the same evening — arm32's onto a
  procedure header. **A stale line number does not error; it points somewhere.**
- **A population figure needs a DATE, or it keeps answering about the tree it was
  taken on.** "riscv32 refuses the flag" was TRUE when measured and became false
  when riscv32 was converted — an **expired** measurement, not a wrong one, and
  the more dangerous kind: the quoted diagnostic is a real string the compiler
  once printed, so nothing about it ever comes to look false.
- **A clean tree one commit ahead is the signature of a session BETWEEN commit and
  push**, not of stranded work. Sampled in that gap twice tonight; ref-level
  checks (`merge-base --is-ancestor`, `ls-tree origin/master`) are the discriminator.
- **A control can be vacuous because your work is STAGED.** frankA's first
  isolation attempt had the diff staged, so `git diff` came back empty and
  `git checkout --` restored from the *index* — both arms identical by
  construction, and it would have printed a clean 11/11. **Two tells, both
  present: a zero-line patch, and both rebuilds printing `verified` instead of
  `converged`.** Third vacuous control caught tonight, each by a different session.
