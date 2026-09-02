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
