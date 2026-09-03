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
- ~~two surviving readers~~ — **BOTH CLOSED at `0dd5858e6`** (frankb-a9, 22:01),
  one commit, one shared cause. Verified independently at `51b80e55b`; see
  "BOTH SURVIVORS ARE CLOSED" below for the rebuilt-binary measurement and the
  eleven-row widening. **x86-64 only** — the cross-target rows below were
  measured before the fix and have NOT been re-run.
- compare deliberately unowned; its flag rows deliberately unwired

**Seven converted; the reader classes are closed on x86-64 and unmeasured
elsewhere.** Every backend emits a one-byte prefix. What is left is the walker
store-side defect and the phase-4 flip, which is the owner's to release.

**DONE — five targets measured, all green.** x86-64 and i386 natively, arm32 /
aarch64 / riscv32 under qemu (all four qemu binaries are installed on plexus;
this cost about a minute and did not need anyone's permission):

| target | how run | six-row repro | negative control |
| --- | --- | --- | --- |
| x86-64 | native | exit 0, all correct | `r.f='nope'` FALSE |
| i386 | native | exit 0, all correct | FALSE |
| arm32 | qemu-arm | exit 0, all correct | FALSE |
| aarch64 | qemu-aarch64 | exit 0, all correct | FALSE |
| riscv32 | qemu-riscv32 | exit 0, all correct | FALSE |

**i386 is the row that matters** — it is the one this file recorded as
segfaulting, and the native-only blind spot in CLAUDE.md is exactly that a
32-bit width bug cannot fail an x86-64 loop.

**Each row carries its own positive control and an identity check.** "All TRUE
on every target" is also what a harness prints when it is not running anything,
so every cross row ran the eleven-row program whose `r.f = 'nope'` must come
back FALSE, and `file` was read for the actual machine (`ARM`, `UCB RISC-V`,
`Intel i386`) rather than trusting the `--target` flag I passed in.

**NOT measured: wasm32 and xtensa.** No runtime invoked for either, so they are
blank, not green — the phase-4 flip should not read this table as seven.

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

> **CORRECTION 2026-09-03 (frankc-af, whose claim this was): BOTH SURVIVORS
> ARE FIXED. The section below is superseded and is kept only as the record of
> what was believed overnight — do not act on it.**
>
> Re-measured at `482b714d0` after a rebuild (`converged after 1 round(s)`), on
> every converted backend, under `-dPXX_SHORTSTRING`:
>
> ```
>              s[1]   r.f[1]   p^[1]    s=lit   p^=lit   r.f=lit    rc
> x86-64        h       h        h       TRUE    TRUE     TRUE       0
> arm32         h       h        h       TRUE    TRUE     TRUE       0
> aarch64       h       h        h       TRUE    TRUE     TRUE       0
> riscv32       h       h        h       TRUE    TRUE     TRUE       0
> ```
>
> Both were already ticketed and closed, and both fixes are ancestors of HEAD:
> `0dd5858e6` (`IRLowerAddress` took the index origin from the base node's
> generic `tyString` instead of `PtrElemTk` on the pointer's own symbol — that
> ticket also records a WRITE half found by its positive control, where
> `p^[1] := 'H'` stored at base+8 and was silently discarded) and `ba90811d3`
> (the field was value-loaded where an address was wanted, plus two compare
> guards spelled `= tyString` where they meant `TypeIsFrozenString`, plus
> `CmpFusible` fusing the field-vs-field row into a scalar address compare —
> correct at `-O0` and FALSE at `-O1+`, which is why `-O0` hid it).
>
> **The claim was EXPIRED, not wrong.** It was measured at `764dc3a30`, which
> is the exact commit `0dd5858e6`'s own summary cites as where the symptom
> reproduced; the fixes landed after, and it was reported as a current
> reproduction without checking. **This is the failure mode this very document
> is about**, committed by the person who supplied its sharpest example: the
> quoted failing output was real output from a real compiler, so nothing about
> it ever comes to look false, and only re-measuring catches it. It was caught
> because a human asked whether a ticket was wanted.
>
> The "opposite operand shapes" observation was also **not new** — `0dd5858e6`'s
> summary already records `s[1]` and `r.f[1]` reading `h` while `p^[1]` blanks
> in the same run. And the segfault-vs-FALSE split it flagged as "probably a
> different mechanism" is explained by `ba90811d3`'s `-O0`/`-O1+` split, on the
> same arm rather than a separate one.
>
> **Phase 2 has no known surviving readers.** i386 remains the open backend.

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
  comparison can fail. **Comparison against a literal is GREEN on all five runnable
  targets** — x86-64, i386, arm32, aarch64, riscv32 — re-measured with one fresh
  binary. i386 gets there by resolving the kind at the `PXXStrEq`/`PXXStrCmp3`
  **decompose**, which is **necessary and NOT sufficient**: i386 resolves there
  and *still* crashes on `r.f = 'hello'`. (An earlier draft of this document said
  x86-64 and arm32 were still FALSE and that arm32 passed `IntToTypeKind` at four
  call sites. Both halves were stale — those sites read `IRStrTkOf` since
  `764dc3a30`. The correction originally sat *beside* the false sentence instead
  of replacing it, which is the same failure one rung down.)
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

**What survived was ONE defect, not two — see the section below, which supersedes
this paragraph.** At the time it read as two: the record-FIELD operand and the
pointer-deref INDEX failed on *opposite* operand shapes, and were separately
ticketed:
`bug-a-comparing-a-frozen-record-field-to-a-literal-crashes-or-answers-false`
and `bug-a-indexing-a-frozen-string-through-a-pointer-deref-reads-the-wrong-byte`.

### RETRACTED: my "both survivors closed on five targets" measurement

**I never passed `-dPXX_SHORTSTRING`.** My command was
`./compiler/pascal26 surv.pas surv` — positional output, freshly built binary, a
real run that really passed. It measured the **default 8-byte-prefix path, which
was never broken**, and I reported it as the byte-prefix path this entire
overhaul is about. **The five-target table is withdrawn, not repaired**: none of
those rows exercised the flag.

**This is worse than a broken instrument, and it is the finding to keep.** That
harness had a positive control, a negative control that returned FALSE, a
`file(1)` architecture check and five targets. **Every guard passed honestly** —
all of them were aimed at a configuration nobody was arguing about. CLAUDE.md
asks "would this row still pass if the machinery did nothing"; the missing
question is **"does this row exercise the CONFIGURATION my claim is about"**. A
guard cannot tell you that you asked the wrong question. frankb-a9 and I got
opposite results at the identical compiler sha `a09992a1c33f` and **neither
harness was faulty** — a correct harness faithfully ran the wrong mode.

**Any claim about this overhaul that does not name the mode it was measured in
is not a claim about this overhaul.**

### The survivors ARE closed — on frankb-a9's evidence, at `ba90811d3`

Four causes, one sentence: **a guard spelled `= tyString` where it meant
`TypeIsFrozenString`.** (1) `ir.inc`'s AN_FIELD rvalue arm value-loaded a frozen
field — eight bytes of the string AS its value, `rax = $6F6C6C656805` at the
fault. (2) the x86-64 and aarch64/arm32 compare guards, in two spellings.
(3) **`CmpFusible`, the one worth keeping.**

**`-O0` correct while `-O1+` is wrong says the unwidened predicate is in the
OPTIMISER, not in the arm you are reading.** After the value-load and both
compare guards were fixed, x86-64 *still* answered FALSE at `-O1`/`-O2` and
correctly at `-O0`: the optimiser predicate excluding float/string/variant from
`cmp`+`setcc` fusion spelled the string half as a bare equality, so a
`tyShortString` operand got fused and the two field **addresses** were compared
as integers. By then nothing in the compare path looked wrong, because nothing
in it was.

**The widths were right the whole time** — `lea 0x1(%rax)` for the field against
`lea 0x8(%rcx)` for the literal. This read as a width bug for a day and never
was one.

**Three theories died on this bug in one hour, each refuted by a single program,
each having looked confirmed by source-reading first. The fourth attempt read
the registers at the fault and took one command.** A theory the code confirms is
not thereby measured. That is a repeatable failure mode of source-reading, not a
curiosity.

**The deref write side is real and the slug undersells it.** With the fix
reverted: the program prints `read [^@^@^@]` *and then* `write [hello]` — the
store went to base+8, landed inside the slot, corrupted nothing visible, and
**the assignment was silently discarded.** `p^[1] := 'H'` doing nothing is the
part a user meets. Silent corruption, not a display bug. The positive control
found it; the repro did not.

Verified by me in BOTH modes at `ba90811d3` / `a81084690bac`: six rows correct,
exit 0, default and `-dPXX_SHORTSTRING` alike.

### FLIP BLOCKER #2, and it is the bigger one: concat segfaults on x86-64

`bug-a-string-concat-segfaults-on-x86-64-under-the-byte-prefix-mode`
(`335a5604e`, prio 85). No array, no record, no pointer, no index — six lines:

```pascal
var s: string[10];
s := 'ab';                 { before: len=2 [ab], correct }
s := s + 'cd';             { SIGSEGV under -dPXX_SHORTSTRING }
```

| target | default | `-dPXX_SHORTSTRING` |
| --- | --- | --- |
| **x86-64** | `[abcd]` | **SIGSEGV (139)** |
| i386 / arm32 / aarch64 / riscv32 | `[abcd]` | `[abcd]` |

**x86-64 is the ONLY broken target** — the inverse of the shape we fought all
night, and it is the default target: the dev loop's, `gate.sh quick`'s, and the
first one the flip meets. `-O` invariant. In a longer program the same statement
died as `out of memory (heap arena mmap failed)`, exit 203, instead of SIGSEGV.

**HOW IT WAS MISSED IS THE FINDING.** Concat is exercised constantly — **only in
the default mode.** The overhaul's own repros are string *comparison* and
*indexing*, so **the commonest string operation in Pascal was never in the
population.** frankb-a9's 17/17 could not have caught it: that is a gap in what
was ASKED, not in how well it was asked. **Nothing sweeps `-dPXX_SHORTSTRING`
broadly, and until tonight nobody had diffed the two modes over ordinary
constructs.** The two blockers below and above both came out of one such sweep,
in about ten minutes.

**The generalisation for the flip: a mode that is only ever exercised by the
repros written to test it has been tested against its own authors' hypotheses.**

### FLIP BLOCKER: arrays of shortstrings are corrupt under the flag

`bug-a-an-array-of-shortstrings-is-corrupt-under-the-byte-prefix-mode`
(`bb04bd580`, backlog-core, prio 80). Measured at `ba90811d3`, exit 0 both modes:

| | default | `-dPXX_SHORTSTRING` |
| --- | --- | --- |
| `a[0]` (`string[8]`) | len=4 `[zero]` | len=4 **`[z  ]`** |
| `b[0]` (`string[4]`) | len=2 `[ab]` | **len=2199023255554** |
| `b[1]` | len=2 `[cd]` | **len=72057594037927938** |
| `a[1]='one'` | TRUE | **FALSE** |

`0x20000000002` and `0x100000000000002` both end in the real length 2, with
neighbouring bytes dragged into a 64-bit load; the narrower declared width
corrupts harder, which is what an element-stride disagreement looks like. **A
`Length()` of 7.2e16 is an overrun, not a display defect** — and the flip turns
this mode on globally.

**Direct evidence of the mechanism, which plain output hid:** under `cat -v`,
`a[0]` reads **`[z^C^@^@]`** — the byte after `z` is `0x03`, which is **the
length of `a[1]` (`'one'`)**. `a[1]`'s prefix is sitting inside `a[0]`'s data:
a stride overlap, visible without a debugger. Printed normally that byte looks
like whitespace, which is why it read as "padding" for an hour.

**Two guard traps in it:** `a[2]` reads CORRECTLY, so a probe checking the last
element passes; `a[0]` reports the RIGHT length beside corrupt data, so a probe
asserting `Length` passes. It surfaced from a widened repro's negative-control
row, not from the repro's own assertions.

**Narrowed at `4def5ca66` — measurement only, frankb-a9's files untouched.**
Byte-identical at `-O0` through `-O3`, so this is a layout/codegen arm and **not**
an optimiser predicate; the `CmpFusible` tell does not fire here. Default mode at
`-O2` on the same harness gives the right answer, so the rows are live.

**And a third trap, the worst of the three.** `2199023255554` is `0x20000000002`,
whose **low 32 bits are exactly 2** — the correct length. So x86-64 and aarch64
report the garbage while **i386, arm32 and riscv32 report `len=2` and look
clean**, with `a[1] = 'one'` still FALSE on all five. A `Length()` probe passes
on three targets with the bug fully present, **on exactly the targets where
anyone hunting a width bug would look first.** Assert the VALUE, never the
length.

The register-width reading of that constant is the obvious explanation and is
**deliberately not in the ticket as a diagnosis** — nobody has read the emitted
load. It is where to point gdb, nothing more.

## BOTH SURVIVORS ARE CLOSED (`0dd5858e6`, frankb-a9, 22:01)

**One commit, 38 lines across `compiler/ir.inc` and `compiler/symtab.inc`, closed
both.** They were never two defects — frankb-a9's `ddc4d3d51` had already said the
field compare *"is not a kind bug"*, and the shared cause is why the two failed on
opposite operand shapes. **The "opposite shapes therefore two mechanisms"
inference in the sections above was wrong**, and it is left standing there
deliberately: it was the reasoning that split the work, and it reads as sound.

**Measured independently, not taken from the author.** Rebuilt at `51b80e55b`
(`converged after 1 round(s)` — the recompute verb, not the stamp), compiler
sha `a09992a1c33f`:

```
s[1]=[h]   r.f[1]=[h]   p^[1]=[h]      <- the deref index, was blank
s=lit TRUE  p^=lit TRUE  r.f=lit TRUE  <- the field compare, was exit 139
```

Widened to eleven rows — deref-to-record-field index `q^.f[1]`, array element
index, `Length(q^.f)` = 5, and **a negative control: `r.f = 'nope'` returns
FALSE**, so the compare is not stuck-TRUE. Exit 0.

**Read `Length` = 5 as the probe that could have failed and didn't.** 5 is not
the old 8-byte prefix, not a type default and not a pointer width — an expected
value that collides with the failure value would have certified nothing.

**A measurement I reported earlier tonight was vacuous, and this is how.** I ran
the repro with `-o`, which pxx does not accept — it takes the output path
POSITIONALLY. The compiler said so and exited 1. A `surv` binary from an earlier
compile in the same scratchpad was still on disk, so it **ran, printed, and
segfaulted**, and I read `exit 139` off a tree that no longer existed. Compile
failure and stale success are not distinguishable downstream: the run produced
plausible, formatted, WRONG output. **Assert that the binary was rebuilt this
minute, and branch on the compile's rc — `[ $rc -eq 0 ] || exit`, not a bare
`;`.** The `rm -f` before the compile is the part that makes the assert real.

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

Two is a smell, three is a design flaw. **A comment is not a mechanism.**

### The fork, and what changed under it tonight

**Every defect found tonight is the same sentence: a reader did not ask the
prefix its width.** Five causes fixed, two survivors still open, and they arrive
in shapes that share no identifier — `IntToTypeKind` at a compare callsite, a
missing kind in a signature, a stale `symIdx`, a bare `+ 8`, an offset-0 load
treated as a low word. **frankb-a9's own account of the real exposure is that
most of them contain no helper name at all**, which is why no grep found them and
why five sessions each hit a different one.

**Option A — fence the spelling.** frankc-af landed a Track T check tonight
(`43c31eff0`) that mechanically catches `IntToTypeKind` where `IRStrTkOf` is
required. It goes green, and it would have caught arm32's four sites. **Cheap,
already done, and it fences one spelling of the mistake.**

**Option B — remove the question.** Make the IR owe its callers a resolved kind,
so a reader cannot get a width without asking for one. `IRStrTkOf` already exists
and its docstring already prescribes exactly this; the gap is that asking it
remains optional at every site.

**My read, and frankb-a9 is the one who would actually know: A does not close
this.** The guard fences the spelling that has already been fixed everywhere it
occurs, while the defects that are still open contain no such spelling. A check
that catches the shape of last night's bug is worth having and is not the same as
a mechanism. **Two is a smell, three is a design flaw — this is at five plus two,
found in one evening, by sessions actively hunting it.**

Not taken unattended, because B is a normalisation across seven backends and the
IR, and that is the shape of change this file says lands as a whole or not at all.

**P3 and the phase-4 flip were NOT started.** frankb-a9 is holding at the
phase-2 boundary; the coordinator is holding a quiet tree. The flip re-types
every string in the compiler and is judged against the tree it lands on — it is
yours to release.

## Method notes

Twenty findings — every instrument that misled tonight was **correct about
something else**, none errored — are in
**`devdocs/dev/instruments-that-answer-the-wrong-question.md`**. They are worth
reading when you next write a guard, a control or a summary; **none of them
blocks anything, so they are not on this page.** The two that bear directly on
the decision above:

- **Nothing runs a label.** A rule fires when something executes it; there is no
  check for *"is the reason you gave the reason that is true"*. Three correct
  decisions carried wrong reasons tonight and every one was caught by a peer,
  never by the author.
- **Fitting the distribution earns a discriminating run, not a promotion.** The
  walker theory predicted the surviving field bug's split exactly and was still
  wrong.

## Ready-to-dispatch slices (coordinator, 2026-09-03 08:1x)

**14 open byte-prefix tickets.** The owner asked why one session was doing this
work while eleven sat idle — a fair hit, and the answer is that the two-mode
sweep is embarrassingly parallel and was never routed. These slices are
**non-overlapping by FILE and by TOPIC**, which is the only division that
matters; git merges files, it does not merge two agents on one question.

| # | slice | files | collides with |
| --- | --- | --- | --- |
| 1 | **concat**, x86-64 managed arm | builtin concat path | frankb-a9 — it diagnosed this and stopped deliberately; **hand over, do not race** |
| 2 | **ordering `<` `>` `<=` `>=`**, x86-64 | the ordering compare path | **frankb-a9 — DO NOT SPLIT OUT.** Same address-comparison shape as `CmpFusible`, which it holds. Almost certainly one cause |
| 3 | **`const` param arrives NUL**, all targets | param passing / reference deref | none known — clean slice |
| 4 | **wasm32 pair** — `setlength traps`, `comparison wrong at every length` | wasm32 backend | none — clean, and wasm32 is unmeasured in every table here |
| 5 | **riscv32 `SetLength` unsupported** | riscv32 backend | none — clean |
| 6 | **pointer/deref group (4 tickets)** — store loses capacity, deref prints blanks, typed-pointer write prints garbage, deref index | shared read/write paths | **one owner for all four** — they smell like one cause; `normalise-dont-special-case` |
| 7 | **extend the two-mode sweep** | none — writes only probes | **zero collision risk, any number of sessions** |

**Slice 7 is the one to hand out first and widest.** It found three of tonight's
four blockers in about twenty minutes, it edits nothing, and it is the only slice
where two sessions cannot get in each other's way. The probes live in this
session's scratchpad and are trivially rebuilt from the tickets' repros.

**The rule that makes slice 7 work, and it is the night's main lesson:** run
every probe in BOTH modes and diff, and read output through `cat -v` — three of
the four blockers print as blanks, padding, or an empty field in a terminal, and
one of them (`const` param) is five NUL bytes that look like nothing at all.

**Sequencing:** only slices 1 and 2 serialise, and both belong to frankb-a9.
3 through 7 are independent of each other and of frankb-a9.

## 2026-09-03 — the suite is clean, and that is NOT "done"

20-probe both-modes sweep at `50bb77aea`, compiler `2f9096bb2bd4`:

| target | built | divergences |
| --- | --- | --- |
| x86-64 | 20/20 | **0** |
| i386 | 20/20 | **0** |
| arm32 | 20/20 | **0** |
| aarch64 | 20/20 | **0** |
| riscv32 | 19/20 | 1 — `SetLength`, known ticket, compile-time refusal |

**And the flip is still blocked on all seven targets** by
`bug-a-a-frozen-record-field-is-refused-by-overload-resolution-against-an-ansistring-parameter`
(`44a61dfc9`, prio 90). **The suite scores 20/20 without touching that
construct.** A clean sweep is evidence about the constructs in the sweep and
nothing else — the same shape as every other lesson in this file, one level up:
the guard is now aimed at the right MODE and still does not cover the whole
LANGUAGE.

### THE PIN IS USELESS AS A CONTROL FOR THIS FAMILY (frankb-78)

**`stable_linux_amd64/default/pinned` predates the byte-prefix layout, so
`-dPXX_SHORTSTRING` is a NO-OP in it.** Under the flag it prints the WIDE layout
(`test_shortstring_byte_prefix` gives `5 0 0 0 0 0`), and it passes every row of
a new byte-prefix test while proving nothing.

**Anyone verifying a byte-prefix fix "against the pinned control" has verified
nothing.** It is CLAUDE.md's *"a green that is correct about a different
compiler"* wearing a new hat, and it is the second time the pin has done this in
three days — the first was the C `__GNUC__` case.

**The control that works is the fix REVERTED and rebuilt**, then restored and
checked byte-identical so the revert cycle drifted no seed. frankb-78 did
exactly that: `7f95d3b1c5c2` SIGSEGVs with default rows unchanged, restored to
`6a01584e19b4` byte-identical.

### "NOT ON THIS PATH" IS NOT "DEAD" (frankb-78)

Concat was **three** arms, not one, all keyed on a bare `= tyString`:
the managed arm (the SIGSEGV), `EmitAnsiStrAppendToSym` behind `m := m + s`, and
the inline frozen-concat arm.

Two things to carry:

**A crash-only assertion would have certified arm 2 as fixed.** Its symptom was
the heap-arena OOM this file recorded as *"probably the same fault"* as the
SIGSEGV — **same cause, different arm**, and fixing the managed arm alone left
it live.

**And the inline arm was banked as unreachable, which was half true.** It is
unreachable from the repro and from `{$H-}` — and `-uPXX_MANAGED_STRING
-dPXX_SHORTSTRING` reaches it, where `u := s + t` over three `string[10]`s
segfaults. The revert was right about the path and **wrong about reachability**,
and the coordinator relayed it onward as settled fact. *Not on this path* must
never travel as *dead*.

## The family, named (frankb-78) — and a census that nearly lied

**The generalisable form: a guard that ENUMERATES KINDS where the concept has
several.** Four independent instances in one day, three of them x86-64-only:

1. concat — three arms, each `= tyString`
2. the call-argument conversion — five sites, `IntToTypeKind(...) = tyString`
3. i386 `IR_WRITE` — the last bare `tk = tyString` in any backend
4. the `-O1` imm-fold arm — excluded float and `tyAnsiString` results, and a
   concat also results in a FROZEN `tyString`. **Two string result kinds, one of
   them named.** Its own comment said *"Excludes float / tyAnsiString results
   (concat + ucomisd paths)"* — it knew about the concat path and enumerated
   half of it.

**The grep that finds them is `= tyString` / `= tyAnsiString` in a width- or
path-SELECTING position** — not `IntToTypeKind` alone, which is what the
existing Track T guard keys on.

### `-O` INVARIANCE IS A CLAIM, NOT A PROPERTY

The concat ticket recorded *"-O invariant, so the `CmpFusible` tell does not
fire"*. **True for that SIGSEGV and the wrong prior for the bug in the same file,
in the same expression, in the same session** — the imm-fold defect is `-O0`
correct and `-O1`/`-O2`/`-O3` wrong. frankb-78 had not varied `-O` when it filed
that ticket and had already written a plausible cause into the summary.
**Vary `-O` before recording a cause, even when the neighbouring bug was `-O`
invariant.**

### The census, and how it nearly produced a false structural finding

Predicate calls vs. kind-equality tests, per backend:

| backend | predicate | `= tyString`/`= tyAnsiString` |
| --- | --- | --- |
| x86-64 `ir_codegen.inc` | 71 | 76 |
| i386 | 60 | 41 |
| aarch64 | 44 | 38 |
| xtensa | 44 | 25 |
| arm32 | 40 | 36 |
| riscv32 | 38 | 26 |
| wasm32 | 22 | 16 |

**x86-64 has the lowest predicate-to-equality ratio (0.93; every other backend
is 1.1–1.8).** That is CONSISTENT with three of four instances being
x86-64-only. It is a weak signal and not a defect count — most of the 664
tree-wide equality tests are ordinary parser type checks, not width selection.

**The near-miss is the part worth keeping.** The first run of this census piped
`grep -c` through `head -10`, which cut `ir_codegen.inc` and `ir_codegen386.inc`
off the list — and the coordinator read that absence as ZERO and was one step
from recording *"the x86-64 and i386 backends never adopted the predicate"* as a
structural explanation. It is a tidy, plausible story that explains the observed
clustering, and it is false. **`head` does not error; it answers.** Committed
while measuring the very family of instruments-that-answer-a-different-question.

## An ordering rule, from a fix that was correct and had to WAIT (frankb-78)

`44a61dfc9`'s fix is written and verified on all seven targets and is being
**deliberately held**, because franka-29's ladder must land first. The reason is
measured, not prudential:

```pascal
type TArr = array[0..2] of string[10];
procedure ShowA(const q: AnsiString);
a[1] := 'elem';  ShowA(a[1]);
```

**Refused today.** With the widening it compiles — and in the
`-uPXX_MANAGED_STRING -dPXX_SHORTSTRING` corner prints sixteen NULs, then a WIDE
length word of 4, then `elem`: the handle points **22 bytes before** the real
prefix. `WriteLn(a[1])`, `m := a[1]` and a frozen `string[10]` parameter are all
correct in the same program and the same corner. Only the frozen→managed
ARGUMENT conversion is wrong — franka-29's ladder, reached by a route nothing
could call before.

### THE HONEST-REFUSAL PROPERTY IS A RANKING FACT, NOT A CONSOLATION

This file praised `44a61dfc9` for declining rather than emitting something wrong.
**That is precisely why fixing it in the wrong order would be worse than leaving
it**: the refusal is the only thing currently stopping a silent wrong value on a
path with no test.

**A fix that converts a loud failure into a quiet one is a regression in
observability even when it is progress in capability.** The rule that falls out:
**when a refusal is the only guard over an untested path, fix the path first.**

### `grep -c | head` REPORTS NOTHING, NOT ZERO (frankb-78, on my error)

Absence from a truncated list is indistinguishable from a zero count, and that
is how *"the x86-64 and i386 backends never adopted the predicate"* nearly got
recorded as the structural explanation for the clustering. Same family as
CLAUDE.md's `ls devdocs/progress/*/` glob: **the instrument answered a different
question and did not error.**

**The tell that was available: a file you KNOW is 12k lines of backend code was
missing from a list of backend files.** Absence of an expected member is the
check, not the count.

### NORMALISING CAN ERASE THE THING IT NORMALISES (frankb-78, open)

`Show(s + r.f)` — a record FIELD as a concat operand — dies with the heap-arena
OOM under the flag. `pasparser_expr.inc` normalises frozen concat operands by
retagging them `tyString`, which is **correct for a VARIABLE** (`IRFrozenKindOfAddr`
walks back to the symbol) and **erases the width for a FIELD** (there is nothing
to walk back to — the node's own tag WAS the width).

**The same normalisation that fixed one bug created another one node type over.**
`normalise-dont-special-case` says share the path; it does not say the shared
tag may be lossy. **Normalise onto a representation that still carries what the
callee needs to know**, or the second path is broken in a new way instead of the
old one.

## The family note, SHARPENED — kinds were one axis of two (frankb-78)

The note above says the defect is *"a guard that ENUMERATES KINDS where the
concept has several"*. **That is necessary and not sufficient, and the grep that
goes with it finds only half the family.**

**The invariant is: A FACT THAT LIVES IN N PLACES WAS ASKED OF ONE OF THEM.**

| instance | what was enumerated | axis |
| --- | --- | --- |
| `TypesCompatible` | one of three kinds | kind |
| the `-O1` imm-fold arm | one of two result kinds | kind |
| `IRFrozenKindOfAddr` | no arm for a field | **entity** |
| `ASTFrozenArgTk` | one of three places a width is recorded | **entity** |
| `IR_ARG` at 17 sites | the AST's type, not the lowered value's | **entity** |
| the AN_INDEX arm | a comment claiming a sibling AN_FIELD arm **never written** | **entity** |

**A `= tyString` grep does not find the entity gaps** — there is no kind name to
grep. What finds them is asking, of any width-reading function: **"which
spellings of this value reach here, and does each carry the fact by the same
route?"** The symbol, `RecFieldType`, and an array symbol's own `TypeKind` are
three different routes to one fact.

### The hold produced a defect nobody predicted — that is why the rule is right

`-uPXX_MANAGED_STRING` makes `AnsiString` ITSELF frozen, so a `string[10]`
argument to `Show(const a: AnsiString)` is a frozen→frozen WIDTH mismatch that
**never reaches the conversion at all**. `ASTFrozenArgTk` had one arm (AN_IDENT);
`ASTTk` for `a[i]` is the generic `tyString`, which EQUALS the frozen formal, so
no mismatch was seen and no copy emitted — a 1-byte-prefixed element handed to a
callee reading an 8-byte prefix.

**Neither session could have found it alone.** franka-29 could not reach that
corner (`Pos`/`Copy` does not compile under `-u`, at the pin, unrelated to
either); frankb-78 could not reach it without its own fix. **The ordering is
what turned a hand-off into a measurement instead of a merge.**

And frankb-78's own correction, which is the expensive half: it first reported
that corner as *"the frozen→managed conversion is wrong"*. **The conversion was
never entered.** It read a wrong value at a call site and named the mechanism it
expected rather than the one it had measured — right about the symptom, wrong
about the owner, which is what misroutes work when handing it over.

### Coordinator near-miss: absence read as a compile FAILURE

Verifying the gate, a probe reported `overload=N` on five targets in BOTH modes
— including default, where it had compiled an hour earlier. That reads exactly
like a five-target regression from the fix just landed. **The file was not
there**: it lived in a different scratchpad directory, and pxx said so plainly
(`cannot read input file`) while the harness collapsed the result to `Y/N`,
which cannot distinguish *refused* from *absent*.

**Third time in two days this session has read an absence as a measurement**
(`head`-truncated list as a zero count; a glob over all folders; now a missing
file as a compile refusal). **The fix is never a better eye — it is to make the
harness assert the input EXISTS before it reports on the output.**

## The shortstring axis is clean (frankb-78, `a3c26785f`)

`SetLength` closed on riscv32 **and xtensa**. Five shapes × seven targets × both
modes, positive control by reverting the arms.

### THE TICKET WAS FILED riscv32-ONLY AND THE DEFECT WAS WIDER

Two backends refused the identical builtin with completely different strings,
**neither of which names `SetLength`**:

```
riscv32  standard builtin calls not supported in bare-metal stage 1 (builtin id 101)
xtensa   this builtin has no arm in the xtensa backend (builtin -101)
```

**The riscv32 message blames a bare-metal stage-1 restriction THAT DOES NOT
EXIST** — `Pos` and `Copy` are builtins too and compile there. Both backends
already had the `-102` arm (dynamic array / managed AnsiString), **which is
exactly why one missing arm read as target POLICY rather than as a gap.** A
plausible-sounding refusal is a worse instrument than a crash: it explains
itself, and the explanation was wrong.

**Read a refusal's REASON as a claim needing its own check.** Two of this
session's tickets have now been filed one target too narrow because a diagnostic
sounded authoritative.

### An ABI trap that would have been silently half-right

The xtensa arm uses `XtensaSlotOff` rather than a literal stack offset: **the
windowed and Call0 ABIs index the expression stack in OPPOSITE directions**, so
a hand-written offset would have been correct on one and silently wrong on the
other. Both ABIs run clean. **A constant that is right on the ABI you tested is
the same animal as a green on the target you tested.**

### The wiring was stale IN OUR FAVOUR — 3 cells became 12

The matrix's Makefile comment said DEFAULT MODE ONLY because the file had been
red under `-dPXX_SHORTSTRING` on all four converted backends. **That state is
closed and the comment outlived it.** Both modes now print the same 33 lines
everywhere; each cross row gained a flag twin, x86-64 is wired natively in both
modes, xtensa is wired under the flag. All twelve byte-identical to the FPC
3.2.2 oracle — **re-run on the extended file rather than trusting the header's
"28 / 28"**, which is the discipline that makes the number mean anything.

### Two pre-existing gaps found alongside, NEITHER gating the flip

**`SetLength` is refused for any frozen string that is not a plain symbol** —
`p^`, `r.f`, `arr[0]`, on EVERY target including x86-64, in both modes, and at
the pin. Every backend's `-101` arm requires an `IR_LEA` of a symbol because it
reads `Syms[si].TypeKind` off the LEA — and that kind is recoverable from the
node without a symbol, which is how the readers were converted.
Filed prio 40, unclaimed, pre-existing, not a width bug.

**xtensa bus-errors in DEFAULT mode** on this file before line one, with
`--platform=posix --xtensa-soft-mulhigh`, and reproduces at HEAD without the new
rows. Pre-existing, unrelated to the byte prefix, and it is why the xtensa row
is flag-only.

## Narrowing changed what the bug WAS (frankb-78, `59ff9a277`)

The xtensa crash was not "this file dies on xtensa". It is an ALIGNMENT bug:

```pascal
type TS10 = string[10];
var arr: array[0..2] of TS10;
arr[0] := 'zero';  { ok }
arr[2] := 'two';   { ok }
arr[1] := 'one';   { Bus error }
```

`SizeOf(TS10)` is 18 in the default mode and the stride IS the size, so element
1 starts at offset 18 — **2 mod 4** — and the 8-byte prefix store is unaligned.
Elements 0 and 36 are 4-aligned and correct.

**THE ALIGNED PAIR IS THE FINDING, NOT THE CRASH.** With only `arr[1]` the
repro reads as *"array element stores are broken on xtensa"* and sends the next
person into the store path. With all three, the predicate is `SizeOf(T) mod 4`
and **every odd element of any `array of string[N]` of odd-ish size is
suspect** — not just this type. Correct under `-dPXX_SHORTSTRING` (a 1-byte
prefix has nothing wide to misalign), correct on the six other targets, both
ABIs, and reproduces at pin v401.

**A REAL FORK, DELIBERATELY NOT PICKED** — pad the type on alignment-requiring
targets (changes `SizeOf` and layout, and fixes every other wide access to a
misaligned element) versus split the prefix store in the xtensa backend (local,
no layout change, and **assumes the prefix store is the only wide access, which
nothing has established**). Both are named in the ticket; whoever takes it
should see both.

## The refusal family has a THIRD member, and it is about STAGE

1. riscv32/xtensa refused a builtin with a reason that was **false**
   (`bare-metal stage 1`, when `Pos` and `Copy` compile there).
2. A comment claimed a sibling arm that had **never been written**.
3. **franka-29's xtensa canary rows returned `rc=1` from the ESP IMAGE WRITER** —
   downstream of the thing under test, *after* the backend had already emitted.

**So a row can produce no observation because it never compiled, because it
compiled and was refused at a LATER STAGE, or because the arm is genuinely
dead — and only the third is a finding.** An `rc` alone cannot separate them;
**the STAGE can.** A canary proving code dead must assert WHERE the failure
came from, not merely that one occurred.

This is the same shape as the coordinator's three absence-as-measurement errors,
seen from the other side: there, nothing was measured and it read as a result;
here, something was measured and it was the wrong stage.

**Both sessions are writing these up as a CLAUDE.md PROPOSAL for the owner
rather than editing that file on a peer's say-so.** That is the right call and
the proposal is queued for him, not applied.

## CORRECTED AGAIN: ONE regression and ONE never-worked feature

**The previous heading said "two silent regressions". One of them is not a
regression.** frankb-78 bisected #2 to **`eadf214725a`** — the commit that
INTRODUCED the x86-64 byte prefix. `frozenVar = ansiVar` under the flag **has
never worked on x86-64.** No culprit to hunt, nobody recent implicated; it is an
incomplete feature, not a breakage.

### AND THE ERROR THAT PRODUCED "REGRESSION" IS THE ONE THIS FILE ALREADY WARNED ABOUT

frankb-78 measured the PINNED compiler with `-dPXX_SHORTSTRING`, got TRUE, and
read it as *"correct before"*:

```
PIN default:  sizeof 16   var_ans TRUE
PIN flag:     sizeof 16   var_ans TRUE      <- SIXTEEN, in a mode that must print 9
```

**The pin predates the byte prefix, so the flag is a no-op in it** — both rows
are the same 8-byte-prefix program and the flag row was the default row wearing
a flag. **A positive control drawn from the wrong population passes and
certifies the instrument.**

**This file already carries that exact warning, contributed by frankb-78 itself
a few hours earlier** ("THE PIN IS USELESS AS A CONTROL FOR THIS FAMILY"). It
then used a pinned control for byte-prefix work. **Knowing a rule is not the same
as recognising the situation it applies to** — and the tell was inside its own
output: `sizeof 16` where the mode requires 9. It walked past its own data.

**That is the strongest argument in this file for writing rules down as
CHECKS rather than as prose.** Three sessions have now been caught by the pin
in two days.

### The old heading's content, still accurate:

**"The phase-4 gate is clear" was true when measured and is no longer true.**
frankb-78 found two wrong-value regressions at HEAD that are **correct on pin
v401**. Both silent: no diagnostic, no crash, just `FALSE`.

1. **i386, BOTH modes** — `arr[0] = arr[1]` for `array[0..1] of string[8]`
   holding equal strings answers FALSE. `arr[0] = a` against a plain variable is
   correct, so it is **element-vs-element specifically**.
2. **x86-64 native, `-dPXX_SHORTSTRING` ONLY** — `frozenVar = ansiVar` answers
   FALSE for equal contents. Default mode correct; every other target correct in
   both modes.

`bug-a-i386-comparing-two-elements-of-an-array-of-frozen-strings-is-false` and
`bug-a-a-frozen-string-compared-to-an-ansistring-is-false-under-the-flag-on-x86-64`,
both prio 70. **Not yet bisected.** They arrived with the frozen work of
2026-09-02/03 — frankb-78's, franka-29's and frankh-15's — and nobody is
assuming whose.

**#2 IS THE ONE THAT MUST NOT BE FOUND AFTER THE FLIP.** It is the
cross-representation compare, wrong **only in the mode phase 4 makes the
default**, on **the backend everything is measured on**, with the default-mode
row green beside it. **A pin taken now would freeze it.**

**My 20-probe suite scores these targets clean and does not construct either
shape** — no element-vs-element compare, no frozen-vs-AnsiString compare. Third
time the suite has been cited as evidence for something it does not cover.

### THE FAILURE VALUE IS NOT CONSTANT — and that is how it hid

For the frozen/AnsiString compare:

| shape | answer | correct? |
| --- | --- | --- |
| two equal strings | FALSE | **wrong** |
| `a = a` | TRUE | right — *the addresses ARE equal* |
| `a < b`, equal contents | TRUE | right by accident |
| `p^ = a`, `p` pointing at `a` | TRUE | right — **and this is what a repro naturally writes** |

**A must-be-TRUE suite catches half, a must-be-FALSE suite the other half, and
a repro that points its pointer at its own comparand catches none of it.**
Every previous rule in this file assumed a fixed wrong answer that a control
could pin down; this one's wrongness depends on operand IDENTITY.

### Two wasm32 tickets whose recorded CAUSE measurement did not support

Both closed at `a30556172` (26 → 30 wired rows), and in both the ticket named a
mechanism that was never entered:

- Frozen comparison compiled to an **`i32.eq` of two ADDRESSES** —
  `wasm2wat` shows `i32.const / i32.const / i32.eq` and **no `PXXStrEq` call at
  all**. `WasmStrParts`, the ticket's named cause, was never reached, and
  *"wrong at every length"* was never it either.
- `SetLength` had no `-101` arm — the same absent arm as riscv32 and xtensa. The
  ticket blamed `WasmEmitSetLenStr`; a frozen `SetLength` never reaches it.
  frankb-78 **wrote the arm there first, measured that it never fires, and
  removed it.**

**And the exclusion note on two remaining rows was wrong because the COVERAGE
REPORT PRINTS ONE REFUSAL PER BODY AND THE FIRST WINS** — which is how three
unrelated causes collected under one `rc=134` and were written up as one.

## WHAT THE 20-PROBE SUITE DOES NOT CONSTRUCT

frankb-78: *"A suite cannot report a shape it does not have; a written inventory
of the axes it covers can."* The suite has been cited three times as evidence
for something outside it, always by the coordinator. It is not wrong — it is a
FIXED SET OF SHAPES, and each citation quietly promotes *"these shapes pass"*
into *"this target is clean"*.

**Covered (20 probes × 2 modes × 5 targets):** assignment; `=` against a
literal; ordering; concat (literal and variable operands); array element read
and `=` against a literal; record field read and `=`; deref index; deref whole;
`const` and `var` parameters; function result; `Copy`/`Pos`; index write; deref
write; `SetLength`; array-of-record field; `const` declaration; empty string.

**NOT constructed — every one of these has hidden a real defect:**

| absent shape | what it hid |
| --- | --- |
| element **vs element** (`arr[0] = arr[1]`) | i386 FALSE, both modes |
| frozen **vs AnsiString** | x86-64 FALSE under the flag |
| deref **vs deref** | unknown — untested |
| field **vs field** | found separately by frankb-78, not by the suite |
| frozen arg to a **constructor / virtual** call | the prio-92 ladder, four targets |
| frozen field to an **AnsiString param** | the all-seven-target overload refusal |
| `SetLength` on a **non-symbol** (`p^`, `r.f`, `arr[0]`) | refused on every target |
| **odd-indexed** array element store | the xtensa alignment bus error |
| anything under **`-uPXX_MANAGED_STRING`** | three separate defects |

**The pattern in the absent column is BINARY OPERATIONS BETWEEN TWO NON-TRIVIAL
OPERANDS.** Nearly every probe compares a computed value against a LITERAL or
prints it. Two frozen operands, or one frozen and one managed, is the axis the
suite has almost no coverage of — and it is where three of the last four
defects lived.

**Do not extend it by adding probes of the same shape.** The gap is an AXIS, not
a count.

## The commit that broke it was CORRECT (frankb-78, `2bd82200e`)

Both compare defects fixed. The i386 one bisected to **`450f4b52a` — and that
commit is not wrong.** It had to start tagging an `IR_INDEX` with the kind the
ARRAY records, because that tag is where the prefix width comes from. **What
broke is every guard that had been asking a DIFFERENT QUESTION of the same
tag:**

```pascal
if ((op = tkEq) or (op = tkNeq)) and
   ((IntToTypeKind(IRTk[left]) in [tyAnsiString, tyString]) or ...
```

That means *"is this a string at all"* — and its comment said so, and said it
was safe **because the IR's generic `tyString` tag answers that.** True when
written. **A correct change to what a tag MEANS breaks every reader that was
using it to mean something else, and none of them are wrong either.**

### ITS SECOND VICTIM WAS BIGGER THAN THE ONE REPORTED

The same enumeration in `ir.inc`'s case lowering: **`case arr[0] of 'lit'`
STOPPED COMPILING on all seven targets in both modes** — `case label does not
match the ordinal selector type`, a **hard error on valid code**, correct at the
pin. `case r.f of` had it too under the flag.

**Live in every `$(PXX_STABLE)` build, and nobody reported it** — because no
test had a non-trivial `case` selector. **The absent-column pattern again, in a
new construct.** Both the i386 wrong answer and an all-target compile error are
one root, and **the compile error is the bigger defect**.

### THE FIX IS A PREDICATE, NOT THREE EDITS

`TypeIsAnyString` in `symtab.inc`, beside `TypeIsFrozenString` (*"does it carry
an inline prefix"*) and `StrValTk` (*"what does it present as"*). **A guard
meaning "is this a string" must not enumerate kinds, because the SET OF KINDS is
exactly what this feature keeps changing.** Three questions, three named
predicates, no enumerations.

**And it left arm32's identical enumeration alone** — `s := arr[0]` and
`s := r.f` are correct there on every target in both modes. **Widening a guard
with no measured defect behind it is a change nobody can verify.** That is the
right call and the harder one.

### A FIFTH STALE-BINARY ROUTE: A BISECT LEAVES THE BINARY BEHIND

`git bisect reset` returns the TREE to master and **leaves whatever the last
bisect step built on disk**, and `make` does not necessarily rebuild it.
frankb-78 nearly reported *"i386 is fixed already"* off three probes that all
said TRUE. **The sha said `a81084690bac` where a HEAD build gives
`60710c8ee103`** — printing the sha beside the result is the only reason it was
caught. Add to the four routes in the handbook.

## 2026-09-03 — PChar closed (`61b12b89c`), and the four findings that outlive it

Banked by the coordinator from frankb-78's report. Verified `61b12b89c` is an
ancestor of `origin/master` before writing this.

### 1. Six arms, not four — and ONE ARM WAS COVERING FOR ANOTHER

The ticket named four. `AN_CAST`'s `PChar` arm was the fifth, and no probe could
see it: **whenever the cast arm declines to fire, the CALL arm rescues the cast
downstream**, because the cast not firing is exactly what leaves the node still
tagged frozen for the call arm to catch. `f(PChar(r.f))` was green all day;
`q := PChar(r.f)` — the same cast with no call to rescue it — pointed at the
length byte.

**Every probe written for this ticket passed the value to a function.** That is
not carelessness, it is the natural shape of a probe: you print what you get, and
printing is a call. The lesson generalises past this family — **when two arms can
each handle a node, a probe that always takes the same route through them tests
one arm and reports on both.** The discriminating spelling is the one that
consumes the value without passing it anywhere.

### 2. The sixth arm was PRE-EXISTING, DEFAULT-MODE, and the fix would have WIDENED it

`@r.f` and `@arr[0]` lower to `IR_FIELD`/`IR_INDEX` still tagged with the
aggregate's string kind, so the call arm fired on an **address-of** and added the
prefix to it — `Take(@r.f)` handed the callee base+8 **in the default mode**,
shipping today. `@s` was correct only by accident: `IR_LEA` on a symbol already
yields `tyPointer`. **Three spellings of one operation disagreed, and the two
broken ones were the two that go through an aggregate.**

The part worth keeping: **widening the guard in the first four arms extended the
bug to `@arr[0]`**, and the offset row in the author's own new test caught that
regression on its first run. The arm already carried the sentence *"the address
VALUE is a pointer no matter what it points at"* for the float case; the fix was
applying a rule already written down to the place it was equally true.

### 3. THE INSTRUMENT LIED BY RENDERING — this is a second half for the measurement rules

frankb-78's BEFORE matrix printed `cast fld [abcde]` and it read as a pass. The
pointer was one byte low and the first byte was `#5` — **invisible in a
terminal**. The control run on the same bytes now prints `[<005>abcde] FALSE`,
because the test **asserts** `walked = 'abcde'` instead of showing it.

`cat -v` is already in the measurement rules, and it was run — on the AFTER
output. The BEFORE was eyeballed. So the rule needs its second half:

> **A string row must be ASSERTED, not READ.** A rendered row hides exactly the
> leading-byte errors this family produces, and it hides them **in the direction
> that reads as success**.

This is the same animal as the assertion-class rule (a leak cannot fail a value
check) one level down: here the assertion class was right and the **rendering**
destroyed the evidence before the eye got to it.

### 4. The test carries NO WIDTH, so the default mode is a real control

Four rows assert `PChar(x) - @x = SizeOf(TS) - 8`, which is true at a prefix of 8
**and** at 1. One `.expected` therefore serves both modes, and the default-mode
rows are a genuine control rather than rows passing for the old reason. 21
assertions, 7 targets x 2 modes x xtensa's two ABIs, 16/16. Positive control run
rather than asserted: fix stashed, stamp removed, rebuilt (`c55894ef5e11`) —
fails in both modes; restored (`b9a8bb0c5f2c`) — matches. **FPC 3.2.2 rejects
every frozen spelling in the file** (`Illegal type conversion: "TS" to "PChar"`),
so there is no oracle here and the test header says so.

### 5. The FPC seed canary earned its rule again, live

First gate run failed on a missing `forward` for `IRStrTkOf` — declared at
`compiler.pas:16160`, called at `6205`. **`make compiler/pascal26` and
`--tier quick` were both GREEN.** That is the declaration-order class in the
wild: PXX prescans headers, FPC is single-pass, and the canary only runs while
`compiler/**` is UNCOMMITTED. Gate before you commit, not after — it would have
been invisible for as long as nobody touched the seed.

### Residual, explicitly NOT closed

The xtensa element-store bus error (prio 60) was re-measured at frankb-78's tip
and is **still signal 7**. It was a near-hit on this ticket, not a consequence of
it.

### P4 status — the blocked-by list is empty and that is NOT a release signal

Every filed blocker is closed. **The list records what has been FILED**, and each
phase of this overhaul has ended with a defect nobody had filed yet — the six
arms above being the fourth instance. The flip is the owner's alone, it
serialises the fleet, and "the axis looks clean" is the exact cue that would
misread it.

## 2026-09-03 — xtensa (`18b92fac9`), and the tell sharpened into something greppable

Banked by the coordinator from frankb-78's report; `18b92fac9` verified as an
ancestor of `origin/master` first. The crash was one line. **The sweep for its
fallout found three more, all silent, all in the layout the flip makes the
default, none filed by anyone.**

### The crash, and why only an ARRAY could tell two mechanisms apart

`SizeOf(string[N])` was cap+prefix with nothing rounding it up, and **that size is
also the array stride** — so `array of string[10]` strode 18, element 1 began at
2 mod 4, and the 8-byte length word was unaligned. The ticket offered two fixes
and said nothing had established which; `Length(arr[1])` traps identically, so the
READ is the same access and **the backend-split option was never sufficient.**

The part to keep: the record path had already reached the right answer by a
different route — `SizeOf` said 18 while the field layout behaved as if 24.
**Only an array could tell those two apart**, because only an array multiplies
the size. Padding the slot makes stride = `SizeOf` again and the two mechanisms
agree by construction rather than by agreement.

### The three, all `-dPXX_SHORTSTRING`, all silent

- **`record x, y: string[10]` OVERLAPPED** — 16 bytes with `y` at offset 8 (FPC:
  22 and 11), so writing `y` truncated `x` to seven characters. The field-size
  test named `tyFixedString` only, so the flag's kind fell through to
  `TypeSlotSize` — **a POINTER WIDTH for a string.**
- **A truncating store into a `string[4]` FIELD wrote all eight source bytes**,
  into the neighbour. The clamp asked `= tyString`, which covered `tyFixedString`
  only because a fixed-string field is RECORDED as `tyString`.
- **`a[0][1]` read base+8** where the first character is at base+1.

### THE TELL, SHARPENED — "an enumeration exists BESIDE a complete one"

This is the fifth phase-4 area to end with a defect nobody had filed, and
frankb-78's contribution is to say what four of them had in common instead of
adding to the count. **In three of the four, the entity that knows was already
being asked ONE ARM AWAY:** the variant-part field path tested both kinds while
the main and class paths tested one; `ASTFrozenArgTk` already had the array arm
the char-index site needed; the deref spelling of that same index had been fixed
here before.

> So the tell is not *"an enumeration exists"* — it is **"an enumeration exists
> BESIDE a complete one."**

That matters because it is **greppable in a way the kind axis is not**: you are
looking for two sibling arms of one construct that test different sets, not for
every `= tyString` in the tree. It is where to look for a sixth.

### Two existing tests held ASSUMPTIONS, and only a size change could expose them

- The byte-prefix test used `SizeOf` (18 vs 11) as its positive control,
  **hardcoded in seven Makefile rows**. It now prints the PREFIX (`@s[1] - @s`,
  8 vs 1): one expected string for every target, and a stronger control because
  it names the thing the flag actually changes.
- The sizeof-matches-storage test bracketed the slot at `<= 18` — **the unpadded
  size wearing the shape of a derivation.**
- The through-a-pointer test derived its prefix as `SizeOf - 10`; it now asks
  `@d[1]`.

> **A derivation that stops being true is worse than a constant, because it keeps
> answering.**

### The new test's design is the reusable part

**23 relations, no number anywhere in the compared output** — so ONE `.expected`
serves both modes AND **FPC 3.2.2**, which compiles and runs the file unmodified
and prints the same lines. A layout test with a real oracle.

And it caught its own author: the first draft asserted `stride mod 8`, **passed
on x86-64 and aarch64 and failed on all five 32-bit targets** — the 8-byte prefix
is two words there, so 4-alignment is what it needs. Second time in one day a new
row caught its own author's wrong premise on the first cross run (the PChar
offset row was the first).

### Filed, not fixed

- A variant record with a shortstring branch is 12 bytes where FPC says 8 (16
  before the field fix, so the field half is done and the variant BASE is a
  separate mechanism). **See the archaeology note below — this is not a plain
  new defect.**
- The container-strides case **is compiled by the Makefile and NEVER ASSERTED**,
  with `dyn2dvals` red at the pin and at HEAD. A case nobody compares is a guard
  that cannot fail. frankb-78 deliberately did NOT wire it with today's output,
  because that bakes the red row in as expected — the correct call, and worth
  naming, since wiring it would have LOOKED like closing it.

### Banked beside frankb-78's own rule, from franka-29

franka-29's 100,560-compile zero was measured over Pascal sources only,
**missing 1433 non-Pascal ones**. Nothing of frankb-78's was measured that way.
The general point is a sharper form of the refusal-downstream rule: **a source
that was never ENUMERATED leaves no trace at all** — not a skip, not a refusal,
not an rc. The absence is invisible in a way even a wrong exit code is not.

### ARCHAEOLOGY — the variant-record ticket is not new, and the discriminator is one line

Dedup check by the coordinator, by folder. The slug frankb-78 suspected,
`bug-p-a-tagged-variant-record-is-padded-to-eight`, is in **`done/`** — resolved
**2026-08-16 as `1a2db4cfc`**, and its summary is:

> *"`record case k: Integer of 0: (i: Integer)` measured 12 bytes where FPC says
> 8: the variant part was always aligned to 8, charging the tag's own padding
> twice."*

**Same numbers, same mechanism, no shortstring in it.** So today's report is one
of two very different things, and nobody has established which:

1. the shortstring branch reaches the variant base by a path `1a2db4cfc` did not
   cover — a new, flag-only, prio-45 defect, which is how it is currently filed; or
2. **`1a2db4cfc` has REGRESSED** — in which case the defect is default-mode, has
   nothing to do with this overhaul, affects every tagged variant record rather
   than shortstring ones, and a `done/` ticket has been silently false for some
   time.

**The discriminator is one compile with no shortstring in it:** does the ORIGINAL
repro — `record case k: Integer of 0: (i: Integer) end` — still measure 8 today,
in the DEFAULT mode? If 8, it is (1) and the prio-45 filing is right. If 12, it
is (2) and the prio is wrong by a lot.

Not measured here: the coordinator does not measure. Handed to frankb-78, which
holds the tree and the context.

### ARCHAEOLOGY, RESOLVED — and my own framing above was wrong

`a82c87c40`, verified on origin. The discriminator answered **8**: `record case
k: LongInt of 0: (i: LongInt) end` measures 8 in the default mode and 8 in FPC,
so **`1a2db4cfc` has NOT regressed.**

**But the section above offered two possibilities and the answer was a third.**
Neither "a path the fix missed" nor "a regression" — **the report was FALSE**, and
frankb-78 moved it to `rejected/` an hour after filing it. The 8 it had compared
against came from `fpc -O2` **with no `-M` flag, where `Integer` is TWO bytes**
for Turbo Pascal compatibility. Its record had a 4-byte `Integer` and FPC's had a
2-byte one: **the two compilers were laying out different records.** With
`LongInt` on both sides they agree at 12, in FPC's default mode and under
`-Mobjfpc`; `record case k: Byte of 0: (s: string[4]) end` is 6 in both. There
was never a residual divergence — the field-size fix took this shape 16 -> 12 and
**12 is correct.**

So the honest version: the field half was broken, it was fixed, and then **the
correct answer was reported as a defect because the oracle was answering about a
different type.**

### THE ORACLE LIED BY BEING CORRECT ABOUT A DIFFERENT PROGRAM

`tools/fpc_diff_probe.sh` passes `-Mobjfpc` on every compile. frankb-78 invoked
`fpc` by hand for a one-off record comparison — a minute's convenience — and
**lost the flag the tool carries.** It did not error. It compiled, ran, and
printed a true number about a program nobody had written.

> **The tool is not slower than the shortcut. It IS the shortcut, with the flag
> in it.**

This is the differential-probe form of the rule this file already states three
ways, and it was walked into by someone who could quote the rule. Worth noting
that the failure is not skipping a check — the check RAN, and its result was
true.

**The discriminator, for anyone comparing a LAYOUT against FPC by hand: print
`SizeOf(Integer)` beside the number. Where it says 2, the record under test is
not the one you declared.**

### Why `18b92fac9` is untouched by this — re-checked, not assumed

Those records hold only `Byte` and `string[N]` fields, so no bare `Integer`
appears in them, and the layout test **prints no sizes at all**: its FPC
agreement is over booleans and strings, which carry no width.

**The design choice that made one `.expected` serve both modes is the same one
that made it immune to this.** That was luck in origin and is worth keeping
deliberately: **a test that prints no number cannot be fooled by a compiler that
disagrees about what a number means.**

Filed to `rejected/` rather than deleted, per the four-folders rule — the report
is wrong and the trap is worth the file. The `done/` ticket's "filed, not fixed"
section was corrected in the same commit so it stops pointing at a defect that
never existed. **The other ticket stands unchanged:** the container-strides case
is compiled and never asserted, `dyn2dvals` red at the pin and at HEAD.

### CORRECTION — the strides case IS asserted, and my own grep said otherwise first

Track T filed a NEW-RED at `71a66c7d1` (`eefa9aa4b`, ticket `26c24332a`) for the
container-strides job: **`-dyn2dvals 1 | +dyn2dvals 0`**. That contradicts what
was banked an hour ago from frankb-78 — *"compiled by the Makefile and NEVER
ASSERTED"* — so one of the two is wrong. It is the banked claim.

**The recipe has BOTH rows**, and `291defbfd` (2026-09-02, frankb-78's own
commit) added them together:

```
./$(COMPILER) test/test_string_n_container_strides.pas $(TESTTMP)/test_strn_container26
tools/expect_same.sh test_strn_container26 "$(...)" "$(printf '... dyn2dvals  1 ...')"
```

**THE COMPARE ROW KEYS ON THE BINARY NAME (`test_strn_container26`), NOT THE
SOURCE PATH.** So `grep 'string_n_container_strides' Makefile` returns exactly
one hit — the compile — and reads as proof that nothing asserts it. I ran that
grep, got one row, and was one commit from banking "confirmed: compiled and never
asserted" as a second source. It is the same instrument failure this file already
names: **a grep answering truthfully about a literal string, and being read as an
answer about a concept.** Two readings that fail the same way are one reading, and
frankb-78 and I made the identical one.

**What is actually established:** the row exists and asserts `dyn2dvals 1`; the
job is NEW-RED at `71a66c7d1` with actual `0`; `291defbfd` and `18b92fac9` are
both ancestors of that sha. **What is NOT established:** when it went red, or
what took it there. Nobody has bisected it and this note does not claim to.

**One more thing for whoever takes it — a comment/code disagreement.** The
Makefile comment above these rows says every row *"is a MEASURED stride compared
against another measured stride, never a constant, so the byte-prefix relayout
cannot turn it red."* A row is red. Either the comment is wrong about `dyn2dvals`
or the value is, and per the handbook the fix is to decide which BEFORE touching
either — matching the comment to the broken row would destroy the evidence.

The parked ticket's stated reason for not acting no longer stands: it was not
"a guard that cannot fail", it was a guard that failed.

## 2026-09-03 — `dyn2dvals` resolved (`e69e71ed2`): the red was RIGHT, and the mask was the ALLOCATOR

Banked from frankb-78; `e69e71ed2` and `adbe33db8` verified as ancestors of
`origin/master` first. **This is the sixth phase-4 area to end with a defect
nobody had filed.**

### `dyn2dvals` is a VALUE row, not a stride row — that distinction is the answer

It writes `r{i}c{j}` into every element of a 3x3 `array of array of string[10]`
and reads them back; the row is 1 iff every element round-trips. `dyn2d`,
directly above it, is the stride row.

**The per-element size of a dynamic array is decided in THREE places and only one
ever asked for a capacity:**

1. `DynElemSize` (`ir.inc`) — the INDEX path. Asks `FrozenStrSlotSize`. Always
   correct.
2. `GetOrAllocNodeDynDesc` / `GetOrAllocSymRTTI` — the portable descriptor every
   CROSS backend hands `PXXDynSetLen`. Asked `TypeStorageSize`: **a pointer width
   for a frozen string.**
3. x86-64's inline `IR_SETLEN_DYN` arm — its own `TypeSlotSize`, same width, its
   own copy of the descriptor build.

`SetLength` allocated 8 bytes per element for a row the index path strides by 24,
so **the last element of every row was written past the end of its own block.**

### WHY IT PASSED BEFORE — measured, not reasoned

frankb-78 rebuilt the pre-padding compiler and measured the block rather than
arguing about it:

| | stride | needs | block | result |
| --- | --- | --- | --- | --- |
| before | 18 | 54 | 56 | PASS |
| after | 24 | 72 | 56 | `[r0c2]` and `[r1c2]` blank |
| fixed | 24 | 72 | 104 | PASS |

The allocation was computed from 8 bytes/element and **the ALLOCATOR'S BUCKET
ROUNDING handed back 56 anyway** — which happens to cover 54 and does not cover
72. The under-allocation was there the whole time; the padding is only what
pushed the overrun past the rounding. The last row passed throughout, because
nothing follows it.

> **A latent under-allocation whose only symptom is which element the bucket
> rounding happens to cover is invisible until a width moves — and the width
> moving is the thing everyone reads as the cause.**

That is the trap in this whole phase in one sentence: the change that reveals a
latent defect looks exactly like the change that caused one, and only measuring
the pre-change block tells them apart.

### COMMENT VS CODE, decided before either side was touched

The comment said: *"Every row is a MEASURED stride compared against another
measured stride, never a constant, so the byte-prefix relayout cannot turn it
red."* **The first clause is TRUE — no row compares against a constant, which is
why the block survived the relayout. The CONCLUSION is over-broad.** `openvals`
and `dyn2dvals` are VALUE rows, and a value row goes red whenever a write lands
outside its own block, whatever the widths are.

So both were wrong, about different things: the value (a real defect, fixed at
the root) and the comment (wrong about its own coverage). The row stays expected
`1`; the comment now says a red here is a bug found, never a stale expected
value.

> **"No row compares against a constant" buys immunity from a RELAYOUT, not
> immunity from a BUG.**

The immunity claim was written over an eight-row block where **six rows had it
and two did not — and the two that did not are the only ones that can catch an
out-of-bounds write.** **An immunity argument stated per-TEST rather than
per-ROW is the shape to look for.**

### The fix, and what was deliberately NOT merged

One shared `SetLenDynElemSize`, asked by the portable descriptor and by the
x86-64 inline arm, so **the two that disagreed cannot again**. The index path's
`DynElemSize` was NOT collapsed in — it takes a different set of inputs and
merging it wants the descriptor machinery reworked. **The count of three is now
in a comment so the next reader sees it rather than rediscovering it.** 8/8 rows
on x86-64, i386, aarch64, arm32, riscv32, xtensa.

### Also landed, and both are the same animal from other sides

**1. `regression-test-emit-obj-test-esp-hello` — THE EXPECTED COUNT WAS THE
DEFECT.** The row said taking an external's address costs TWO more relocations
than calling it; it costs ONE. The `+2` was measured while the
address-materialisation sequence was emitted **twice back to back** (riscv32
`auipc/j/literal/lw` at `0xb4` and again at `0xc4`, same value into the same
register; xtensa the same duplicate literal). `adbe33db8` stopped the double
emission and **the row went RED FOR THE IMPROVEMENT.** Verified byte for byte
against the pin rather than inferred: HEAD's `.text` is the pin's with exactly
that 16-byte sequence removed and everything after shifted down. **And the
fixture's own comment said ONE all along** — comment and code disagreed, and the
code had encoded what the defect produced.

**2. A SIGSEGV RATE recorded instead of a close.** `test_npy_clone26`: 10/10
green looked like a fix; **100 runs gave 29 crashes.** A pass rate sampled at ten
is not a pass rate.

### Filed, deliberately NOT fixed

`bug-a-a-field-rooted-array-of-array-of-string-n-indexes-as-a-char` (prio 55,
`backlog-core`). The field-rooted `SetLength` arm has no symbol to carry the
capacity, so its frozen element still gets the kind-only size — **left unfixed on
purpose, because `r.matrix[0][0] := 'a0'` for a record field of `array of array
of string[10]` does not compile AT ALL in either mode** (the second index
resolves as a CHARACTER index), while the same declaration as a plain variable
works and FPC runs it. **There is nothing to measure a fix against until the
parse bug is fixed, and fixing the size arm blind would be a change with no
observable.** That is the right call and the reason belongs in the record.

### Retracted

The "compiled and never asserted" ticket is in `rejected/`. The correction stands
as banked at `884a51fbc`: **a Makefile test row is addressed by its OUTPUT name**,
so grepping the SOURCE path finds the compile and not the compare — hit
independently by two sessions an hour apart, which is what makes it a class
rather than one session's slip.

## 2026-09-03 — the canary pass (`86bc8e33d`): FIVE arms were reachable, and nothing was deleted

Banked from franka-29; `86bc8e33d` verified on origin. **The ticket stayed open
until proven and the proof came back negative — believed-dead was not
proven-dead, for the second time in this family.**

### What fires

Each inline frozen->managed argument arm became an `Error` with a **per-site
id**, and every id was **first shown able to fire** under a control build with
`IRLowerCallArg`'s arm gated off — before any silence was read as evidence.

| arm | fires | population |
| --- | --- | --- |
| x86-64 / direct | 61 | 30 distinct `.npy` sources |
| x86-64 / ordered-predicate | 60 | same, `-O3` only |
| i386 / direct | 120 | same |
| arm32 / direct | 120 | same |
| aarch64 / direct | 120 | same |
| riscv32 / direct | 0 | of 1932 compiles — **vacuous** |
| xtensa / direct | 0 | **of 0 compiles — entirely vacuous** |
| x86-64 ordered / ctor / method | 0 | 5092 compiles |

**TEN arms, not the ~15 the ticket claimed** — the census is closed, and the two
riscv32/xtensa external-C arms are a different conversion (frozen -> `PChar`)
that was never part of this.

### Why they are reachable

`IRLowerCallArg` excludes `AN_STR_LIT` deliberately — **and `AN_STR_LIT` is a
PASCAL node.** A NilPy string literal lowers to a `const_str` tagged `tyString`,
matches neither that exclusion nor any backend's literal fast path, so **the
backend's own frozen arm is the only thing that converts it.** `x = "a" * 3`
fires; `y = "ab"; x = y * 3` does not. With all ten deleted the self-host
fixedpoint still held and `gate.sh quick` went RED — `quick_canary_nilpy` from
`total ok 36 / 36` to `ok 23` plus a segfault. Root cause filed as
`refactor-a-nilpy-const-str-bypasses-both-the-literal-fast-path-and-the-call-arg-funnel`
(prio 45, `backlog-core`, unclaimed).

### THE CORRELATED BLIND SPOT — the finding, and it outranks the fix

Before that, franka-29 ran a canary sweep of **100,560 compiles** — whole corpus
x 6 targets x 4 mode corners x `-O0/-O2/-O3` — and reported **ZERO fires**, and
was about to close on it. **It enumerated only the Pascal half: 1676 files.** The
corpus also holds **818 `.npy`, 583 `.c`, 26 `.rs`, 6 `.zig`**, none compiled.

> The claim under test was *"every call argument now funnels through one
> function"*, and **the frontends that do NOT funnel are exactly the ones a
> Pascal-only population cannot contain. The hole and the defect had the same
> shape, so the zero was clean BECAUSE the bug was there.**

That is the sentence to keep. This repo already knows a zero can be vacuous; what
is new is that **the gap was not random — it was CORRELATED with the defect.** A
random gap would have been lucky to hide five reachable arms across five targets.
This one was guaranteed to.

### Two guards worked and still could not see it

**Per-site ids** — two arms had first shared a label, and every fire came from one
of the two. **Replaying every control-firing row under the armed binary**,
requiring rc=0 AND no fire — 12 of 76 came back rc=1, a whole backend's control
population refusing to compile.

**Both are aimed INSIDE the population.** `gate.sh quick` caught it on the first
test OUTSIDE it, **which is an argument for gating before believing a census
rather than after.**

### Scoping, stated by the author rather than asked for

The numbers are scoped to tip `8cd3d6eb4`. frankb-78's `18b92fac9` (SizeOf
padded to a machine word) landed after the sweep, and franka-29 said so rather
than comparing across it.

## 2026-09-03 — the NilPy thread flake (`817cac4ef`) — NOT shortstring, but the same three classes

Banked here rather than separately because its findings are direct continuations
of this file's: **the assertion class must match the defect class**, and **the
sibling-arm tell**. `817cac4ef` verified on origin.

**It was never a race in the runtime.** `__pxxclone`'s trampoline calls an entry
it knows nothing about. A callee whose return type is `RetViaHiddenDest` —
record, set, frozen string, `Variant`, promo int — does not return in a register:
it copies through a pointer **the caller is obliged to hand it**, in a register
fixed per target (`r10` x86-64, `ecx` i386, `x8` aarch64, `r12` arm32). The stub
set none of them, so the child copied its result through whatever the clone
syscall sequence had left there. On x86-64 that register is `r10`, which the stub
loads with `ctidptr` — so `__pxxclone(..., 0)` made the child **write 16 bytes to
address 0.**

### Why nobody had seen it — a gap the suite's own SHAPE could not contain

> **Every NilPy `def` is such an entry (they all return a `Variant`), and no
> Pascal thread in the tree is one (`TThreadEntry` is a `procedure`).**

An entire ABI obligation went unexercised because **one frontend's threads are
all procedures and the other frontend's are all functions.** That is not a hole
in the test suite; it is a hole the suite's shape guaranteed. Same family as
franka-29's correlated zero earlier today, arrived at independently.

### How a flake became a diagnosis — vary the shape, do not sample harder

It looked intermittent because the child's crash races the parent's exit: the
parent normally finishes and `exit_group`s before the child reaches its epilogue.
frankb-78 **emptied the worker so the parent spins the full 400M instead of
exiting early — 40/40, deterministic** — and gdb then gave it in one line:
`worker+172 rep movsb (%rsi),(%rdi)`, `rdi=0`, thread 2, at the `return`.

**Varying the shape until the race disappears, rather than sampling the race
harder, is what did it.** The obvious wrong answer was checked first and was
wrong: pointing `arg` at valid memory changes nothing, because it is `r10`, not
`arg`.

### "DID IT CRASH" IS THE WRONG INSTRUMENT FOR A WILD WRITE

Scribbling over a join handle is **silent** — `munmap` of a garbage range is
ignored, and the kernel clears the tid word afterwards anyway. The first
acceptance test asserted survival and **passed 70% of the time against a compiler
that was corrupting memory on EVERY run** (5/20 failures, then 9/30 when the
result was made four times wider). **Widening the damage did not help, because
the damage was never the observable.**

Asserting the memory the stray pointer **AIMS AT** does: `PalThreadCreate` passes
`@h.TidWord` as `ctidptr` and `StackSize` sits 16 bytes past it, so the test
snapshots `StackSize` while the children still spin and compares after the join.

| | fixed | pinned (pre-fix) |
| --- | --- | --- |
| x86-64 | 25/25 pass | 10/10 fail — **5 HANG**, 5 report handles `0 / 4` |
| i386 | pass | SIGSEGV |
| aarch64 | pass | SIGSEGV |
| arm32 | pass | **PASSES 5/5** |

**Half the pinned x86-64 failures HANG rather than crash** — the other reason a
crash-only row could never have been the guard. Same family as the open-array
leak: **a wild write is observed at its TARGET, not at the process.**

**arm32's positive control does NOT fire, and the Makefile row says so.** `r12`
is untouched by that leg's syscall sequence, so it held whatever the caller left,
which happened to be valid. **That row is regression cover, not a reproduction,
and reading its green as proof of the fix would be exactly backwards.** Saying so
in the recipe is what stops the next reader counting four green legs as four
confirmations.

### THE SIBLING-ARM TELL AGAIN, one level up

Converting two hand-counted branch offsets: aarch64's `cbnz x0, .parent (+7
words)` and arm32's `bne .parent (+7)` were counted by hand over the child
sequence, so adding one instruction made both land one instruction short —
**inside the child path, in the parent.** The x86-64 and i386 legs had already
been converted to computed offsets **for exactly this reason**, carrying the
comment *"a hand-counted displacement here is the arm that stays wrong the day
someone edits the child sequence and only looks at one leg."*

> **The file was carrying the warning and the bug at the same time, in different
> legs.** A fix applied to some arms of a construct and not its siblings, with
> the reasoning left behind in a comment as if it had been.

That is the "an enumeration exists BESIDE a complete one" tell, promoted from
kinds to code: **a comment explaining why an arm was fixed is evidence its
siblings were not.**

### The fix

A 256-byte scratch carved off the top of the child's stack (above the alt stack,
so every other offset in the leg is unchanged), with the hidden-destination
register pointed at it. The child never returns, so **a write-only sink is the
only meaning a result can have.** Four legs, four registers, **one contract for
the trampoline** — which is what keeps Pascal, C, Rust and Zig entries working
unchanged.

200 runs, 0 failures and 0 wrong outputs, against 29/100 this morning. Existing
thread coverage re-run on all four legs, which is what says the branch conversion
is right rather than merely untested.

### Filed, not fixed — both measured, neither reasoned

- `bug-a-a-nilpy-clone-entry-receives-a-raw-word-where-it-expects-a-variant-address`
  (prio 55): the ARGUMENT half of the same mismatch. A NilPy parameter is a
  by-ref `Variant`, so a worker that actually READS `arg` dereferences the raw
  word — **3/3 SIGSEGV, deterministic. The existing test passes 0 and ignores
  it**, which is why it never surfaced. The stub cannot fix it: the trampoline
  must keep exactly one contract, so the adaptation is a thunk where the callee
  is known. Shape sketched, not built.
- `bug-a-nilpy-thread-clone-cannot-start-a-thread-on-aarch64-or-arm32` (prio 40):
  `tid nonzero = False` on both, clone returns <= 0, no thread at all.
  **Reproduces on the PIN, so not a regression**, and the obvious cause was
  checked and rejected — the test's `SYS_mmap = 9` is the x86-64 number, and
  rebuilding with 222/192 changes nothing. Pascal threading is fine on both, so
  it is specific to the NilPy raw-syscall route.

## 2026-09-03 — the argument half (`d49de34b6`): a thunk where the callee is KNOWN

Banked from frankb-78; `d49de34b6` verified on origin. **The design argument is
the deliverable here, not the fix.**

### Why NOT the stub

The trampoline is reached by Pascal, C, Rust and Zig entries as well as NilPy
ones, so its single contract — `entry(arg)`, a raw word in the first integer
argument register — **is the property that makes it work at all.** Teaching it a
second calling convention would mean **four legs learning a question only one
frontend can answer.**

So the adaptation goes where the callee is KNOWN: the `__pxxclone` arm of the
NilPy factor parser. `PyGetOrMakeCloneThunk` synthesizes `procedure
$pyclonethunk_N(arg: Pointer)` with body `REALPROC(Int64(arg))`, on the
callable-value wrapper's existing pending-body queue with a second sentinel
beside its first.

### Three choices, each defended separately

- **The parameter is `tyPointer`, NOT `tyInt64`** — one machine word on every
  target, where an `Int64` parameter is **two stack slots on i386 and arm32** and
  the second would be read past the staged word. **That would have been a
  cross-target-only bug of exactly the class this file spent the morning on** —
  invisible on the 64-bit host every gate runs on.
- **The `Int64` cast in the body** makes the coercion the ORDINARY one a written
  `worker(41)` gets, instead of a second unboxing path that can drift from the
  first. (Normalise, don't special-case.)
- **It is a PROCEDURE**, so the call is not wrapped in `AN_EXIT`: the callee's
  `Variant` result is discarded **on purpose**, because the child never returns
  and a result has nowhere to go.

A proc that already fits the contract passes through untouched — the gate is
*"first parameter is a Variant, or it returns via the hidden destination"*, i.e.
it is a NilPy `def` — so a Pascal `procedure(arg: Pointer)` from a `uses`'d unit
still gets its raw address. **A `def` with more than one parameter is now a
compile error naming the arity**, rather than a miscall.

### THE PROBE VALUE — this extends the `sizeof(int)` class with its sharpest case

The assertion is **12345**, not 0 and not 1, **and the worker adds one so the
printed number is not the literal either.**

> **A thread entry handed the wrong word almost always gets 0 — the clone stub's
> own registers are full of zeroes.** So a row expecting 0 would pass whether the
> argument was delivered or not, and a row expecting the literal would pass if
> the constant were copied into the wrong place.

Same question as frankc-af's: *if the machinery did nothing at all, would this
row still pass?* **Here the answer was YES for the two values a person reaches
for first.** The general form is now sharper than "avoid a type's default": **the
failure value is whatever the surrounding machinery happens to leave behind —
zero, a pointer width, `sizeof(int)` — and those are exactly the values that feel
natural to assert.**

Measured: `child saw = 12346` at HEAD on native and i386; **3/3 SIGSEGV on the
pinned compiler, deterministic, with `tid nonzero = True` already printed.**

### Broad check RUN AND READ — plus a near-miss on this file's own rule

`make test-nilpy` in full under `PXX_ALLOW_FULL_SUITE=1`, because quick does not
cover the NilPy frontend and this edits its factor parser AND
`PyCompileLambdaBody`, which the callable-value wrappers share — so *"my repro
passed"* was a different claim from *"the frontend still works"*.

**The near-miss:** it was piped through `tail -15`, so the notification's
`exit code 0` was **the PIPELINE's** and said nothing about `make`. frankb-78
checked which recipe line the output ended on instead. **Same wrapper-versus-
verdict shape as the backgrounded gate**, which this file already records — and
it arrived through a different tool, which is what makes it a class rather than a
`gate.sh` quirk.

### Two mechanisms kept ON PURPOSE, and said so in the ticket

The `CLONE_RETBUF_SIZE` scratch **is not made redundant** by the thunk: it covers
a computed entry pointer, and a C or Rust entry returning a struct — neither of
which the parser can resolve to a proc index. **The thunk makes the NilPy path
correct; the scratch makes every other path survivable.** Different populations,
recorded in the ticket **so nobody deletes one as dead** — which is precisely the
mistake the canary pass spent a day disproving.

## 2026-09-03 — the frozen dyn-array field (`aee455a16`), raised 60 -> 85, and TWO classes that correct earlier entries

Banked from franka-29; `aee455a16` and `test/test_dyn_frozen_field_capacity.pas`
verified present. **I asked for a ranking judgement rather than re-ranking it
myself, and the answer was worse than the commit body I had read.**

### The ranking, with the measurement behind it

**In the DEFAULT mode — the shipping build — it is a SIGSEGV, not silent
truncation.** frankb-78 measured that independently before franka-29 got far in;
the A/B is base `c709788d39ad` rc=0 **by luck**, and the same program crashes the
moment one half of the fix lands. No diagnostic, exit 0 or a core dump depending
on how many bytes are stored, **in a shape that has always compiled.**

The flag-mode face is silent truncation **whose length depends on an unrelated
neighbouring declaration**: `pad: string[17]` in front of the field makes a
`string[10]` element clamp at 17; `string[9]` makes it 9.

That is the i386-compare argument **plus a crash**, hence 85 rather than 80.

### The cause was broader than the summary said

Not *"a NAMED frozen alias"*. **Both field parsers test `fIsDyn` FIRST, and that
arm returns before the frozen-field arm — the only place `fStrCap` is ever
assigned.** So every spelling is broken (inline element, named element, named dyn
type), in records AND classes, both modes, every target.

**The class face fails the OTHER WAY:** with no frozen field in front of it the
leftover is `0`, which the store path reads as *"no limit"*, so 26 characters go
whole into a 10-character element. **One hole, both signs.**

### CLASS 1 — a measured negative that was TRUE and still the wrong conclusion

This one **corrects the bucket-rounding entry banked earlier today**, so read
them together.

The ticket carried *"not a missing carrier at the consumer"* as a **measured**
negative: a past session built the carrier, wired it at all three lowering sites,
probed it, found junk arriving, and reverted it because consuming that junk
strode worse than the pointer-width default. **Every word of that was true.**

It was still the wrong conclusion. **The carrier is not an ALTERNATIVE to fixing
the declaration — it is the other half of the same fix, and NEITHER HALF IS
LANDABLE ALONE.** Landing the declaration half first turned a silently-wrong
program into a SIGSEGV: the store's stride becomes truthful while the allocation
stays at a pointer width, 28 bytes into an 8-byte element, and **the crash lands
at the NEXT allocation, two statements after its cause.**

> **The malloc bucket was the only thing standing between two wrong numbers and a
> crash, and fixing EITHER half alone removes it.**

frankb-78 hit the mirror image from the allocation side on `dyn2dvals`. So the
two entries in this file are one phenomenon seen from opposite ends. Two rules
fall out:

> **A new crash immediately after a size fix is evidence the fix is RIGHT.**
>
> **"I measured that this makes it worse" scopes to the STATE AT THE TIME OF
> MEASUREMENT, not to the design.**

That second one is the sharper of the pair, because the measurement was honest,
reproducible, and correctly reported — and it still froze a half-fix into the
record as a closed door.

### CLASS 2 — a cause that FITS is not a cause that was OBSERVED

The ticket's diagnosis blamed `LastTypeStrCap` as a stale channel — **and
`LastTypeStrCap` genuinely IS the stale channel `defs.inc` documents at length.**
The story fit the junk perfectly and **stopped the search one arm short of the
arm that is never ENTERED.**

What separated them was **not a probe but a two-line program**: a neighbouring
`pad: string[17]` making the field clamp at 17 is not something any theory about
alias resolution predicts. **A plausible mechanism that is really present in the
codebase is the most expensive kind of wrong answer**, because every check you
run against it confirms it.

### Verification

x86-64, i386, arm32, aarch64, riscv32 in both modes, plus an xtensa compile. New
regression `test_dyn_frozen_field_capacity.pas` wired native + four cross
batteries, both modes — **a positive control: red on `c709788d39ad` in both
modes**, the default one printing heap descriptor bytes from inside a string.

**frankb-78's acceptance rows re-run because it asked, not on franka-29's own
census** — all eight of `test_string_n_container_strides` including `dyn2dvals`,
green on all five runnable targets in both modes. frankb-78 was right that six of
its eight rows are stride rows that cannot see a value bug. `gate.sh quick` GREEN
**(grepped the log, not the wrapper)**; self-host `converged after 1 round`.

Coordination: franka-29 messaged frankb-78 directly before entering
`SetLenDynElemSize` and was cleared. **Peer-to-peer, no routing through the
coordinator, which is the arrangement working as intended.**

## 2026-09-03 — a real topic collision, and a RE-LANE justified by probes that could not fail

Not shortstring. Banked here because the second half is this file's central class
arriving in a new place: **a conclusion drawn from an absence the instrument
manufactured.**

### The collision — the one thing git cannot show

Both worker checkouts held uncommitted work on
`bug-a-i386-a-pointer-is-register-and-memory-resident-at-once-across-a-goto-entered-loop`:
one a **staged rename** into `working/` (a claim), the other `compiler/cparser.inc`,
`Makefile`, `tools/gate.sh` and **four new C test cases** (the work).

**Both diffs would have applied cleanly.** A rename and edits to the same file do
not conflict, so the ticket would have landed in `working/` owned by one session
while the other's fix landed under it — noticed only when two half-fixes appeared
with different test names. Confirmed by both sessions as **not coordinated**; the
claim was ~4 minutes old and had no code behind it. Released cleanly, tree back
at HEAD, and the releasing session **messaged the other directly rather than
leaving it to discover the slot was free.**

### The finding: the ticket's TITLE and LANE were both wrong

It is **not i386, not register allocation, not the backend.** `ParseCDoWhileAST`
desugared do-while through a **first-iteration FLAG**, and a `goto` into the body
skips both writes to it, so the back edge short-circuits `flag or cond` and takes
an extra pass **without evaluating `cond`**. Now `AN_REPEAT`.

**The sibling, same defect, found by looking for it rather than by it failing:**
`ParseCForAST` guarded a `for`'s post-expression with the identical flag, so a
`goto` into the body **skips the post on the first back edge** — and that one
reproduces on x86-64 too. Fourth time today the *"an enumeration exists beside a
complete one"* tell has paid, and the first time it was applied **prospectively**.

Anyone starting from that title instruments i386 codegen and finds nothing, which
is what the last three passes did. Title, summary and lane corrected in the same
commit.

### A PROBE FOR THIS MUST DIRTY THE STACK FIRST — and this explains the re-lane

Five earlier minimal probes — **including one that was exactly a `goto` into a
do-while body** — cleared a shape they had in fact caught, because **in a fresh
frame the uninitialised flag reads ZERO, and zero is accidentally the correct
value.**

> **MINIMISING A REPRO CAN DESTROY IT.** The failure value is whatever the
> surrounding machinery leaves behind, and a minimal probe is the most likely
> thing to leave behind exactly the value you were hoping to see.

**The two halves nobody held together.** One session had the re-lane's
provenance: the ticket was explicitly moved to Track A carrying the sentence
*"this is i386 backend code generation, not the C frontend"*, **on the strength
of four probes that failed to reproduce it at C level.** The other had the reason
those probes were empty. Neither could see the other's half.

So the re-lane was **not sloppy reasoning** — it was a sound inference from four
instruments that could not fail, and its conclusion was drawn from an absence the
probes' own cleanliness produced. **A re-lane justified by non-reproduction is
only as good as the probes' ability to reproduce**, and this family's probes go
quiet precisely when minimised. Recorded so the ticket's CONCLUSION is corrected,
not merely its status.

### Surfaced to the owner, deliberately not acted on

**`test-c-conformance` is SKIPPING ENTIRELY** — the gitignored `c-testsuite`
corpus is not installed on this box — so that battery has **measured nothing for
an unknown period, while a summary line printed "all targets green" over four
skips.** The summary line is fixed; **installing the corpus needs a network fetch
and is the owner's call**, so nobody ran it. The open, non-fetch half is
establishing how long it has been skipping and what it would have covered, which
decides whether this is paperwork or a hole with real defects behind it.

### Coordinator note, logged against itself

The seat recommended the p55 open-array ticket to a session that already knew it
was taken — the other worker had told it directly that morning. **Peer-to-peer
carried a fact the coordinator never saw.** That is the arrangement working as
designed, not a gap to close by routing more through the seat; the correct output
is *"no KNOWN hold"*, never *"no hold"*.

### RETRACTED — the C-conformance "coverage hole" was PAPERWORK, and this seat escalated it wrongly

`2f58b23be`, verified on origin. **The section above surfaced this to the owner
as a battery that had "measured nothing for an unknown period" and needed a
network fetch. That was wrong, and the escalation should not have been made.**

seven publishes all 30 `test-c-conformance*` jobs as `pass`, with
`job_last_pass` equal to `0975f200bd17` — its most recent FULL tier, today
12:57Z. **The battery ran, on the host that runs Track T, at the current tip.**
Not a stale green from an older sha: the last-pass sha IS the last-run sha.

**WHY BOTH READINGS LOOKED RIGHT — the corpus is gitignored, so its presence is
PER-CHECKOUT, not per-box.** Present in 6 of the 24 checkouts under `/home/neo`
(`pxx`, `frank1`, `frankC`, `frankD`, `frankZ`, and `trackt-watch` — **the clone
that PRODUCES those reports**), 879 files each. Absent in `frankA` and `frankB`,
which is where the SKIP was seen. **Nothing was uncovered for any period; a
session ran the battery in a checkout that never had the corpus.**

So there are no defects hiding behind it and **the owner needs to fetch
nothing** — only if he wants that battery runnable in every checkout.

**The defect that IS real and must not be discounted by this retraction:**
`test-c-conformance-cross` printed `all targets green` over four skips. **A
summary line that cannot say no** — the class this repo already has a rule for,
and the reason a local skip read as a coverage hole in the first place.

**What this seat got wrong:** it took one session's observation of a local SKIP
and reported it as a property of the harness, to the owner, as something needing
his authority. The observation was accurate and the inference crossed a boundary
the evidence did not — **per-checkout state read as per-box state.** The
discriminator cost one grep and was available before the escalation.

### A VACUOUS ZERO, CHECKED AND RECORDED AS VACUOUS RATHER THAN REPORTED

To answer *"how long has it been skipping"*, franka-29 grepped each host's
`history` array for a past c-conformance skip and got **zero across all four
hosts** — and threw the number away rather than reporting it.

**History entries carry `date`, `sha`, `tier`, `verdict`, `new_red` and `fixed`,
and NO per-job status at all**, so they are **physically unable to record a
skip.** The instrument cannot observe the quantity and returns a clean zero
rather than an error. (The window is also narrow: seven's 50 entries span only
2026-09-02T20:01Z to now.)

`job_last_pass` is the field that can answer *"when did this job last really
run"*, and the answer above rests on that instead. **The vacuous zero is in the
logbook beside the result, because a bare "no skips in history" would have read
as the strongest sentence in the report.**

## 2026-09-03 — the goto-loop fix (`72c431bd9`), and A REVIEW GATE THAT FIRED ONLY WHERE NOBODY LOOKS

### The refinement that makes the probe rule usable

*"Dirty the stack first"* is **not enough as a rule.** frankb-78's first for-loop
probe called `dirty()` **inside the function under test**, which writes BELOW
that frame and changes nothing — **it passed on every target while the bug was
live.**

> **The dirtying call must come FROM THE CALLER: leave the bytes where the frame
> under test will SIT.**

A probe that dirties its own frame is the same shape as a guard aimed inside the
population — it is doing work in a place the defect cannot see.

### The discriminator, and a trace that was wrong invisibly

The busybox `mv` row went **FAIL -> byte-identical to the gcc oracle over all 14
cases ON THE FRONTEND CHANGE ALONE**. So the instrumented trace's
"pointer-is-register-and-memory-resident-at-once" reading was **wrong, and wrong
in a way invisible from the trace itself**: the extra pass never evaluated the
condition, so `*++argv` never ran, so `argv` legitimately held one address at
both prints. **No i386 residual** — if one appears later it is a new defect.

**A trace can be internally consistent and describe a phenomenon that does not
exist**, when the thing it failed to record is a statement that never executed.

### THE ONE TO BROADCAST — a red shipped while every gate said green

`d49de34b6` (this afternoon) added **two legitimate AST child writes** and left
`test/ast_slot_writes.expected` stale. **That census only ran in `make
test-core`, which the per-fix loop does not run** — so `make compiler/pascal26`
and `gate.sh quick` were both GREEN over a red row for hours, and it surfaced
only because a later change happened to need the full tier.

> **A REVIEW GATE THAT FIRES ONLY WHERE NOBODY LOOKS REVIEWS NOTHING.**

And this one is not bookkeeping: it guards `ASTLeft`/`ASTRight` being **children
for most kinds and a payload for a few** — i.e. **generic-walker memory
corruption.**

Now a `gate.sh quick` step (~5s, `tools/gate.sh:311-315`, verified present),
running its own `--self-check` as the positive control.

**FLEET NOTICE:** anyone editing AST slot writes will now see a RED there that
nobody has seen before. **`tools/ast_slot_overloads.py --update` after READING
the diff** is the correct response when every new row is a real child node.

### Verification status, stated with one row still in flight

`gate.sh quick` GREEN with `compiler/**` uncommitted (FPC seed canary ran);
self-host `converged after 1 round`; busybox i386 green with both fixes; both new
tests match gcc on native + i386 + aarch64 + arm32 + riscv32 **with the pinned
control firing**. `make test-core` was **still running and unread** at report
time, and frankb-78 said so rather than implying a verdict — committing ahead of
it deliberately rather than sitting on a dirty tree.

### A PARTIAL PUSH LOOKS EXACTLY LIKE A COMPLETE ONE FROM INSIDE

frankb-78 reported *"three commits, all verified on origin"*. **One was.** The
other two — the epitaph and the corpus ticket — were still local, `frankB`
`ahead=2`, **while a full tier ran that a restart could have interrupted.**

The fix pushed, so the sync LOOKED like it worked. Checked by SUBJECT on
`origin/master` as well as by sha, because this repo rebases nearly every sync
and a pre-push sha is a ghost by construction — **neither subject was there, and
the ticket file did not exist in another checkout.** That is the discriminator
between a ghost sha and genuinely unpushed work: **a ghost has a twin with the
same subject; unpushed work has nothing at all.**

## 2026-09-03 — `private` for parallel-for (`b67d943eb`), and a SEED CONTROL that proved itself accidental

### The control is the finding

franka-29 chose to SEED where OpenMP deliberately leaves `private`
uninitialised, then asked whether the seed could be **shown** to matter — by
building a compiler with the seed emission disabled and changing nothing else.

**The SEED row printed 11, not 0.** The `Integer` and the `Double` came back
dirty; **the `Boolean` and the `Char` landed on zero bytes and PASSED.** Two of
four components fired.

> **The unseeded behaviour is accidentally correct most of the time** — the same
> sentence as the do-while flag, from the other end. **Which components catch it
> is a property of the FRAME LAYOUT, not of the defect**, which is why the test
> keeps all four with distinct weights rather than the two that happened to fire.

Without that control, a seed believed-in would have shipped beside a row nobody
could tell from a guard that cannot fail. **This is the third instance today of
a probe whose failure value collides with its correct value, and the first where
the author manufactured the collision deliberately to measure it.**

The motivating shape: a loop that must total 300000 gave 298051 / 298141 /
299650 / 299462 / 299233 over five runs with the clause removed, **exit 0 every
time**, and 300000 over twenty with it.

### The managed half used the RIGHT instrument, not the convenient one

A private `AnsiString` had to be pinned to one worker. **Every `expect_same` row
would have passed over a per-iteration leak**, so it ran `-dPXX_ALLOC_CENSUS`:
4000 iterations `allocs=10975 frees=10972 live=3`; 16000 iterations
`allocs=45116 frees=45111 live=5`. **Four times the work, live flat.** Assertion
class matched to defect class — the open-array-leak rule applied without being
told.

### `Char(0)` not `Chr(0)` — the name-is-not-the-thing rule in miniature

`tkChr` **greps as thoroughly live**: six backends test `-Ord(tkChr)`. **Every
one of those is an INTRINSIC ID stored in `ASTIVal`. The lexer never emits
`tkChr` as a token.**

And the diagnostic points at the wrong file: a stashed `tkChr` fails as
`expected expression` **INSIDE `lib/rtl/palthread.pas`**, which is where the
synthesized worker body lands — **an error in a file the statement under edit
never mentions.** Cost one rebuild; noted at the site.

### Group discipline

Grepped the clause set before starting: genuinely **one** open Track A ticket
(`feature-opt-heap-per-thread-cache` p48 is in `working/` and someone else's; the
other three are NilPy-lane at p10/p5). **A single ticket is fine — the rule is
against not looking, and it looked.**

`gate.sh quick` GREEN, self-host `converged after 1 round`, verified
x86-64/i386/aarch64/arm32. **riscv32 refuses `--threadsafe` outright and has no
parallel rows, which is why it is not wired** — stated rather than left as an
absent column.

### FLAGGED FOR A DECISION, NOT TAKEN — the p55 open-array ticket is a design fork

`bug-a-address-of-an-open-array-element-points-at-the-marshalling-temp` sits at
**p55 in the ordinary queue**, and its own summary says the fix is a
representation change across **633 `IsArray` sites in 27 files and 6 backends**,
with *"do not start it casually"*. The only alternative — prefixing the
argument's storage — **is impossible for a record field or a 2-D row.**

**Three sessions have now looked at that wall independently.** A p55 queue
position guarantees a fourth will. This is a Track U decision or an umbrella,
not a session's ticket, and the recommendation is to move it there before
someone takes it as ordinary work.

## 2026-09-03 — the capacity-carrier group (`fe68c75cc`, parked): TWO WRITERS, NOT ELEVEN READERS

franka-29 holds the frozen-string capacity carriers and is **parked, not idle**.
No compiler change in that commit. Verified on origin.

### Re-measured at HEAD before touching anything

`p: ^string[8]` storing 16 characters gives **len 16 on x86-64, i386, aarch64,
arm32 and riscv32 in both modes — ten cells** — and the overrun is **visible
rather than inferred**: a neighbouring `g` holding `'GUARD'` prints EMPTY in the
default mode, and hundreds of bytes of adjacent memory under
`-dPXX_SHORTSTRING`.

### IT CORRECTED ITS OWN LARGEST FINDING — the count was right, the DIRECTION was wrong

The ticket said eleven sites spell `if cap <= 0 then cap := DEFAULT_STR_CAP`, so
a missing capacity is read as a permissive one, and offered `SizeOfSlot` — which
guards on `cap > 0` and declines to guess — as the model for fixing all eleven.

**The count is right. The direction is wrong: `0` is not ABSENCE at those sites,
it is a deliberate ENCODING written one level up.** `AllocVar` and `AllocParam`
both spell `if TypeIsFrozenString(tk) and (tk <> tyString) then SymStrCap :=
LastTypeStrCap`, leaving a plain frozen `string` at 0 **on purpose**, and the
downstream substitution is what gives it its capacity.

**Measured rather than read off the guard:** under `-uPXX_MANAGED_STRING`, `var
s: string` with a 300-character store comes back **Length 255 with the neighbour
intact.** So making the eleven decline **would break every plain frozen string.**

The bit that separates the two meanings **already exists and is the destination
KIND** — which is what `SizeOfSlot` actually keys on, **not the zero**.

> **The fix is TWO WRITERS, not eleven readers.** Give a plain frozen `string`
> its real 255 at allocation; then `0` means unset everywhere and each of the
> eleven can become a **diagnostic** instead of a silent overrun.

**This is a deliberate counterweight to today's other class.** Most of this
file's findings are *"a fact that lives in N places was asked of one of them"*,
whose fix is to make the N agree. Here, fixing the N readers is the WRONG move,
because the value they read is meaningful and the ambiguity was introduced by two
writers. **Count the writers before fixing the readers** — an overloaded value is
a writer-side defect wearing a reader-side symptom.

### THE SECOND WRITER WAS FOUND BY AN EDIT THAT ASSERTED ITS MATCH WAS UNIQUE

The guard appears **twice with identical text**, in `AllocVar` and `AllocParam`.
franka-29 was about to make a one-line change; **the uniqueness assert turned it
into a two-site change before anything was built.** A plain replace would have
fixed one arm and left the other — the exact double case
`normalise-dont-special-case.md` names.

> **An edit tool that asserts its match is unique is a SIBLING DETECTOR, and it
> fires before the build rather than after the cross run.**

That is the cheapest instance of today's recurring tell. The others cost a
canary pass, a bisect, and three passes on a mis-titled ticket; this one cost a
failed edit.

### Parked for SEQUENCING, and that is the right call

Both halves are carrier questions, and both sit inside
`feature-p-implement-the-real-tyshortstring-byte-prefix-layout` (prio 100,
`working/`, owner frankB), **which re-types `string[N]`**. The ticket's own
closing note says to check whether that work lands the carrier for free before
adding one.

So franka-29 **asked frankb-78 directly and is waiting**, rather than building a
parallel `LastTypePointerStrCap` that the layout change may invalidate or collide
with — and told it that today's `IRSetLenBaseCap` gives `SetLenDynElemSize` a
**second capacity carrier**, since the layout change touches the same conversion.

**It is touching the prio-100 area only through a question**, and is nowhere near
P3 or the flip. If the answer is "the layout work lands the carrier", it closes
the open half against that; if not, it builds one following
`LastTypePointerStrElemTk`'s existing convention **rather than inventing a
second**.

## 2026-09-03 — tier green, and TWO SESSIONS MADE THE SAME SCOPE ERROR FROM OPPOSITE DIRECTIONS

All shas below verified on origin.

### The verdict

`make test-core` rc=0, **1912 ok rows**, at the tree carrying both loop fixes and
the updated census snapshot. Full record for `72c431bd9`: test-core green,
`gate.sh quick` GREEN with `compiler/**` uncommitted, self-host `converged after
1 round`, busybox i386 byte-identical to the gcc oracle over all 14 cases, both
new tests matching gcc on native+i386+aarch64+arm32+riscv32 **with the pinned
control firing on all four for the `for` case.**

### A self-correction worth more than the verdict

frankb-78 on its own earlier report: *"I told you 'three commits, all verified on
origin' and I had run `sync.sh` ONCE, before two of them existed."*

> **That was not a ghost-sha misreading. It was an UNMEASURED CLAIM IN THE
> SENTENCE THAT WAS SUPPOSED TO CARRY THE MEASUREMENT** — the exact shape it had
> spent the day cataloguing in other people's instruments.

The phrase "verified on origin" is doing the work of a check that never ran, and
it is *more* credible than a bare claim precisely because it names a
verification. **A claim that describes its own verification is the hardest kind
to doubt, and the cheapest kind to write without doing.**

### THE SCOPE SYMMETRY — the same error, twice in one hour, from opposite ends

- frankb-78 **read a DIRECTORY LISTING as a property of the harness** ("the
  corpus is absent, so the battery has measured nothing").
- this seat **read frankb-78's REPORT as a property of the fleet**, and escalated
  it to the owner as a coverage hole needing a network fetch.

> **Neither of us asked what the thing we were measuring was actually SCOPED
> TO.** Both observations were accurate. Both inferences crossed a boundary the
> evidence did not.

Two independent sessions making the identical inference from the identical skip
is why the false claim is **written up as false rather than quietly deleted.**

**The corpus ticket was rewritten BEFORE it landed** (`6edb97dc2`): retitled to
name per-CHECKOUT state, **prio 50 -> 25**, carrying the `job_last_pass`
measurement — *a job cannot pass without its corpus, which is stronger than any
directory listing.* What survives is small, real and stays p25: **`make test-c`
in the two affected checkouts delivers its test-core half and silently drops its
conformance half**, which costs a Track C worker following the documented gate.
Still a network fetch, still the owner's.

### The NEW-RED was not his, and the TELL is a docs-only commit

`f81021cb1` / `1d5db3093`, `test-core#src:test/c_asm_in_inline_body.c@2`. It
compiled clean at `-O2` and `-O3` in frankb-78's run, and `8acf737e3` has it
**GREEN at `addffd2608d3` — a docs-only commit.**

> **A red that clears across a commit which changed no code is the flake's own
> signature.** `e340f51b9` already calls it race-unsafe-on-one-green and declines
> to close it, which is right.

### The open-array fork, moved by its own owner (`72ea3dcc8`)

`decide-should-an-open-array-parameter-become-a-two-word-descriptor`. The bug is
now `blocked-by` it and in `blocked/`, **so `ready --track A` stops offering the
wall** three sessions walked into.

**Arm A is NOT an open-array change** — the one-word `[ptr-8]` convention is
shared with dyn arrays and AnsiString handles, so it is a **wire-format change**
across 633 `IsArray` sites in 27 files and 6 backends.

**Arm B was kept visible precisely BECAUSE it looks cheap.** Prefixing the
argument's own storage works for a local or a global and is **impossible for a
record field or a 2-D row** — so it would leave two behaviours for one construct
**with the second still broken AND LOOKING FIXED.** Documenting the attractive
wrong arm, rather than omitting it, is what stops the next reader re-deriving it.

Recommendation is **C, keep the convention**, on the goal's own test: *the
evidence that settles a compat question is real source that wants the behaviour*,
and every `@a[i]` on an open-array parameter found so far is confined to the
call, where we are already correct.

### AN AUTHORITY BOUNDARY, CORRECTLY DRAWN BY A WORKER

frankb-78 **deliberately did not file it to `known-incompat/`**: that folder
asserts *"ours is CHOSEN"*, and **choosing to spend an FPC-compatible idiom is
above a worker's line.** It routed the choice to Track U instead.

That is the four-folders rule used as a statement about **authority**, not
taxonomy — and it is the distinction that keeps `known-incompat/` meaning
something.

## 2026-09-03 — THE PRE-FLIP CENSUS INVERTED THE QUESTION (`49ce033d0`)

Verified on origin, and the effect verified independently: the compat ticket is
no longer the top row of `ready --track P`.

### The inversion

The coordinator asked *"which open tickets does the flip PROMOTE?"* — assuming
flag-only defects that become default-mode. **Censused by FOLDER (24 open
tickets carry the language, not 20), the answer is NONE.**

> **The flip does not PROMOTE this surface — it RELEASES it.** The edges that
> matter are not blockers pointing OUT of P4; they are consumers pointing IN, and
> three were missing.

### The zero is NOT vacuous, and that was checked before it was reported

`PXX_SHORTSTRING` appears in **exactly one open ticket: P4 itself.** The control
is drawn from the right population — **24 tickets in `done/` name the flag**,
most titled *"under the byte prefix mode"* — so a flag-conditional defect **does**
name it in this repo's idiom, and the grep could have seen that shape. **The
flag-only defects of phases 1–3 were fixed rather than filed. That is why the
count is zero.**

### THE NEAR-MISS — a Track P agent pulling its own top row was being handed the flip

`compat-pascal-four-type-sizes-disagree-with-fpc-and-every-value-agrees` was the
**#1 row of `ready --track P`** at **effective p75** (own prio 25, inherited from
`feature-pascal-typed-and-untyped-files` p70 and `umbrella-sizeof-is-one-answer`
p75 **by two separate paths**) with **no edge to P4**.

Item (1) is done and item (2) moved to its own Track A ticket, so its only
remaining item is *"`string[10]` is 8 bytes where FPC gives 11 inline"* — **which
is P4's declared deliverable.** Now `blocked-by` P4 and off the queue. Its
summary also routed that item to Track U as an open storage-model decision **when
the decision is taken.**

The other two: `refactor-a-the-frozen-string-store-body-is-written-twice-in-three-backends`
said **in PROSE** not to start during the P4 window — **nothing watched the
sentence**, so it is now an edge. `umbrella-sizeof-is-one-answer` names P4 in its
body as the `tyShortString` half of its own thesis and did not list it —
**membership is an edge.**

> **A constraint written as prose in a ticket body is not enforced by anything.
> If it must hold, it is an edge.**

### THE COORDINATOR'S LIST CONFLATED TWO INDEPENDENT FLAGS

`-dPXX_SHORTSTRING` (the byte prefix; **the flip deletes it**) and
`-uPXX_MANAGED_STRING` (the frozen-string **model**; the flip does not touch it)
are **independent axes**. Most of the coordinator's candidate list sat on the
second and is not promoted at all:

- `feature-a-dynamic-array-of-frozen-strings` — managed-string axis.
- `bug-a-a-plain-frozen-string-records-capacity-zero` — managed-string axis.
- `bug-a-setlength-is-refused-for-any-frozen-string-that-is-not-a-plain-symbol` —
  its own summary says *"in both modes, pre-existing and unrelated to the byte
  prefix"*.
- `bug-p-a-nested-dynamic-array-field-mistypes-its-element-as-the-leaf-type` —
  **no frozen-string content at all**, and now closed anyway.
- `bug-a-address-of-an-open-array-element` — its body says *"do not fix this
  inside the byte-prefix feature"*.

**And two the coordinator missed were ALREADY wired correctly** —
`feature-pascal-typed-and-untyped-files` and `feature-d-a-representation-contract`
both carry `blocked-by: P4`. **That is evidence the convention already runs in
the RELEASE direction**, which is what should have told the coordinator its
question was the wrong way round.

### A hazard REFUTED rather than filed

`bug-b-gtk3-pc-writes-past-its-buffer` quotes a `<skip the 8-byte prefix>` FFI
guard, and `ir.inc` carries a dozen literal `+8` prefix skips in the PChar decay
path — **so the flip looked like it would break them.** Measured instead of
asserted, in both modes: `PChar(s)`, `PChar(r.f)`, `PChar(a[0])` and `@s[1]` for
a `string[10]` all print correctly under `-dPXX_SHORTSTRING`. **The decay is
already width-aware; the literal `+8` sites are interned-literal-pool specific.**
Nothing added to the ticket. (Scope: the compiler's decay path, not gtk3's own
`PC()` body.)

### Closed rather than ranked

`bug-p-a-nested-dynamic-array-field-mistypes-its-element-as-the-leaf-type` (p40)
is fixed and in `done/`. **The same defect one element class over** from
`45391912a`, which deleted the second dyn-depth walker (`DynArrayNodeDepth` had
no `AN_FIELD` arm) — **element-type-blind, so the AnsiString spelling went with
the `string[10]` one.** Positive control: pin v401 `766b99f98`, an ancestor of
the fix, reproduces the ticket's error string verbatim in both modes; HEAD passes
with a **type-discriminating** row (`Two(r.v[0])` where `Two` takes `array of
AnsiString` — cannot typecheck if the intermediate is the leaf).

### Correction to the coordinator's held state

franka-29 is **not** waiting on frankb-78 for the pointer-clamp carrier. It was
answered, built, and landed at `c2ad9761e`; the writer-side third finding is
filed separately at p45.

## 2026-09-03 — `owner:` NAMED A CHECKOUT, NOT A SESSION — and a real ABI oracle was already installed

### THE STRUCTURAL ONE: P4 has no holder, and "wait for frankB" was a wait on nobody

`feature-p-implement-the-real-tyshortstring-byte-prefix-layout` carried
`owner: frankB`. **That names a CHECKOUT DIRECTORY, not a session.** No session
has ever claimed it; frankb-78 has never touched it and has been under a standing
instruction to stay off anything that re-types strings.

**For a day, the coordinator read that field as a session and routed on it** —
telling one worker to wait for "frankB's layout work" before building a carrier.
**That was an indefinite wait on nobody**, and the only reason it cost nothing is
that the two workers settled it peer-to-peer before the relay arrived.

> **This repo's own rule, on its own ticket metadata: the name is not the thing.**
> `owner:` is ambiguous between a checkout and a session, and both are spelled
> the same way. A wait routed through an `owner:` field can be a wait on an empty
> string.

Corrected in the frontmatter and hoisted to the front of the summary, because
**the flip is the one ticket where "who holds this" will be asked at exactly the
wrong moment.**

### And the relay was stale three times

The coordinator relayed *"franka-29 is still parked waiting on your answer"*
**three times against a session that had been unblocked for hours** — the answer
was given, the carrier built and landed (`c2ad9761e`), and the classification
taken. **Peer-to-peer beat the relay exactly as the roster says it should; the
fact simply never reached the seat.** A relay repeating a stale premise is worse
than silence, because it is asserted in the coordinator's voice.

### A REAL ABI ORACLE WAS ALREADY INSTALLED — and the earlier note was too narrow

`~/.cache/pxx-cross/{aarch64,arm32}/lib/` holds a **complete glibc** (verified:
`ld-linux-aarch64.so.1`, `libc.so.6`, and the arm32 equivalents), `run_target.sh`
already points `QEMU_LD_PREFIX` at it, and pxx already emits dynamic imports for
those targets. **So a pxx caller and a gcc-built glibc exchange arguments across
a real ABI boundary, observable through the callee's own output — with NO cross
compiler and NO linker.**

frankb-78's own note an hour earlier (`2dd981a7b`) concluded the missing piece
was a **linker**. **That is true of a static mixed LINK and is not the answer to
"is there an oracle"**, which is what the two ABI tickets actually ask.

> **Same error shape as the corpus one, by the same session, within the hour: a
> narrower question was answered and the answer was allowed to stand for the
> wider one.** Corrected in both tickets rather than rewritten.

### It found a defect within the hour

On aarch64 `sprintf(buf, '[%.2f]', 3.5)` prints **`[0.00]`** where arm32, x86-64
and FPC all print `[3.50]` — and with a trailing integer, **`[1 0.00 0]`: the
argument AFTER the float is lost too**, so it is a **slot-counting**
disagreement, exactly what AAPCS64 §6.4.2 predicts if a variadic `double` goes to
`v0` instead of the general/stack path. **arm32 is the control that makes this a
finding rather than a harness complaint.**

**And the pxx-vs-pxx version is self-consistently WRONG:** the same C program
built against `lib/crtl` prints `[3.50]` on aarch64, because our own `sprintf`
reads the argument back from the same wrong place. **That is a worked example of
why self-consistency is worthless as evidence for a calling convention** — the
claim the by-value-struct ticket has been making in the abstract.

Filed as `bug-a-aarch64-passes-a-variadic-float-in-an-fp-register-so-glibc-reads-zero`,
p55 (verified present).

### The aarch64 row was deliberately NOT wired green

Writing today's wrong answer into a `.expected` would have made the suite green
over a live divergence. **The Makefile says which target is excluded and names
the ticket** — the same call as the strides row this morning, made without
prompting.

## 2026-09-03 — `SetLength` through a field, element or deref (`0dedfb86c`), and the `owner:` field claims a third victim

Verified on origin.

### The fix, for the owner's "complete shortstring as best we can" tally

`SetLength(p^, n)`, `SetLength(r.f, n)` and `SetLength(arr[i], n)` on a frozen
string were **refused everywhere but wasm32** — an FPC-accepted idiom that simply
did not compile. Now works on all seven targets in both modes: **14 cells (7
targets x 2 prefix modes), all byte-identical to FPC 3.2.2**, regression wired
native + four cross. **The pinned compiler REFUSES TO COMPILE that test, which is
the control.**

### wasm32 ALREADY DID IT — and that is a new shape of absent column

Its arm has never required the symbol-shaped operand the other six demanded; it
compiles and runs the field and deref shapes **at the pin's tree**, and the
managed AnsiString path had all three working beside it. So the work was a copy,
not a design.

> **A ticket's target list is written from the targets that FAILED — so a backend
> that has drifted toward CORRECT is the one systematically absent from it.**

This file already records absent columns as places a defect hides. This is the
inverse: **the absent column was the working implementation**, and it sat
unnoticed because nothing writes down a target that did not fail. **Running the
repro on all seven cost a minute.**

### The ticket was wrong about the COUNT OF CAUSES

It recorded all three shapes dying in the `-101` arm. **The element shape never
reached it.** The classifier's `AN_INDEX` arm answered *"array"* unconditionally
and sent it to the dyn-array builtin, so it surfaced as `SetLength expects an
ARRAY variable` — **a diagnostic about a different concept, which is exactly how
it stayed invisible in the ticket's own summary.**

A wrong diagnostic does not merely fail to help; **it re-describes the defect as
belonging to another subsystem**, and the summary then carries that description
forward.

### THE `owner:` FIELD HAS NOW MISLED THREE READERS IN ONE DAY

franka-29, an hour before fixing it, **wrote into that ticket that the arms could
not be touched without colliding with in-flight phase-4 work, and parked.** There
is no in-flight phase-4 work. `owner: frankB` names a **checkout** — the same
misreading of the same field the coordinator made, and that frankb-78 had to
correct twice.

**The paragraph is struck through in the ticket rather than deleted**, with the
reason: **a false LIMIT is quieter than a false FIX and gets believed by the next
reader.** A wrong fix fails a test; a wrong reason not to act produces nothing at
all, and nothing looks like diligence.

Its standing rule, adopted: **an `owner:` field may never be a reason to park.**

**Census, because this is not a one-off.** Open tickets carrying a CHECKOUT name
in `owner:`: **`frankS` 7, `frankA` 6, `frankC` 3, `frankwasm` 2 — 18 tickets**
any of which can be read as a session hold and become a reason to wait on nobody.
(30 say `unassigned` and ~55 are empty, which are both honest.)

### A SEQUENCING WARNING AIMED AT THE COORDINATOR, and it is right

> The owner's plan is **complete shortstring work FIRST, then pause and flip.**
> **"Pause everything" is NOT in force yet, and reading it as already in force is
> an argument for doing nothing.**

A relayed future constraint is easily heard as a present one. The seat must say
which.

## 2026-09-03 16:51 — four NEW native reds, and a suspect found without building anything

`native` went GREEN (`5e2dcc37c253`) -> RED (`91b4b77ec631`). Four new rows, all
in the frozen/SetLength family: `test_alias_cast_assign_target`,
`test_field_rooted_nested_dyn_frozen_index` @1 and @2, and
`test_string_n_container_strides`. Three tickets auto-filed under
`devdocs/progress/backlog/`, prio 70.

### The window had exactly one code commit, and refs alone said so

Six commits sit between the two tested shas. Diffing each for `compiler/`,
`lib/`, `test/`, `tools/` or `Makefile`: **five touch none.** The sixth is
`0dedfb86c` — the SetLength fix banked two hours earlier — touching the Makefile,
`ir_codegen.inc`, five backend arms and `pasparser_stmt.inc`.

**A bisect by construction, at the cost of one `merge-base` and five `show
--stat`.** No build, no repro, no compiler. Worth naming as a technique: when the
green and red shas are both known, the window is usually mostly bookkeeping, and
**the set of commits that touch code is often a single element.** Reach for that
before reaching for a build.

### AND IT MAY NOT BE A REGRESSION AT ALL

The alias-cast row's failing step is a `grep -q 'SetLength expects a'` — **it
asserts the compiler still REFUSES something.** `0dedfb86c` deliberately WIDENED
what `SetLength` accepts. **A refusal test going red is exactly what an intended
widening looks like**, and in that case the test is the thing to update and there
is no defect.

So the same four-row RED is consistent with two opposite stories — a real
regression, or a correct change meeting a stale assertion — and **the verdict
cannot tell them apart, because a refusal test and a value test both just say
`fail`.** The discriminator is the author's INTENT, which lives in no instrument.
Routed to franka-29 as a question, not a verdict.

### Re-laned on commit content, not on the failing step

The auto-filer guessed P, T and T from the failing STEP, flagging each as a
fallback and inviting correction. All three moved to **A**: the suspect commit is
`fix(A)` in codegen and `pasparser_stmt`. Metadata only — the ranker reads
frontmatter, so a mis-laned ticket is a routing defect, which is the one kind of
defect this seat owns.

### Range hygiene, relayed

frankb-78 is bisecting pin v401..HEAD for the x86-64 `frozenVar = ansiVar`
regression, and `0dedfb86c` landed INSIDE that range while it was measuring. If
its BAD endpoint is a fixed sha, nothing moved; if it resolves HEAD fresh each
build, the endpoint drifted six commits. **A bisect whose endpoint moves does not
fail loudly — it converges on the wrong commit and prints a confident answer.**
`0dedfb86c` did not touch the x86-64 arm by name, so it may be irrelevant to that
bug; the point relayed was hygiene, not a claim.

## 2026-09-03 18:59 — `f199ca260`: both regressions were real, and my "maybe a widening" caveat was right for the wrong reason

Verified on origin. Both causes in `0dedfb86c`, both fixed, gate GREEN, 14 cells
re-measured. The three auto-filed tickets are closed against it. **Neither was a
stale assertion**, so the re-lane to A was right and the "maybe the test needs
updating" arm was wrong — usefully wrong, see below.

### Cause 1 — the depth question has to be asked BEFORE the element question

The classifier asked *"is the element a frozen string"* of an `AN_INDEX` target.
**One index into a DEPTH-2 dynamic array yields a depth-1 ARRAY, and `ASTTk`
reports the ELEMENT's kind for it** — so `SetLength(v[0], 1)` on
`array of array of string[10]` took the string arm and **wrote a length prefix
over the sub-array's handle.**

**Depth decides what the target IS; element kind only separates the two leaf
cases.** Asking them in the wrong order is not a missing case — it is a
well-formed question asked of the wrong node.

### Cause 2 — A DEFAULT THAT IS A REAL ANSWER CANNOT SAY "NOT APPLICABLE"

`SetLength(TI(i), 5)` for `TI = Integer` was being **ACCEPTED**. The membership
test was `TypeIsFrozenString(IRFrozenKindOfAddr(n))`, and
**`IRFrozenKindOfAddr` returns `tyString` when it cannot determine the kind.**

That default is *deliberate and correct* for its own callers — a reader that
already KNOWS it has a string and needs only the width. It is useless as a
predicate, because `TypeIsFrozenString(tyString)` is True for **every** node, an
`Integer` included. **The function never errs; it answers a different question,
and the wide default is indistinguishable from a real hit.**

This repo already says *"if the machinery did nothing at all, would this row
still pass?"* about a TEST's expected value. **This is the same defect one level
down, in a FUNCTION's return:** where a routine's don't-know value is also a
legitimate answer, **every caller that reads it as a predicate is a guard that
cannot fail.** Fixed with `IRNodeIsFrozenStrAddr` (`compiler/ir.inc:16223`,
called from the six codegen arms): same arms, same order, **False where the
walker defaults** — and the walker keeps its default for its own callers.

**Ask of any reused helper: what does it return when it does not know, and is
that value inside the range I am about to test?**

### THE PART TO KEEP — a refusal test can be the ONLY instrument aimed at a silent write

I raised, from refs alone, that a red refusal test is what an INTENDED WIDENING
looks like, and told franka-29 the test might be the thing to update. **The
structure of that reasoning was sound and the conclusion was wrong, and it was
hiding something worse than the regression I was hedging about.**

Accepting `SetLength` on an integer is **silent**: it compiles, it runs, and it
writes a length prefix over the integer's storage. **Every value assertion in the
suite still passes.** The only row that can fail is the one asserting a REFUSAL.

> **A red refusal test is not merely "maybe an intended widening". It is
> sometimes the only instrument in the tree pointed at a silent memory write.**

That is the assertion-class rule again — the one the open-array leak paid for —
in its second habitat: **a silent-accept defect cannot fail a value check, BY
CONSTRUCTION**, exactly as a leak cannot. The test's own header says it exists
for this, and a previous widening (`850a9e4cd`) broke a shape nobody watched the
same way. **So the correct move on a red refusal row is to establish intent
FIRST — never to update the assertion because the change "was meant to widen".**
The counter-case now lives in `test_setlength_frozen_lvalue_shapes.pas` as the
`nest` row, so the file that motivated the widening also asserts the direction it
must not widen into.

### `gate.sh quick` was GREEN before the push

Quick runs none of the four. **Not a complaint about quick** — it is the argument
for T's ~8-commit sampling, which caught this in about forty minutes.

## 2026-09-03 19:00 — the bisect nobody was running, and a predicate layer that has now failed four times

### THE MISATTRIBUTION, AND IT WAS MINE

I told frankb-78 its bisect range had moved under it. **frankb-78 is not running
a bisect and never was this session.** I took the claim from my own recurring
watch prompt's STATE block and relayed it **in the coordinator's voice**, which
is what made it credible — the same class already banked twice today, third
instance, and this time the seat that banked it was the one that did it.

**The tell was free and I did not take it:** nothing frankb-78 had reported all
session mentioned a bisect, a v401 range, or a comparison under the flag. A
STATE block describes what someone BELIEVED at the time it was written; it is
not a live reading, and **a standing brief is exactly the kind of instrument
that does not error when it goes stale.**

### AND THE BISECT WAS NOT REAL — BOTH BLOCKERS WERE ALREADY CLOSED

Chased it because frankb-78 asked the right question: *if that bisect is real,
someone else is running it and did not get your warning.* Nobody is.

- `bug-a-i386-comparing-two-elements-of-an-array-of-frozen-strings-is-false`
  (prio 80) — **`done/`**.
- `bug-a-a-frozen-string-compared-to-an-ansistring-is-false-under-the-flag-on-x86-64`
  (prio 70) — **`done/`**, and its summary records the bisect as **already
  complete**: first bad commit `eadf214725a`, the commit that introduced the
  x86-64 byte prefix. **Wrong since the feature landed, not a regression.**

Both resolved by `2bd82200e` at **11:47:06** and moved to `done/` at `68c168230`
at **11:47:15** — nine seconds apart. **The STATE block is stamped "corrected
11:47".** It captured the tree in the last seconds before the close and has been
carried forward every thirty minutes since, asserting two open blockers and a
bisect in progress. **A brief written during the close reads exactly like a brief
written after it.**

**THIS DOES NOT MEAN THE PHASE-4 GATE IS CLEAR AND NOBODY MAY READ IT THAT WAY.**
Two named blockers being closed is a fact about those two tickets. Six phases
have each ended with a defect nobody had filed, and **`f199ca260` — seven hours
after the close — is the seventh.** An empty blocker list has never once been a
release signal in this project. **NO PIN, and the flip stays the owner's.**

### FOUR GUARDS, ONE CONCEPT, TWO COMMITS SEVEN HOURS APART

`2bd82200e` is titled *"three guards asked 'is this a string' of a tag that
stopped answering."* `f199ca260` fixed a membership test reading
`IRFrozenKindOfAddr`, whose don't-know default is `tyString`.

**That is four guards in one day, in one layer, all asking "is this a string" of
something that cannot answer the question they are asking** — one tag that
stopped answering, one width oracle that always answers yes. This repo's own
rule: two mechanisms serving one concept is a smell, three is a design flaw.
**We are at four, and they were found by two different sessions who did not know
they were on the same defect.** The next one should be a search for the
REMAINING callers of every kind-ish oracle used as a predicate, not another
point fix.

### frankb-78: the aarch64 variadic float fix, BUILT GREEN AND REVERTED

`c7c5cbf65` (Pascal-side variadic, landed) and **`08b0f50df`**, which is the one
to read. It **built the aarch64 variadic-float fix, measured it GREEN against
glibc, and took it back out.** AAPCS64 §6.4.2 is now settled by MEASUREMENT:
glibc went `[0.00]` -> `[3.50]` and `[1 0.00 0]` -> `[1 3.50 2]`, and the new
varargs test matched fpc on aarch64.

**Then the positive control it nearly skipped, which is the whole story:** a
plain `printf("%.2f", x)` C program on aarch64 went **3.00 -> 0.00**. `lib/crtl`'s
printf is a pxx-compiled variadic CALLEE on the same arm, and its aarch64
register-save prologue stores `x0..x7` only, deliberately. **Caller and callee
are self-consistently all-GP today, so pxx->crtl works and only a FOREIGN callee
sees the bug. Fixing the caller alone INVERTS the pair.**

> **A change that makes glibc right and crtl wrong is not progress**, so it is
> out of the tree rather than parked in it.

Kept: `ABIA64SlotWalk` (`compiler/abi.inc`), the placement walk split to run over
a per-argument class vector — behaviour-identical, green, and the mechanism the
real fix needs, **so the next attempt starts from one walk with two sources
rather than writing a second.** That is `normalise-dont-special-case` executed in
advance of the change that needs it.

Its tree was at `45397c903` throughout, predating both `0dedfb86c` and
`f199ca260`, and it did not pull during the run — **which is the only reason it
can say its rc=0 is about a known tree.** It scoped the claim to its own tree and
explicitly did not claim it about HEAD.

## 2026-09-03 19:30 — the aarch64 variadic float, landed as a WHOLE change (reported, NOT yet pushed)

**Status when reported: `test-core` still running, nothing pushed.** Recorded as
a peer's report, not as a landed fact. The revert is `08b0f50df`; this is the
second attempt, with all three sites in and **the two directions green at the
same time for the first time.**

- **Caller:** the variadic arm calling `EmitCallArgRegsA64` — pxx's INTERNAL
  all-GP convention — is **deleted rather than fixed.** Both C-ABI arms build one
  per-ARGUMENT class vector and run the single `ABIA64SlotWalk` over it, taking
  each class from the PARAMETER inside the declared list and from the ARGUMENT's
  own IR type past it. That is `Arm32CdeclArgKind`'s shape — **the 32-bit target
  that already got this right** — so it is a spelling the repo already trusts.
- **Callee:** the variadic-save prologue stores `d0..d7` at save-area offset 64
  beside `x0..x7` at 0, and the overflow anchor **asks a placement walk instead
  of comparing `ProcNamedGP + ProcNamedFP` against 8.** A named parameter spills
  when its OWN bank fills; **the combined count is the all-GP model wearing a
  different hat.**

### A HELPER THAT TAKES A COUNT AND DOES THE ARITHMETIC HAS CLAIMED A LAYOUT

`__pxx_va_start_impl` took slot COUNTS and computed `gp_offset = ngp*8`,
`fp_offset = 48 + nfp*16`. **Those constants are SysV's save-area layout**, so a
helper that looked like it took a count had silently claimed a layout — **and
that is the mechanical reason aarch64 could not have an FP region at all**, not
an oversight anyone made about aarch64. It takes BYTE offsets now; the frontend,
which knows the target, computes them. x86-64's numbers are unchanged, only
moved.

**[NARROWED 19:45 BY ITS AUTHOR — see the correction at the end of this file.
The cross-link below is frankb-78's INFERENCE, not a measurement, and the
count that follows was mine and is withdrawn.]**

**This is the `IRFrozenKindOfAddr` finding one turn further out.** There a reused
helper's **RETURN** carried a hidden claim (a don't-know value that was also a
real answer); here its **PARAMETER** does (a count that only means anything under
one layout). Same defect, both ends of the signature:

> **A helper's signature can carry a claim its name does not mention — on the way
> in as well as on the way out.** Ask of a reused routine not only what it
> returns when it does not know, but what it must already believe to interpret
> what you hand it.

~~That makes it five in this family today, across three sessions.~~
**WITHDRAWN — this count was the coordinator's and it was built by inference.**
The IN direction has **one worked example plus one already-cured sibling in the
same file**. See the correction at the end of this file.

### THE GUARD IS TWO TESTS AND NEITHER IS SUFFICIENT ALONE

`test_pascal_varargs_external` gains its aarch64 row (foreign callee, glibc, fpc
oracle) and a new `test/cvararg_fp_bank_cross.c` runs native/aarch64/arm32/i386/
riscv32 for the pxx-callee direction through crtl (gcc oracle).

**Every C variadic test in the suite was native-only — exactly where this defect
does not exist.** And the two directions are not redundant: **one direction
cannot tell a correct convention from two sides wrong the same way.** That is the
self-consistency trap that made the first attempt look green, stated as a test
requirement.

### THE POSITIVE CONTROL WAS RUN, NOT REASONED ABOUT

Disabling ONE line — the callee's FP-bank selection, precisely the half-change
that was reverted — fires both probes on aarch64 (`separate=3.00->0.00`,
`scaled=6.00->2.00`, `sumd=55.00->0.00`) and **NEITHER on native**, then restored
to **the same binary sha `a85892f216a9`.** So the new rows fail on the population
they are about, stay quiet on the one they are not, **and fail on the specific
wrong state that looked green a day ago.** Restoring to an identical sha is the
part that makes it a control rather than two builds.

### FOUND AND DELIBERATELY NOT FIXED — recorded as a CHOICE

The same arm saves `x0..x7` across the hidden-destination evaluation and not
`v0..v7`, and its own comment says the arguments are in both. The change makes
that wider. **Still reachable by no program** — the arm serves externals and
Pascal-mode prototypes only, and no libc returns an aggregate by value while
taking a float — and it was PROBED for and could not be reached. Filed with the
shape and an explicit *"do not land it without a program that fails first"*.

> **A codegen change nothing can exercise is a change made on belief**, and this
> repo's rule about deleting code you merely believe is dead cuts exactly the
> same way for ADDING it.

## 2026-09-03 19:45 — CORRECTION: the count was mine, and the claim is in the BODY not the signature

frankb-78 narrowed its own finding after I banked it. **Both overreaches were
mine, added in the banking, not in its report** — the earlier section is
annotated in place rather than rewritten, so the shape of the error stays
visible.

### 1. "Five in this family today, across three sessions" is WITHDRAWN

That count was **built by inference and I published it in the coordinator's
voice**, which is the third time today that combination has produced something
false. frankb-78's own words: *"two cases pointing the same direction on one day
is how yesterday's phantom structural finding got built."* `IRFrozenKindOfAddr`
is franka-29's, **a different mechanism, found a different way**; calling them
one family is a hypothesis, and I wrote it as a tally.

**The evidence line, which is what the record now carries: ONE worked example,
plus ONE already-cured sibling in the same file.** Nobody may read it as a survey
result.

### 2. THE PARAMETER IS HONEST — THE ARITHMETIC BEHIND IT IS NOT

I wrote that the *signature* carries the hidden claim. It does not, and **that is
precisely what makes it invisible.** `nfp` is honestly named: it really is a
count of named FP parameters. What is nowhere in the signature is that the callee
turns it into `48 + nfp*16`, and those two constants are SysV's save-area layout.

> **The parameter is layout-neutral and the arithmetic behind it is not, so a
> caller on another layout reads the signature CORRECTLY and is still wrong.**

A misleading name is a hazard anyone can learn to distrust. **An honest name over
a body that assumes a layout defeats reading the signature at all**, which is the
only thing most callers do.

### 3. The discriminator is CONCRETE, and it beats my standing question

Mine was *"what must it already believe to interpret what you hand it"* — right
in shape, and not something you can grep for. frankb-78's is:

> **Look for a parameter that is a COUNT or an INDEX rather than a quantity in
> the callee's own units — bytes, an address, an offset. A count has to be
> multiplied by something to be used, and that something is a layout the caller
> never named and cannot see.**

`ngp`/`nfp` are the shape. **`gpbytes`/`regsize` in `__pxx_va_start_impl32` are
the already-cured shape, sitting in the same file** — and that sibling is why
this is worth stating as a rule at all rather than as one instance. Passing bytes
moves the layout to the one place that knows the target.

### 4. Two corrections frankb-78 volunteered against itself

**The xtensa row does not exist and it is not about varargs.** It had said the
new test "COMPILE-FAILs at typedef", which reads as a C frontend gap it found. It
is not: `--target=xtensa --platform=posix` answers *"C program entry stub not
implemented for this target yet"* for `int main(void){return 0;}` with nothing
but `<stdio.h>`. **No C program compiles for xtensa today**, and the `typedef` in
the error is just the first line of the header it was reading when it gave up.
Pre-existing, unrelated, deliberately not filed. **An error message names where
the compiler STOPPED, not what it could not do** — and a plausible-looking token
in it invents a finding.

**The ten new rows have now run inside `test-core` and it continued past them.**
`expect_same.sh` aborts the recipe on a mismatch, so continuing IS passing. Its
own weighting, which is the right one: **worth exactly one notch of confidence,
not two — same binary, same oracles, same machine** as the standalone runs. Still
running; rc and push after it, not before.

## 2026-09-03 20:00 — the frozen dyn-array premise was FALSE, and the target list lied in the OTHER direction

franka-29 took `feature-a-dynamic-array-of-frozen-strings` and **refuted it
instead of implementing it** (`74326e51b`, logbook `9be382451`). Now blocked on
a Track U fork it filed the same hour.

### The ticket said "no path knows its stride". The stride is 8,388,616 bytes.

`STRING_CAP + 8`, taken from **the ARRAY VARIABLE's storage class** — a category
error for a dynamic array whose elements live on the heap and are neither global
nor stack-local.

**And only x86-64 refuses.** i386, aarch64, arm32 and riscv32 all ACCEPT
`array of string` in the frozen model, print **byte-identical to FPC 3.2.2 on
three elements**, and **SIGSEGV at 1000**. Reproduced on **pin v401** — the
control that says none of this is recent and none of it is franka-29's.

> **So x86-64's refusal is the only honest behaviour of the six, and this was
> never a missing implementation.**

### THE TARGET LIST IS UNRELIABLE IN BOTH DIRECTIONS, AND TODAY SHOWED BOTH

This morning: one backend had drifted toward **CORRECT** (wasm32 already did
SetLength), and was therefore **absent from the ticket's target list**, because a
list is written from the targets that FAILED.

This evening, **the same class with the sign flipped**: four backends drifted
toward a **WRONG-BUT-WORKING** answer, and **the one that refuses reads as the
laggard.** A ticket describing x86-64 as the gap had it exactly backwards.

> **Both times, "which targets fail" was the cheap question — and both times the
> answer inverted the ticket.** Absence in a target list means nobody looked, and
> it can hide a target that is ahead OR a majority that is wrong together.

### Why it is a DECISION and not a bug

A plain frozen `string` is **ALLOCATED** at 8,388,616 as a global, 264 as a
local, 264 as a record field — and **CLAMPED at 255 in all three.**

The measurement discipline is the part to copy: it checked the clamp against a
**direct 300-char literal assignment as well as concat**, because *a concat-only
clamp would have meant a global really could hold 8 MB* — the two are
indistinguishable if you only test concat. And it carried a **denominator**:
three `string` globals move bss from 38,732 to 25,204,580 against a no-string
control, **exactly 3 x 8,388,616**. So **8,388,352 bytes of every global plain
frozen string are unreachable by construction.**

Two readings, both internally consistent, **neither derivable from the code — and
each has a constant written as though it were already the answer.** `STRING_CAP`
is named and commented `{ 8 MB }` and chosen by storage class at four sites;
`LOCAL_STR_CAP`'s comment says "max string length for local/stack variables".
Against it: every clamp uses `DEFAULT_STR_CAP`, and 264 = 255 + prefix is what a
local and a field already get. Recommended 255, with why 8 MB is not dismissible.
**The stride the feature needs IS this number, so guessing it would have been
guessing the fork.**

### AND IT RETROACTIVELY QUALIFIED ITS OWN LANDED COMMIT

`b84e73e53` records `DEFAULT_STR_CAP` for a plain frozen string, justified as
*"255 IS its N — measured"*. **The measurement was of the CLAMP; the ALLOCATION
disagrees.** Neutral today because the clamp already used 255, so it stays
landed — but it is **one arm of an open fork written into a writer**, and the
ticket now says so.

**Self-qualifying a landed commit on evidence found afterwards is the rarest
move in this repo and the one that keeps a record honest.**

### COORDINATOR ACTIONS — both routing metadata, both revertable on request

1. **The fork was laned `track: A`.** 33 of 36 tickets in `backlog-decide/` are
   `U`, and as filed it appeared at **p45 in `ready --track A`** — offering an
   agent a fork **only the owner can settle**. Re-laned to `U`. (Two other
   off-convention siblings exist and I left them: one `P`, one with an EMPTY
   track.)
2. **`bug-a-a-plain-frozen-string-records-capacity-zero...` had `blocked-by: []`
   while its body recorded the hold.** It was live at p45, so **the next A agent
   to take it would have written 255 — one arm of an open fork — into eleven
   clamp sites.** Edge wired to the fork; it now correctly leaves the queue.

> **A HOLD THAT LIVES IN THE BODY IS A HOLD NOTHING READS.** The ranker reads
> frontmatter. Prose stating a constraint and an empty `blocked-by` beside it is
> the same defect as a summary that has gone stale: honest, present, and invisible
> to the only thing that routes.

Ticket stays in `working/`, claimed, genuinely blocked — the `blocked-by` edge is
what the ranker reads, and `owner:` here names a **real session**, not a checkout.

## 2026-09-03 19:47 — `9fb5655f7`: a TRUE clause, scoped to a narrower question, invented work on two tickets

`1c2219596` — the aarch64 variadic float fix, all three sites — is **landed and
verified on origin**: `make test-core` rc=0 with the ten new rows inside it,
`gate.sh quick` GREEN **with the FPC seed canary actually RUNNING rather than
SKIP**, because it gated while `compiler/**` was still dirty. That is this file's
own *gate-before-you-commit* rule executed correctly, and the canary is the only
thing that catches the declaration-order class. `converged after 1 round(s)`,
sha `a85892f216a9`.

### The find: two tickets said their first deliverable was AN ORACLE

Both carried *"there is no gcc cross for aarch64 on this box, so no mixed link is
constructible and the only available verification is pxx-against-pxx."*

**The clause about a LINK is TRUE.** There is no cross gcc and no `lld`, so
nothing can be linked. **It was answering a narrower question than either ticket
asks.** `clang` is a cross compiler by construction — no sysroot, no cross
binutils — and **if the callees are `extern` and never defined, you are reading
the CALL SITE, so nothing has to link or run.** `llvm-objdump-21` was already
installed and reads pxx's own aarch64/arm32/riscv32 ELF for the other column.

> **A true statement, scoped to a narrower question than the one being asked,
> does not read as an error — it reads as a finding, and it INVENTS WORK.** Two
> tickets each grew an oracle as their first deliverable, and the oracle was
> installed.

This is the file's *"every instrument that lies, lies by being CORRECT ABOUT
SOMETHING ELSE"* — applied not to a tool but to **a reasoned premise sitting in a
ticket summary**, where nothing will ever return an error to contradict it. The
discriminator is the same one as always: **ask what question the sentence
actually answers, not whether it is true.**

### FIVE SHAPES, FOUR WRONG, AND THE FIFTH RIGHT BY ACCIDENT

Measured on aarch64: pxx emits `x0 = &temp, x1 = tail` for **all five** by-value
aggregate shapes. Four are wrong. **The fifth is right by accident** — a 24-byte
struct really IS passed indirectly on AAPCS64.

**And a big struct is exactly the shape someone writing one hand probe would
reach for.**

Banked, at frankb-78's explicit request, **as an INSTANCE of this repo's
"choose a probe whose right answer differs from the default" and NOT as a new
rule** — seen from the other side. There it is the test's expected value
colliding with the failure value; here it is **the BUG's answer colliding with
the SPECIFICATION**, on the single most likely probe. (It declined to promote its
own finding to a new rule. Worth noting on a day when this seat inflated a peer's
hedged inference into a tally twice.)

### FOUR ROWS THAT ARE NOT GUESSABLE FROM THE psABI

The argument for RUNNING an oracle rather than reasoning from a document:

- aarch64 and riscv32 go indirect past a size limit; **arm32 never does.**
- The tail integer lands in `w0`/`r0` after an HFA, because **the two banks
  allocate independently** — so a fix that places the HFA correctly and still
  advances the GP index is wrong **in a way no single-argument probe can see.**
- riscv32 takes `{double,double}` in FP registers but `{float,float,float}`
  **indirectly.**
- `long` is four bytes on the 32-bit targets, so **a struct named for its 64-bit
  size is a different shape there** — the name travels, the layout does not.

### THE SCOPE LIMIT IS WRITTEN ON BOTH TICKETS AND IN THE DOC

> **This is a PLACEMENT oracle, read off the call site, and it NEVER RUNS.**

It cannot catch a placement that is right and **read back** wrong. And the
outcome oracle — the glibc dynamic call — **cannot reach either ticket at all**,
because no libc entry point takes a large aggregate by value. **Both are needed;
neither substitutes.** Writing the limit into the artifact is the part that
matters: the half a reader supplies wrongly is the half nobody wrote down.

Section: `devdocs/dev/differential-probes.md:655`. Both ticket summaries rewritten
to record the old premise **AS FALSE rather than deleted**.

No compiler change in `9fb5655f7` — docs and tickets. Next is
`ABIA64CdeclArgSlot`'s fixed 8-per-argument becoming a real AAPCS64 aggregate
classification, landing **incrementally, not as one drop.**

## 2026-09-03 20:30 — the prescribed fix measured as NO CHANGE, and that was the finding

`575e71ccf` + `95c98db70` + `b294f903a`, all verified on origin.
`ShiftTokParallel` is in `lexer.inc`; `CaptureTemplateTokenFrom` in
`pasparser_generic.inc`.

### A NO-CHANGE RESULT CAN NAME A SECOND IMPLEMENTATION, NOT ONLY A SECOND CONSUMER

The ticket prescribed: shift `TokSrcOff`/`TokSrcLen` alongside `Tokens[]` in
`InsertTokens`/`RemoveTokens`. franka-29 did exactly that, **generalised to all
ten positional arrays** — checking each of the eleven against its declaration in
`defs.inc`, and every non-`Tokens` one documents state *"at this token"*, so
every one owes the shift. Rebuilt. **The symptom did not move by a character.**

Because **a generic specialization never goes through `InsertTokens`.**
`pasparser_generic.inc` carries a SECOND, hand-rolled splice — **and its own
comment says it "owes the same bookkeeping". It did not pay it.**

> **The ticket's prescription was right about the MECHANISM and wrong about the
> POPULATION, which is the ordinary way a precise instruction misleads.**

This repo already reads a no-change result as data about your model. **The
sharpening: the model that was wrong may be "there is one implementation of
this."** A second consumer is the case people look for; a second *implementation*
with a comment promising the bookkeeping it never does is the one that survives,
and it is `normalise-dont-special-case`'s "the second path is the one that stays
broken" caught in the act.

### THEN THE FIX EXPOSED ITS OWN RESIDUAL — the part to keep

The window went from **stale-and-complete to correct-and-punctuationless**:

```
before      near: < T > = class public >>> Val : T
after       near: Integer   var q  >>> TNoSuchTypeAnywhere  begin
```

Those double spaces are blanked punctuation. **The gap a splice opens gets its
spelling channel ZEROED — correct for a SYNTHESIZED token** (no source range
exists, and the printer's fallback to `SOffset`/`SLen` is its text) — **and wrong
for the specializer, whose tokens are VERBATIM COPIES of template tokens with
real ranges.** `SOffset`/`SLen` holds text only for identifiers and strings.

> **So the first fix reproduced the exact defect that channel was ADDED to fix,
> one scope down.** A correct rule applied to a population it was not written for
> regenerates the original bug — and it looks like progress, because the window
> did improve.

`95c98db70` carries the span through the template and specialize pools: **kept
for verbatim copies, zeroed for SUBSTITUTED ones** so the fallback prints their
NEW text. Carrying it there would print **the old word one token over** — the
same bug in a different hat, a third time in one ticket.

```
95c98db70   near: Integer ) ; var q : >>> TNoSuchTypeAnywhere ; begin
substituted near: z : LongInt ; w : >>> TNoSuchTypeAtAll ; begin
```

The second row is **a probe built for the zeroing arm** — template says `z: T`,
specialization is `<LongInt>`, it prints `LongInt` — **so that arm is shown live
rather than merely untested.**

**Three sites buffered a template token, not one — found ONLY because an edit
asserted a unique match and FAILED.** A uniqueness assertion used as a census is
a free instrument, and it is one of the few that errors instead of answering.
They go through `CaptureTemplateTokenFrom` now.

### GATE DISCIPLINE, and one instrument that lied in its own favour

1. The ticket's grep was added to the recipe and **run THROUGH the recipe**
   (`make -n`, then execute) rather than by hand, and **the pinned compiler is
   the positive control: it FAILS the row, so the row can fail.**
2. `gate.sh quick` GREEN with `compiler/**` uncommitted, so the **FPC canary ran
   (PASS, not SKIP)** — but **quick does not exercise the specializer AT ALL, and
   the self-host fixedpoint cannot, because `compiler.pas` has no generics.**
   That is this file's *"it cannot see a construct the compiler never writes"*
   with a named construct. So it ran the 47 generic test blocks out of
   `make -n test-core` under their own recipes: **266 logical commands, 0
   failures**, guardrail lifted deliberately and the reason in the commit.

**And the sweep first reported a failure that was ITS OWN.** It wrapped the
extracted lines in `set -e`, and one recipe's assertion is
`decl=$(... | grep -c ...)` **expecting ZERO**.

> **`make` does not run a recipe line under `-e`; it checks the line's FINAL
> status. Emulate make, not bash.**

A harness that adds a shell option the real runner does not use **manufactures
failures that look exactly like findings**, and it fails toward alarm — which is
the direction that gets believed and acted on.

## 2026-09-03 21:00 — the denominator trap, shipped and then caught by its own author

`52d134518` + `c6b3b8204`, both verified on origin.

### The ticket's proposed fix was NEARLY VACUOUS, and the report now says so in its own output

Both shapes the ticket offered assume a body's later refusals are **REACHED**.
`WasmUnsupported` **latches**, and about forty sites guard on that latch, so a
second reason only arrives down a path that does not guard. Implemented anyway —
**because the measurement said it buys something real**, not because the ticket
asked. The header now carries a gap count beside the body count **with the word
FLOOR in it**.

### A PRINT STATEMENT'S POSITION IS A POPULATION CHOICE

The number shipped in the fix commit and in two source comments was *"91 of 300
sources reached the report, 86 recorded exactly one reason"*. It was measured
with a probe printed **UNCONDITIONALLY — above the report's `if nothing is broken
then Exit`** — so it counted every program that **COMPILED**. **77 of that 91 had
nothing broken at all and could not have recorded a second reason.**

Recomputed over the population that could produce a two: **5 of 14.**

> **Same numerator, opposite decisions.** 5-in-91 says *"barely worth keeping a
> list"*. 5-in-14 says *"a third of affected programs"*.

> **A print statement's POSITION is a population choice, and the widening lands
> ENTIRELY in the vacuous half.** Moving a probe one line up the function does not
> error, does not change the numerator, and silently swaps the question.

This is the repo's denominator rule with a new mechanism: not a wrong glob, not a
wrong folder — **a correct probe at the wrong height.** Both comments corrected
in place; `c6b3b8204` **says so rather than quietly restating**.

### THE CHEAP CONTROL FAILED IN THE BELIEVABLE DIRECTION

It nearly justified the new test row with *"`and also` does not occur in the
pre-fix source"* — and **grepping the pre-fix file for it HITS, in a prose
comment.** A source-level control that would have read as **refuting a claim that
is in fact true.**

So it built the pre-fix compiler instead: stash, rebuild `d5a7b5d3ce4d` — the row
fails there and prints the single shadowed cause; restored, rebuild
`eac2ad1a536b`, it passes. **A control that can be defeated by a comment is not a
control**, and this one would have failed toward *abandoning a correct fix*.

### THEN IT USED THE FIXED INSTRUMENT AS ONE — and that is the group part

300 sources compiled for wasm32: **278 gap instances, and 222 are `statement IR
op 43` — IR_VAR_STORE, the Variant family.** Next down is 18 (`IR_SYSCALL`), then
8 (`IR_SET_LIT`).

> **Variant is four fifths of wasm32's entire gap surface**, and the ticket for it
> sat at prio 30 with `blocked-by: []` and no umbrella edge.

Wired under `umbrella-wasm-is-a-real-platform` (edge on the UMBRELLA's
`blocked-by`, which is the correct direction) **and its prio deliberately NOT
touched** — the edge is what the ranker reads and the umbrella prio is the
owner's number. **An umbrella grown by ATTEMPTING THE TARGET rather than by
triaging the backlog**, which is exactly what this repo asks for and rarely gets.

**COORDINATOR NOTE — the edge is correct and it changes NOTHING for the ranker.**
`effective_prio` is the max of a ticket's own prio and everything it unblocks:
the Variant ticket is **30**, `umbrella-wasm-is-a-real-platform` is **25**, so
max(30, 25) = **30, unchanged**. The measurement that Variant is 4/5 of the gap
surface **cannot move the work up the queue, because the umbrella expressing the
goal is ranked BELOW the ticket serving it.** Only the owner can change that —
umbrella prio is the only number a human sets. **This is a case FOR a re-rank,
and it is his call, not mine; I have not touched either number.**

### Scope limit, and what was left open on purpose

**278 is a FLOOR by construction** — a body stops at its first refusal, so the
census **can understate the tail and never the head.** Stated on both tickets.

Making it a true census means letting the walk continue past a refusal. **Cheap
in output terms** (the emitted bytes are discarded anyway) **and not cheap in
robustness terms** — the forty guards exist because a refused lookup leaves state
a later site reads.

> **Whoever takes it should expect to be measuring compiler crashes, not report
> quality.** Written into the closed ticket, which is the right place for it.

## 2026-09-03 22:00 — a FOURTH thing that reads like a blockage, and a right action from a wrong model

### The transcript check answered (3): ended its turn

frankb-78 had landed `78b320712`, read `gate.sh quick`'s verdict **out of the log
rather than the wrapper**, reported, and stopped. Nothing in flight, no
unanswered call.

### THE FOURTH REFUSAL SHAPE — a HARNESS POLICY BLOCK

This file already records three things that look alike in a transcript: a user
rejection, a denial-by-policy, and a guardrail the agent may lift itself. There
is a **fourth**, and it appeared today:

> `sleep 120` in the foreground returned **"Blocked: ... To wait for a condition,
> use Monitor with an until-loop ... Do not chain shorter sleeps to work around
> this block."**

A **tool-policy block**, arriving as a tool-result error with a refusal-shaped
string — indistinguishable at a glance from the other three. **It is the only one
of the four that ships its own remedy in the message**, which is also what makes
it harmless: frankb-78 adapted in the same turn and it cost nothing.

So the census of "refusal-shaped strings in a transcript" is now four, and **only
two of them are a session being stuck.** Asking *"is there a refusal"* remains
insufficient; the question is **who refused** — and now also **whether the
refusal told you what to do instead.**

`no-full-suite.sh` **never fired** in that session: `PXX_ALLOW_FULL_SUITE=1` was
set up front on every `make test-core`, because the rows being added are
cross-target and quick runs none of them, with the reason in both commit
messages. That is the guardrail used as designed rather than tripped.

### A RIGHT ACTION FROM A WRONG MODEL, and the peer said so

I asked because a gap "looked like an incremental codegen job in progress". **It
was not: step 2 had not started.** The action was right and my reason for it was
wrong.

> **From outside, "landed step 1 and stopped" and "step 2 is underway" are the
> same silence** — which is exactly why the commit gap could not answer and the
> question could. **The value of asking did not depend on my model being right,
> and that is the argument for asking cheaply rather than modelling well.**

### SEQUENCING CALL — mine, and made rather than deferred

frankb-78 asked whether to start step 2 (`ABICRecordParamByValue`: a C record
parameter stops being a pointer on aarch64, **caller and callee in one commit
because they are one decision**) now, or hold it while a pin window may open.
**It explicitly declined to make that call silently on the owner's behalf**,
which is the right instinct — this repo's rule is to sequence the few things that
genuinely serialise, and *landing order when a change is only correct as a whole*
is named in it.

**Held.** Not because it risks a broken pin — it is green-or-nothing by
construction — but because **a pin containing a brand-new aarch64 ABI change that
no breadth run has seen degrades exactly what a pin is FOR.** Track T samples
every ~8 commits, not instantly, and the owner has already been told that nothing
has measured this tree.

**With a release condition it controls, not an open-ended wait on me** — the
day's own lesson about waits on nobody. It takes
`bug-t-a-silent-test-assertion-makes-the-harness-report-the-wrong-thing` (p45,
A+T), which is harness-side and cannot destabilise a pin, and **if the owner has
not answered by the time that lands, step 2 starts.**

## 2026-09-03 22:xx — BUILDING WITH THE FLAG *IS* THE FLIP, and the post-state is red today

frankb-78 took the verification half and **went for the BEFORE**, which changed
the sequence. The flip does NOT complete tonight until four defects close.

### The structural fact that makes it cheap, and nobody had stated it

`pasparser_decl.inc` re-types `string[N]` to `tyShortString` under
`-dPXX_SHORTSTRING` **today**. franka-29's change makes that unconditional. So:

> **BUILDING WITH THE FLAG IS THE FLIP.** No compiler change is needed to measure
> the post-state — only the window in which BOTH modes still exist, and the one
> thing that closes that window is **deleting the flag.**

This reframes the whole job. The flip is not "a change we make and then test"; it
is **a state we can measure before committing to it.** And the flag's deletion is
therefore **not the last mechanical step — it is the moment the BEFORE is
destroyed**, after which every failure has two explanations and no comparison is
possible. It is sequenced last and separately for that reason.

### THE BLAST RADIUS NOBODY HAD: 58 of 71

**71 test files declare `string[N]` or `shortstring`. The Makefile builds 13 of
them with the flag.** The other **58 have never been measured in the mode the
flip makes the default.**

13-built-with-the-flag is exactly the coverage shape that reads as *"we test
this"* — the same animal as C variadic tests that were all native-only.

### Four defects, and TWO CORRECT CHANGES SEPARATED OUT

Swept all 71, native, both ways: **64 same, 4 output-differs, 2 rc-differs.**
Re-run under the Makefile's own flags against the checked-in `.expected`:

- `test_char_into_shortstring_via_pointer` — **SIGSEGV**
- `test_frozen_string_concat_operand` — **SIGSEGV**
- `test_char_string_equality_both_directions` — **`1char eq TRUE FALSE`**, a
  one-char string equality **silently returns FALSE**
- `test_string_n_array_field_stride` — `stride/fits/guard` all `1 -> 0`

Two further differences are **the flip WORKING** (`SizeOf` of a shortstring field
16->8; the byte-prefix test's own layout rows) and were separated out
deliberately.

> **That separation is the entire difference between "six differences" and "four
> defects."** Folded together, the set reads as noise or as one regression, and
> invites someone to dismiss or to over-unify it.

### THE WRONG BOOLEAN OUTRANKS THE SEGFAULTS

A crash has a location and stops the program. **`TRUE FALSE` has neither**, and
only a value assertion **in a mode 58 files never run** can see it. Fix the
segfaults first and that row still ships. Same shape as `SetLength` silently
accepted on an `Integer` this morning, where the refusal row was the only
witness — **twice in one day, a silent wrong answer hiding behind a louder
failure in the same subsystem.**

### FOUR IS A FLOOR — **the COUNT held; the REASON below is WRONG, see the 5af42ef0f correction at the end of this file**

x86-64 only so far — **the target where a width defect is LEAST likely to
appear**, and the one the dev loop, `gate.sh quick` and the pin all run on. The
seven-target matrix is next and is expected **worse, not better.** This is the
repo's structurally-invisible class, which is why the matrix is not optional
before the flag goes.

**Not diagnosed, and deliberately not guessed at:** whether the four share a
cause. *"Three symptoms in one subsystem on one day is exactly the shape that
reads like one root cause and turns out to be three."*

### The owner's instruction, honoured rather than overridden

He asked for **a compiler that implemented shortstrings.** A flipped compiler
that segfaults on two shapes and silently answers FALSE for one-char equality has
not implemented shortstrings — it is a broken compiler with the flag removed, and
it is the exact thing this handbook is written against. **Fixing four and
flipping IS the instruction. Flipping over them is not.**

Sequence: **fix the four -> seven-target matrix -> flip -> re-pin.**

### `22fe29814`'s zero was true of the PATTERN, not of the defect

*"Bare equality assertions are now 0"* — its scan required the LEFT operand to be
a command substitution, and the six that exist are `out=$(...); test "$$out" =
"$$(...)"`, the form you write when you also need an rc or a timeout. All six
predate that commit.

**Third instance today of one class: a TRUE statement about a NARROWER question
than the one everyone reads it as answering** — after the clang/link premise and
`IRFrozenKindOfAddr`'s default. **A scan reporting zero is indistinguishable from
an absence of defects, so its population must be stated.**

Landed alongside: six genuinely silent assertions converted, **four whose exit
status was discarded by a `;` — they could not fail at all** — plus a guard tool
with ten devtest cases wired into `gate.sh quick` so the ~3900 conversions cannot
rot. Cleared to land: harness-only, cannot affect the flip, and it makes
assertions louder for the matrix about to run.

## 2026-09-03 23:xx — `5af42ef0f`: the matrix, and a correction to a claim THIS SEAT amplified

Both verified on origin. Matrix doc: `devdocs/dev/shortstring-flip-cross-target-matrix.md`.

### THE MATRIX — 71 tests x 7 targets x 2 modes, plus FPC 3.2.2 (built and ran 55)

**The oracle picks a side on every differing row**, which is what makes this a
verdict rather than a diff.

**The flip FIXES two, on all seven targets:** `test_shortstring_byte_prefix` goes
**byte-for-byte to FPC's output**, and `test_sizeof_array_field`'s `rec.S` goes
**16 -> 8, which is FPC's answer.**

**It BREAKS four, with FPC on today's side:** `frozen_string_concat_operand`
SIGSEGVs on **six of seven** (not wasm32); `string_n_array_field_stride` prints
`0/0/0` on **all seven**; the other two are **x86-64 ONLY**.

**Checked and empty:** no BUILD-OFF-FAIL row builds in the ON mode — **the flip
changes nothing about what compiles, on any target.**

### CORRECTION — I RELAYED A FLOOR CLAIM'S REASON, AND THE REASON WAS WRONG

I relayed *"four is a floor, expect the matrix worse, because x86-64 is where a
width defect is least likely to appear"* — to franka-29, to frankb-78, into this
file, and **to the owner.** frankb-78 asked for the correction rather than
letting the tidy version stand.

**The COUNT survived: the cross sweep found NO new defect, and two of the four do
not reproduce on any cross target.** So "four is a floor" is still true.

**The REASON does not apply.** The structurally-invisible class — the one where
the dev loop, `gate.sh quick` and the pin all run on x86-64 and a whole defect
family is therefore native-only-visible — is about **width, alignment and ABI**
changes.

> **A FRONT-END RE-TYPE IS NOT A WIDTH OR ABI CHANGE AND DOES NOT HAVE THAT
> BLINDNESS SHAPE.**

**A correct rule applied to a change it does not describe** — which is the same
error franka-29's token-splice fix made against a population, one day and one
subsystem apart. **The rule being real is exactly what makes over-applying it
persuasive**, and a coordinator relaying it adds credibility it has not earned.
The earlier section is annotated in place, not rewritten.

### THE FINDING: SIXTEEN ROWS WERE THE INSTRUMENT, NOT THE FLIP

All sixteen were **reproducible, target-specific, byte-real differences** — and
none of them were the change:

- **wasmtime prints the binary's own path in its trap message, and the two modes
  are two files.** (12 rows.)
- Its backtrace prints **code offsets that shift with code size.** (3 rows.)
- **i386 `test_rtti_reg` dumps a raw RTTI blob containing a STACK ADDRESS** — the
  **same binary differs from itself by 3 of 47557 bytes under ASLR.** (1 row.)

> **A differential sweep with no self-comparison cannot separate "this change did
> something" from "this program is not deterministic" — and both render as the
> same tidy table.**

**The control: run the OFF binary TWICE and compare it with ITSELF, before you
compare it with anything else.** 33 rows checked: **32 STABLE, 1 NOISE.**

This is the sharpest instrument finding of the day. Every other control this file
records asks *can this guard fail* or *is the expected value distinguishable from
the default*. **This one asks whether the measurement is repeatable AT ALL**, and
a sweep that skips it reports nondeterminism as a finding, with a target name and
a byte count attached to make it convincing.

### The scanner had to be widened TWICE, and both widenings were its own defect

`8ccaf9532`. Residual was **14 silent + 4 vacuous.**

- Draft one read **PHYSICAL lines**, and called four assertions silent whose
  `|| { echo ...; exit 1; }` sits on the **next continued line.**
- Draft two **matched only `=`** and reported OK — while four
  `test "$(grep -c ...)" -ge N` rows (duplicated across test-core and test-nilpy,
  so eight lines) **sat silent behind `-ge`.** `test` prints nothing for `-ge`
  exactly as it does for `=`.

**That second one is the "true about a narrower question" class a FOURTH time
today — and this time it was the scan's own author reporting the zero.**

**Positive control now stated IN the tool:** against `git show HEAD:Makefile` it
reports 14 silent, 4 vacuous, exit 1; against the tree, 0, exit 0. Devtest at 12
guards, wired into `gate.sh quick` so the ~3900 conversions cannot rot.

## 2026-09-04 — all four flip defects diagnosed and fixed, and one of them was never a flip defect

`b97167982` and `157b02b90` verified on origin. Fixes 3 and 4 are in frankb-78's
tree pending the seven-target sweep — `test_frozen_string_char_compare_shapes` is
**not yet on origin**, which is consistent with that and is how I checked the
account rather than taking it.

**Native sweep is 69 SAME of 71.** The only two rows still differing are
`test_shortstring_byte_prefix` and `test_sizeof_array_field` — **the two the flip
is SUPPOSED to change, both toward FPC.** Each fix verified in both modes against
FPC 3.2.2 on all seven targets, each rebuilt to `converged after 1 round` and
gated GREEN with the FPC seed canary running.

| # | test | cause |
| --- | --- | --- |
| 1 | `test_char_string_equality_both_directions` | x86-64 Char<->String arms hardcoded the 8-byte prefix |
| 2 | `test_string_n_array_field_stride` | record-field arm missing from the `tyShortString` stride branch |
| 3 | `test_frozen_string_concat_operand` | `IRFrozenKindOfAddr` had no `IR_CALL` arm |
| 4 | `test_char_into_shortstring_via_pointer` | Char arms guarded on `= tyString`, the GENERIC tag |

### FIXING THE SILENT ONE FIRST CHANGED WHAT THE CRASH LOOKED LIKE

The ordering argument was that a silent wrong value outranks a crash because only
a value assertion can see it. **It turned out to matter for a second and better
reason.**

Before (1) was fixed, `test_char_into_shortstring_via_pointer` printed `a FAIL`
**and then segfaulted.** After (1), **the FAIL was gone and the segfault moved to
a later row** — and that is what led to the real cause.

> ~~A silent wrong value upstream does not merely hide; it RELOCATES the crash
> downstream of it.~~ **OVERSTATED BY THIS SEAT — narrowed by its author, see the
> correction at the end of this file.** What was measured: **a failing assertion
> upstream can hide WHICH ROW is the crashing one.** Starting with the crashes
> would have meant chasing a symptom that the other fix was going to move anyway.

So "fix the silent one first" is not only about shipping risk. **It is about not
diagnosing a crash whose position is a function of a bug you have not fixed yet.**

### FOUR DEFECTS, FOUR MECHANISMS, THREE FILES — A SHARED SHAPE, NOT A SHARED CAUSE

Both frankb-78 and this seat refused to guess whether they shared a cause. **They
did not.** What they share is a shape, in frankb-78's words:

> **In every one of the four, the information needed was ALREADY RECORDED
> somewhere and the reader did not ask.** The prefix width was in
> `FrozenStrPrefixSize`; the field capacity in `RecFieldStrCap`; the return kind
> in `Procs[].RetType`; the frozen kind in the node's own tag.
>
> **Nothing was missing. Four readers were.**

That is the day's theme stated better than anything else in this file: the defect
is not an absent fact but **an available fact nobody consulted** — the same
family as a width oracle used as a membership test and as guards asking a tag
that stopped answering. **Recorded as a SHAPE and deliberately not as a tally**,
because a count built by inference is exactly what this seat got wrong twice
today.

### AND ONE OF THE FOUR IS A SHIPPING BUG, NOT A FLIP DEFECT

Chasing (4): **`a[0] := 'X'` for `a: array[0..1] of string[8]` SIGSEGVs on the
PINNED compiler in DEFAULT mode** — verified against
`stable_linux_amd64/default/pinned`. **It ships today and has nothing to do with
the flip.**

The x86-64 Char arms guarded on `lhsTk = tyString` — **a test for the GENERIC
frozen tag rather than for membership.** A variable's `IR_LEA` carries that legacy
tag, so `s = 'X'` matched; **an array element and a record field are tagged with
their real kind** and fell through to `EmitStrCmpReg`, which dereferences the
Char's ORDINAL as a string address.

> **The flip did not introduce it. The flip WIDENED it**, by re-tagging every
> `string[N]` field — which is how a latent crash became visible.

Fixed in both modes, with `test_frozen_string_char_compare_shapes` wired for
x86-64/aarch64/arm32/riscv32 in both modes and its `.expected` taken from FPC.
**The pinned-compiler crash is that test's positive control** — a control drawn
from the population the question is about, which is the standard this file keeps
asking for and rarely gets handed.

### Coordination note

franka-29 never answered. frankb-78 messaged it directly first, as instructed,
before taking the four. Everything is on origin with full commit messages,
nothing will be half-done in its tree once the last two land, and it has offered
to hand back anything franka-29 wants. **That is the right shape for taking work
from an unresponsive peer: try direct, land publicly, offer it back.**

## 2026-09-04 — MATRIX CONFIRMED, FLAG AUTHORISED, and a third over-generalisation by this seat

All five verified on origin: `b97167982`, `157b02b90`, `15b9abdcf`,
`8b6c2280d` (the default-mode crash, committed separately as asked), `257201e1c`
(matrix re-run).

### The matrix — 72 files x 7 targets x both modes, FPC 3.2.2 as oracle

| target | OUTPUT-DIFFERS | SAME | BUILD-OFF-FAIL | NOISE |
| --- | --- | --- | --- | --- |
| x86_64 | 2 | 69 | 1 | |
| i386 | 2 | 67 | 2 | 1 |
| aarch64 | 2 | 68 | 2 | |
| arm32 | 2 | 68 | 2 | |
| riscv32 | 2 | 68 | 2 | |
| xtensa | 2 | 63 | 7 | |
| wasm32 | 2 | 63 | 7 | |

The two on every row are `test_shortstring_byte_prefix` and
`test_sizeof_array_field`, both `=ON` — **FPC agrees with the flip and not with
today.** **Zero RC-DIFFERS anywhere**; before the fixes there were six including a
SIGSEGV on six of seven. `b-` rows re-checked: none builds in ON mode either, so
**buildability is unchanged.** The single `~` is the i386 ASLR row, still noise,
excluded by name.

> **The supported claim, stated narrowly by its author:** on this corpus the flip
> **moves two rows toward the oracle, moves nothing away, and stops nothing that
> ran.**

**Stated coverage limits, volunteered rather than extracted:** 72 Pascal files
declaring `string[N]`/`shortstring`; nothing from `examples/` or `lib/` (checked —
no example declares one, and `lib/rtl`'s only real declaration is typinfo's
`string[256]`, outside the re-typed range); nothing from the C/NilPy/Rust/Zig
frontends, which the re-type does not touch.

### The self-host fixedpoint is SAFE and is NOT the gate here

`793b38646` established, **by building rather than by grepping**, that the
compiler's own source is unaffected: all 24 `compiler/` files mentioning
`string[N]` do so in comments. **So `converged after N round(s)` will prove the
compiler still builds itself and will NOT prove the flip correct** — this is
exactly the documented limit that the fixedpoint cannot see a construct the
compiler never writes. **The matrix is the gate. Say so rather than letting a
green fixedpoint imply more than it can.**

The boundary lands on FPC at both ends, and **`string[256]` is unchanged in both
modes** — the row that matters for the RTL, because `lib/rtl/typinfo.pas:42`
declares `TRttiStr = string[256]` whose 256 is a **kind selector, not a length**,
and FPC rejects that declaration outright. **The re-type must keep its 1..255
bound or the RTL changes shape underneath the compiler that builds itself.**

### AUTHORISED: delete the flag, and `tools/flip-shortstring/` in the same diff

The condition this seat set — four defects closed and re-measured — is met. After
the flag there is no "off" mode and **every script in that directory measures one
thing twice**, so leaving it is leaving an instrument that cannot fail.

### A THIRD OVER-GENERALISATION, AND THE PATTERN IS ABOUT THIS SEAT

I wrote that a silent wrong value **"RELOCATES the crash downstream of it."**
frankb-78 measured something narrower: **a failing assertion upstream can hide
WHICH ROW is the crashing one** — same program, same crash site, moving because an
earlier row stopped failing. Its reason for insisting: **"the bigger one would be
quoted at people as a rule."**

**Third time today.** The `five in this family` tally, the `expect the matrix
worse` reason, and now this — each a peer's measured finding widened by me into
something more quotable.

> **A coordinator's restatement acquires authority the original did not have.**
> The peer hedges; the relay does not; and the relayed form is what gets cited.
> **The failure mode of this seat is not getting facts wrong — it is making
> correct findings bigger.**

### What DID repeat, stated precisely and not as a tally

The four did not share a cause — four mechanisms, three files. But **two of the
four were the same READING ERROR in different files**: `= tyString`, and the
walker's wide default, **both used as membership tests when they are width
answers.**

> **Not one bug; one habit.**

## 2026-09-04 — PHASE 4 IS LANDED AND PINNED. v403.

`fd186a975` (the flip) + `4f167ccb5` (ticket/logbook/board) + **`ce63beeeb`
(pin v403, binary `c31d03b202da`)**. The owner's `pin -> flip -> re-pin` is
complete. **`string[1..255]` IS `tyShortString`, unconditionally, with no flag.**

### Verified independently before pinning, not taken on report

- `PasDefineExists('PXX_SHORTSTRING')` — **gone from `compiler/` entirely.**
- `TargetHasByteStrPrefixCodegen` — **no longer defined**; its one remaining
  mention is a comment at `pasparser_decl.inc:429` **recording the gate's
  removal**, which is evidence kept rather than deleted.
- `tools/flip-shortstring/` — **gone**, in the same diff, as it must be: after
  the flag there is no "off" mode and every script in it measures one thing twice.
- **The bound is live** at `pasparser_decl.inc:443`:
  `if (LastTypeStrCap >= 1) and (LastTypeStrCap <= 255)`.
- `stabilize-fast` reached **`c31d03b202da` — the same binary sha frankb-78
  reported from its own build.** Two independent builds, one sha: the fixedpoint
  is corroborated rather than asserted.

### THE PIN SAYS WHAT IT DOES NOT ASSERT

Written into the pin commit rather than left here: **the fixedpoint does not
validate the flip and cannot.** `compiler.pas` declares no `string[N]` at all —
established **by building**, in `793b38646` — so `converged after 1 round` is
**structurally incapable of observing the change under test.** The gate is the
matrix. A future reader will find a green fixedpoint on the flip commit and it
will look like validation; the commit now says why it is not.

### Grade: reds(3), none introduced by the flip, none a self-host failure

`testmgr --tier full` **3957 of 3964 ok**. Three `tools-devtest` scanners, all
other lanes': `exit_observable` (stdout-only 94.13% vs 92.69% cap),
`test_wiring_gate` (5 test files no rule runs), `testmgr_hardcoded_tmp` (`/tmp`
literals in two C tests).

**They were established as pre-existing by running all three against a pristine
`git archive HEAD` tree — NOT by reading the flip's diff and judging them
unrelated.** That is the difference between a control and an opinion, and it is
the reading frankb-78 explicitly said it did not want to trust. On
`exit_observable` the flip is an **improvement it declined to claim credit for**
(94.13% -> 93.79%, still over cap).

### The diff contained ~18 stale COMMENT blocks nobody had asked about

Found by grepping for `PXX_SHORTSTRING` **after staging, expecting nothing**:
Makefile comment blocks describing the two-mode world in the present tense —
*"BOTH MODES"*, *"the flag rows below are wired"*, *"all FOUR combinations"*,
*"sizeof is 10+8=18 by default and 10+1=11 under the flag"*.

**None errors. Each tells the next reader the tree still has a mode selector.**
And **two of them are the blocks written because a stale "this file is red under
the flag" nearly stalled this very flip once** — the same defect, in the same
place, that its own remediation had documented. Evidence kept and moved to past
tense, and **the pass was verified mechanically to have moved no recipe line**
rather than by reading the diff.

> **A comment that describes a world the tree no longer has is a stale
> imperative: obeyed by the next reader, contradicted by nothing.**

### Left owned, not bundled

The three harness reds were **deliberately not fixed inside the flip** — they
need owners. frankb-78 offered to take `testmgr_hardcoded_tmp` first, being two
literals and mechanically verifiable. Step 2 (`ABICRecordParamByValue`) stays
parked **as a patch**, and the hand-back offer to franka-29 — silent throughout —
remains open; nothing landed forecloses anything it holds.

## 2026-09-04 — two of the three graded reds closed, and a correction to how I cited my own check

`8b5eddb80` (`testmgr_hardcoded_tmp`) and `7e2dce2f8` (`test_wiring_gate`), both
verified on origin. `exit_observable` deliberately left — a threshold argument,
not a defect. **Pin v403's grade of `reds(3)` was accurate when taken and two of
the three are now gone.**

### MY PRE-PIN CHECK: one item stronger than I framed it, one weaker

**Stronger — the two independent builds.** I recorded "two builds, one sha
(`c31d03b202da`)" as corroboration. **The routes DIFFER, and that is the point I
missed:** frankb-78's was `make compiler/pascal26` seeded from its local chain;
mine was `stabilize-fast` from the pin. **Those are precisely the two routes that
legitimately produce DIFFERENT valid fixedpoints when a local seed has walked off
the pin-derived chain** — a documented `gate.sh quick` RED, and not a miscompile,
since both binaries self-reproduce. So the second build did not repeat the first;
**it ruled out the one divergence this repo has actually observed.**

**Weaker — "the bound is live at `pasparser_decl.inc:443`".** A line number **in a
file that had just been rewritten** is the citation most likely to be stale within
the week. This repo has already measured a `make pin` line reference drifting 142
lines in a single day and landing on a real line that explained nothing.

> **The bound is load-bearing; the line is not.** Cite the predicate, not the
> address. (Checked today and `:443` still holds — which is exactly how a citation
> like this earns trust it will not keep.)

### A GUARD THAT FIRED CORRECTLY AND EXPLAINED ITSELF WITH THE WRONG HARM

`testmgr_hardcoded_tmp` rejects a hardcoded `/tmp` because *"two concurrent runs
share the file"*. **Both offenders used `mkstemp`, so the NAME was already unique
and that hazard never applied to them.** The real harm is the **DIRECTORY**: a
file outside `$TESTMGR_TMP` is one testmgr did not create and does not clean up.

> **Right verdict, wrong stated reason** — the "correct about something else"
> shape, this time in an instrument's **MESSAGE** rather than in its verdict. A
> reader who checks the stated harm against these two files concludes the guard
> is wrong and is tempted to suppress it.

**Flagged, not edited** — it is Track T's tool, and the message is accurate for
the 61 literals it was built against. T may want to widen the wording.

**The control there is the keeper:** `TESTMGR_TMP` pointed at a directory that
does not exist, where both pxx and gcc print `mkstemp failed`. **Without it, a
dead `getenv` would have quietly succeeded in `/tmp` and printed all four correct
rows — a passing test certifying a change that did nothing.**

### WIRING THOSE TESTS x86-64-ONLY WOULD HAVE BEEN WORSE THAN LEAVING THEM OUT

All five were written alongside their own fixes on 2026-09-02 and **none was ever
gated.** Two are the const-cast-width and method-pointer tests — **the pair
CLAUDE.md itself holds up as the case a 64-bit host cannot see.**

> **A native-only wiring of those two would have passed whether or not the fix
> existed** — a guard that cannot fail, added in the act of closing a
> guard-coverage red.

Wired on i386, aarch64, arm32 and riscv32 as well, and **the positive control is
that the i386 method-pointer row REFUSES the x86-64 answer.**

Verified by **executing all 32 added recipe lines verbatim**, rather than
re-running binaries already run by hand: **in a wiring commit the risk is the
recipe TEXT, not the program.** That is the same reasoning as this file's rule
about a `cmp` harness whose inputs were never proven to exist.
