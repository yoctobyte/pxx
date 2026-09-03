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
