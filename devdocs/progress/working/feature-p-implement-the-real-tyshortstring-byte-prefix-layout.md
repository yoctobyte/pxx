---
slug: feature-p-implement-the-real-tyshortstring-byte-prefix-layout
title: "Implement the real `tyShortString` byte-length-prefix layout — the kind is already plumbed, the codegen is not"
track: P
prio: 100
type: feature
status: working
created: 2026-09-02
found-by: owner (raised 2026-09-02), measured by frankuser
owner: frankB
summary: "P1 AUDIT DONE (frankB, 2026-09-02, binary `b1b8ca4d5435`). We are `cap+8` and FPC is `cap+1` uniformly (ShortString 263 vs 256, string[10] 18 vs 11); the whole divergence is the length-word width and it is a documented interim at `pasparser_decl.inc:540`. THE AUDIT MOVED THE SURFACE RATHER THAN CONFIRMING IT, in three ways that change how P2 is scoped. (a) `tyShortString`'s 63 sites are a NAME count and it points the wrong way: riscv32 and xtensa mention the kind ZERO times and handle frozen strings fully, i386 REFUSES both frozen kinds outright, and the rest are kind lists and comments. The backends look ready because `TypeIsFrozenString` -- 128 sites, whose own comment says it exists to route the new kinds 'without 250 new arms' -- ERASES the very distinction the byte prefix creates. Scope by those 128 (28 touch a layout number), never by the 63. (b) `EmitStoreStrLen`/`EmitLoadStrLen` is not a width abstraction: it is an x86-64 helper TRIO in symtab.inc (the third member, `EmitLeaStrDataRdi`, computes the data offset) that hardcodes 8 itself; the other backends reference it only in COMMENTS, so six have no equivalent. (c) SELF-HOST RISK LARGELY DISSOLVED: the fixedpoint builds in MANAGED mode (`FROZEN_PXXFLAGS` is only on the `-frozen` targets), so bare `string` in `compiler/**` is a tyAnsiString handle and the 69 declarations are not in this feature's domain at all -- and even under `-frozen` they are tyString, which the flip does not re-type. The ENTIRE build-input exposure was ONE declaration, `lib/rtl/typinfo.pas`'s `TRttiStr = string[255]` sitting exactly on the N<=255 boundary; it is now `string[256]` (a kind selector, not a length -- the type is never instantiated), which was a provable no-op pre-flip and takes lib/rtl out of the flip commit entirely. STILL TRUE AND UNCHANGED: `tyFixedString` stays as-is for N>255, this is additive, and P4 remains the serialising step."
---

# The real `tyShortString`, and why it is cheaper than it looks

## PHASE 1 — THE AUDIT. It moves the surface rather than confirming it

Measured 2026-09-02 by frankB, binary `b1b8ca4d5435`, `converged after 1
round(s)`. **Headline: the deliverable this phase asked for — "sites assuming an
8-byte prefix without going through the named emit pair" — is not the right
query. The named emit pair is not an abstraction, and the plumbing count is a
name count that points the wrong way.** Both corrected below, with what to use
instead.

### F1 — the emit "pair" is ONE BACKEND'S HELPER TRIO, and it hardcodes 8 itself

Defined at `symtab.inc:6907/6926/6945` — and there is a third member nobody has
named, `EmitLeaStrDataRdi`, which is the one that computes the DATA ADDRESS.
All three emit **raw x86-64 machine code**: `mov [P], rax` is a 64-bit store,
`add rdi, 8` is the data offset. The trio is not a width abstraction; it *is*
the 8.

Of its 15 references, the three outside x86-64 are **comments**:

    ir_codegen386.inc:3098      "Mirrors x86-64 EmitStoreStrLen."
    ir_codegen_aarch64.inc:2993 "Mirrors x86-64 EmitStoreStrLen."
    ir_codegen_arm32.inc:2534   "Mirrors x86-64 EmitStoreStrLen."

`riscv32`, `xtensa` and `wasm32` do not mention it at all. So "route it through
the named emit pair" is not a small step: **P2 must first make the trio
width-aware, then build an equivalent in six backends that have none.** The
phrase describes a concentration that does not exist.

### F2 — THE KIND IS NOT PLUMBED IN THE BACKENDS; IT IS *ERASED*. That inverts the risk.

`tyShortString`'s 63 mentions are the reassuring number. Per backend:

| backend | mentions | what they actually are |
| --- | --- | --- |
| x86-64 `ir_codegen.inc` | 1 | a comment |
| i386 | 2 | **an explicit refusal** (F3) + one kind list |
| aarch64 | 1 | a kind list, beside `tyFixedString` |
| arm32 | 1 | a kind list, beside `tyFixedString` |
| wasm32 | 1 | a debug type-NAME string |
| riscv32 | **0** | — |
| xtensa | **0** | — |

**And yet riscv32 (11 sites) and xtensa (12) handle frozen strings fully.** They
reach them through `TypeIsFrozenString`, whose own comment states the purpose:
*"Widen existing `= tyString` codegen checks to this predicate so the new kinds
route through the frozen-string path without 250 new arms."*

That predicate is **an abstraction over exactly the distinction the byte prefix
must create.** True for `tyString`, `tyFixedString` and `tyShortString` alike,
asked at **128 sites across 17 files** — `symtab` 25, `wasm32` 15, `xtensa` 12,
`riscv32` 11, `ir.inc` 10, `ir_codegen` 10, `pasparser_expr` 10, `arm32` 7,
`pasparser_stmt` 7, `aarch64` 6, `pasparser_lval` 4, `386` 3, `pyparser` 3,
`abi` 2, one each in `pasparser_name`, `pasparser_proc`, `compiler.pas`.

**So the audit surface is 128 `TypeIsFrozenString` sites, not 63 `tyShortString`
ones — and the two counts point in OPPOSITE directions.** A grep for the kind
says the backends are ready. They are ready precisely *because* they cannot tell
the two kinds apart. This is the 80%-accurate name: every site you sample
confirms it.

Not all 128 are layout-sensitive. A first pass flags **28** carrying a literal 8
or a sizing constant within ten lines (9 of those reach a sizer); they are the
P2 worklist. The recurring shapes are
`TypeIsFrozenString(Syms[si].TypeKind) and not Syms[si].IsArray` — the
char-into-string store arm, present in every backend, which is the eight
hardcoded arms already in this ticket — and
`ProcExternal[procIdx] and TypeIsFrozenString(...)`, the `+8` skip that hands a
Pascal string to a C callee as a `char*`.

### F3 — i386 REFUSES BOTH FROZEN KINDS OUTRIGHT

`ir_codegen386.inc:857`, in `IREmit386CheckScalarSym`:

    else if Syms[symIdx].TypeKind = tyShortString then
      Error('target i386: ' + whoSym + ' is a SHORTSTRING, not supported yet')
    else if Syms[symIdx].TypeKind = tyFixedString then
      Error('target i386: ' + whoSym + ' is a string[N], not supported yet')

A `string[N]` variable does not compile for i386 today. That is one fewer
backend for P2 — and it is a constraint on how P4 gets MEASURED: an i386 run
cannot observe this shape before or after, so it cannot serve as the
cross-target evidence the plan asks for. Use aarch64 or arm32.

### F4 — most of the literal-8 noise is the STRING POOL, and it is out of scope

Sweeping for a literal 8 on a line mentioning a string-layout concept returns
**254 candidates — of which 55 are `Strs[...].Offset + 8`**, the interned
literal pool that `emit.inc` writes once as `[len:8][chars][NUL]`. **Literals
stay `tyString` by the plan's own rule, so the pool keeps its 8-byte prefix and
all 55 are correct and must not be touched.**

**Scope by what the 8 is a displacement ON, not by the presence of an 8.**
`Strs[].Offset + 8` is the pool (out of scope); a displacement on a symbol slot
or a runtime base register is a variable's frozen string (in scope). Worth
stating because "grep for +8" is how the next person will scope P2, and it comes
back four times too big.

### F5 — SETTLED: the self-host build is **MANAGED**, and the 69 bare `string`s are not in this feature's domain

The open question this phase was told to close. It closes off the build recipe,
not by inference:

- `util.inc:107` — `if PasDefineExists('PXX_MANAGED_STRING') then BareStringKind
  := tyAnsiString`.
- `bparser.inc:722` — *"PasApplyDefaults defines PXX_MANAGED_STRING
  unconditionally — so for EVERY program, in every frontend, it returns True.
  It is not a discriminator; it is a constant."*
- `Makefile:134` — `FROZEN_PXXFLAGS := -uPXX_MANAGED_STRING`, referenced by
  **only** `bootstrap-frozen`, `test-frozen`, `test-nilpy-frozen`,
  `stabilize-frozen` (lines 240, 3977, 3984, 22247).
- The fixedpoint recipe `$(COMPILER_STAMP)` passes plain `$(PXXFLAGS)` — empty.

**So `compiler.pas` self-hosts in MANAGED mode: bare `string` inside
`compiler/**` is a `tyAnsiString` handle, exactly as in user code.** `defs.inc`'s
*"tyString, the self-host model"* describes the `-frozen` OPT-OUT — a true
sentence about a build nobody runs by default, and the sentence P4's risk
paragraph was resting on.

Two consequences, both shrinking P4:

1. The 69 bare-`string` declarations are **not "left alone by choice" — they are
   not in the domain.** They are managed handles; this feature does not touch
   `tyAnsiString`.
2. Even under `-uPXX_MANAGED_STRING`, bare `string` is `tyString`, the legacy
   frozen kind — **which the flip also does not re-type.** The flip is
   `string[N]`, N <= 255, and nothing else.

**P4's remaining self-host risk is therefore not "the layout of strings the
compiler itself uses."** It was F6, and F6 is now closed.

### F6 — the whole build-input exposure was ONE DECLARATION, and it is now DECOUPLED (landed this phase)

`compiler/**` has zero `string[N]` declarations (frank-coordinator-2c, verified).
Extending the grep to the rest of the build input: **all of `lib/` contains
exactly one**, and it is the one already flagged —

    lib/rtl/typinfo.pas:19   TRttiStr = string[255];

Nothing else in `lib/rtl`, `lib/pcl` or `lib/crtl` declares a `string[N]` or a
`ShortString`. The two-ended ABI contract *was* the entire exposure.

**Taken out of P4.** `TRttiStr` is now `string[256]`, reasoning in the
declaration's own comment: the number is a **kind selector, not a length**. The
type is never instantiated — only `^TRttiStr` exists, so no slot is allocated
and the cap bounds nothing — while N > 255 can only ever be `tyFixedString`,
because a 1-byte prefix cannot count past 255. `string[255]` sat on exactly the
boundary where the re-type would reach it.

**Why now rather than in the flip commit: pre-flip, `string[255]` and
`string[256]` are the SAME KIND, so the change is a no-op today and cannot be
one later.** It converts "the emitter and the RTL unit are only correct as a
whole" into two independent commits. The stale `^string[255]` cross-reference at
`sysutils.pas:225` was corrected in the same commit — load-bearing prose
explaining why `PString` is not `^string`.

**Verified with the control the claim needs.** Nine RTTI/typinfo tests are
byte-identical across the change — but identical output only means something if
the tests OBSERVE the path, so that was established separately:
perturbing `GetClassName`'s deref by one byte moves
`test_rtti_field_get_by_name` (`48258e01f694` -> `0348e0728008`), while a
cap-only change (256 -> 257) leaves every row untouched. So the no-op is aimed,
and the second control confirms the cap is not read. Note the other eight rows
did NOT move under the off-by-one — they do not reach that reader, and quoting
"nine tests green" as coverage of the name path would have been the mistake.

### F7 — the permissive default will re-fire at ELEVEN sites at once, and the fix pattern already exists twenty lines away

frankA's finding, relayed and then corrected by the coordinator; I confirmed the
correction in the source. Every clamp helper opens
`if cap <= 0 then cap := DEFAULT_STR_CAP` — seven backend helpers
(`ir_codegen.inc:4758`, `386:1438`, `aarch64:595`, `arm32:1287`, `riscv32:445`,
`xtensa:629`, `wasm32:4616`), three in `pasparser_decl.inc` (3334, 4134, 5982),
and `FrozenStrSlotSize` at `symtab.inc:3636`. **Eleven, not twelve** — the
twelfth match was prose inside a doc comment, and `grep -c` cannot see that.

**A MISSING capacity reads as a PERMISSIVE one**, so an unwired arm is a silent
overrun and never a diagnostic. `DEFAULT_STR_CAP = 255` substitutes 255+8 = 263,
aligning to 264 — **which is the 264 from
`bug-p-a-string-n-element-loses-its-capacity-in-three-container-shapes`.** That
bug was one firing of this mechanism, and `FrozenStrSlotSize:3636` is the site
that performed the substitution in it. Under a byte prefix the same absence
substitutes 256 instead: **same shape, different wrong number, equally
plausible** — the concrete reason the capacity thread was sequenced ahead of
this feature, now confirmed rather than assumed.

**`SizeOfSlot` (`symtab.inc`, eleven lines below `FrozenStrSlotSize`) is the
counterexample and the model, not one of the eleven.** It has no permissive
default; it does the opposite —

    if TypeIsFrozenString(tk) and (cap > 0) then Result := FrozenStrSlotSize(tk, cap)
    else Result := TypeSlotSize(tk);

— reading `cap <= 0` as *"none was recorded"* and declining to guess, because
widening it there *"would be a guess dressed as a fix."* One site in this tree
can already tell "unset" from a real answer; eleven cannot, and the one that can
sits in the same file as the one that started the 264.

**This is NOT a call to change all eleven.** Each has to be asked what its caller
can actually know — which is exactly the question `SizeOfSlot` asks and answers
honestly. Doing that once, against a pattern already in the file, is the
tractable version; a blanket edit is not.

### F8 — A GATE RED YOU WILL PROBABLY MEET, WHOSE REFLEX REMEDY DESTROYS THE EVIDENCE

Raised by frankD, relayed by frank-coordinator-2c, verified in the script at
`ea9fe253f`. This belongs in the ticket rather than a message because it is a
READING INSTRUCTION for a diagnostic P2-P4 will plausibly trip more than once.

`tools/selfhost_fixedpoint.sh:96` emits:

    FAIL: the fixedpoint reached from PINNED differs from compiler/pascal26

**It is not a staleness detector. It is the anti-Thompson agreement check** (the
script's own header, lines 23-28): a compiler can converge to a DIFFERENT
self-reproducing fixedpoint depending on which binary it started from — both
stable, both green, one carrying whatever the local binary carried. The FAIL
text names both causes in one breath: *"Local seed contamination, **or a
self-perpetuating miscompile**."*

**Cause one is the reflex reading and cause two is this feature's live risk.**
We are changing the layout of strings the compiler itself uses; a
self-perpetuating miscompile is exactly what the fixedpoint gate exists to
catch, and it presents identically to a stale seed.

**And the standard remedy for cause one destroys the evidence for cause two.**
Reseeding from the pin makes `compiler/pascal26` *become* the pinned-derived
fixedpoint, so afterwards the two sides of the comparison are the same object by
construction and the check passes trivially. It can no longer tell you whether
there were ever two fixedpoints. **The fix does not diagnose the RED; it removes
the ability to.**

**Order to follow — reseeding is the LAST step, not the first:**

1. Do **not** reseed. Copy `compiler/pascal26` aside first.
2. Read the `cmp` output the script already prints — it names the first
   differing bytes.
3. `make compiler/pascal26` from current sources, WITHOUT reseeding, and re-run.
   A merely stale binary clears here — cause one, established rather than
   assumed.
4. **Still RED after a clean local rebuild = two distinct fixedpoints = cause
   two.** Stop and report; do not reseed.

A genuinely benign third case is already distinguished by the script itself: if
`compiler/pascal26` changes mid-check it prints `NOTE ... this is NOT a self-host
failure` and exits 0. That is not the case above.

### What P2 should be scoped by, in one line

Not `grep tyShortString` (63, and it lies in the reassuring direction), not
`grep '+ 8'` (254, four-fifths of it the literal pool): **the 128
`TypeIsFrozenString` sites, filtered to the 28 that touch a layout number, plus
the four-backend x86-64 helper trio that has no equivalent elsewhere.**


> **OWNER: HIGHEST PRIORITY, PHASED, frankb-a9 HOLDS IT (2026-09-02).**
> `prio: 100` — **TOP OF THE BOARD, set by the owner.** Above every
> umbrella. All other tracks finish what they are holding and then idle.
>
> ### CORRECTION to this ticket's own exposure count, and a REAL hit it exposed
>
> frank-coordinator-2c falsified the "10 declarations in `compiler/`" figure
> (`9714d1652`): **`compiler/**` has ZERO explicit `string[N]` declarations.**
> All 21 `string[N]` and 37 `ShortString` occurrences are prose inside comment
> blocks — bug write-ups quoting code in backticks. My grep counted comment text
> as declarations. Verified: all three of my hits are inside `{ }`.
>
> **But the falsifying branch it named — a fixed string reached through an alias
> defined OUTSIDE `compiler/**` — has a hit, and it is the real exposure:**
>
> ```
> lib/rtl/typinfo.pas:19:  TRttiStr = string[255];
> lib/rtl/typinfo.pas:20:  PString  = ^TRttiStr;
> ```
>
> **AND THE CONTRACT IS WRITTEN DOWN, NAMING THE WRITER SIDE.** The comment
> directly above `TRttiStr` (found by frank-coordinator-2c) is not decoration —
> it is the ABI spec:
>
> > *"word-length-prefixed strings (**`rtti_emit.inc` points NamePtr at
> > `Strs[].Offset`**) ... a name pointer must be a FROZEN string pointer to read
> > the inline `[len][chars]` blob correctly — `^string` would misread the length
> > word as a managed handle and crash. **`string[255]` is the frozen
> > (tyFixedString) word-prefix kind.**"*
>
> The emitter writes word-prefixed blobs; `TRttiStr` is the reader. Re-type
> `string[255]` to a byte prefix and the two disagree — the reader misreads the
> length, which is the exact crash this comment exists to prevent. **`255` is
> precisely on the boundary**: `tyShortString` caps at 255 so it DOES re-type;
> at 254 it would not.
>
> **Rewrite that comment in the SAME COMMIT as the re-type.** Per CLAUDE.md, a
> comment and code that disagree mean one is wrong and the next reader cannot
> tell which — and here the comment is the only record of why `PString` cannot
> be `^string`. Do not delete it; correct it.
>
> `defs.inc:5588` records that the compiler EMITS `{NamePtr:PString;
> DataPtr:Pointer}` which `typinfo.pas` READS. So this is a **cross-component
> ABI contract containing a fixed string at exactly the 255 boundary**, in
> `lib/rtl` — which is itself a compiler build input. At `cap = 255` the flip
> changes it from 263 bytes/8-byte prefix to 256/1-byte. **The emitter and the
> RTL unit must change together; it is only correct as a whole.** This belongs
> in Phase 1's audit output and is the strongest single argument for the owner's
> quiet-tree instruction — stronger than the declaration count ever was.
>
> ## THE PHASES — land each one green, push, and report before starting the next
>
> **P1 — AUDIT, no behaviour change.** Find every site that assumes an 8-byte
> length prefix without going through `EmitStoreStrLen`/`EmitLoadStrLen` (13
> references; aarch64 emits a length word inline in at least two places, and 16
> comments across backends name it directly). Deliverable is a LIST, in this
> ticket. Also settle the unverified question below — how the self-host string
> mode is selected — because Phase 4's scope depends on it.
>
> **P2 — BYTE-PREFIX CODEGEN, still unreachable.** Make `tyShortString` actually
> store a 1-byte length, per backend, behind the named emit pair. Nothing
> re-types yet, so nothing observes it. Positive control required: a synthetic
> `tyShortString` slot whose stride is asserted, since no source spelling
> reaches this kind yet.
>
> **P3 — THE NINE CONVERSION ARMS**, including `tyString -> tyShortString`.
> Still nothing re-types.
>
> **P4 — THE FLIP: `string[N]`, N <= 255, binds to `tyShortString`.**
> **SERIALISING — quiet tree, no other work landing, announce before and after.**
> This is where the self-host fixedpoint is on the line. Recommended scope:
> explicit `string[N]` only (10 declarations in `compiler/`), leaving bare
> `string` as `tyString` untouched (69 declarations) — see the two-flips section.
> Recovery: reseed from the pin, `touch` the sources, name the pin in the commit.
>
> **P5 — typed constants** for N <= 255 (`const T: string[10] = 'hello'`), which
> have real `.data`. Literals never change; they are `tyString` and convert at
> use.
>
> **Gate at every phase:** `make compiler/pascal26` must print **`converged
> after N round(s)`**, not `verified` — the stamp path means nothing was built.
> `gate.sh quick` before committing, not after, so the FPC seed canary runs.
> Cross-target matters here: per the rule landed today, "nothing observably
> differs" measured on x86-64 is a claim about one target, and this change is
> exactly the width-and-alignment class that hides there.

> **DECIDED BY THE OWNER, 2026-09-02 — DO IT.** *"all we need to do is
> implement a real shortstring type. it will give us some headache with all
> mixed string types concatting etc, but that's all trivial. it will give us
> blitted file io. and memory efficient string handling, something esp targets
> will like. so, useful. we keep our fixedstring as well, just as is."*
>
> **`tyFixedString` STAYS EXACTLY AS IT IS.** This is additive — two kinds, not
> a migration. Nothing about the wide kind changes, and it remains the only one
> that can express `N > 255`.
>
> **The three payoffs, all measured rather than asserted:** blitted `file of T`
> (our padding and alignment rules already match FPC exactly — see below — so
> the width is the whole remaining gap); memory (`string[10]` becomes 11 bytes
> instead of 18, a 39% saving on small strings, which is the ESP argument); and
> FPC-byte-identical records for interop.
>
> **The mixed-kind surface, measured because "trivial" deserved a number:** 29
> sites enumerate multiple string kinds together; **20 already name
> `tyShortString`** and **9 omit it**, spread over 6 files at most 2 per file
> (`symtab`, `pasparser_stmt`, `ir_codegen` ×2 each; `pyparser`,
> `pasparser_expr`, `pasparser_decl` ×1). So the concat/assign work is
> extending nine kind lists. **Caveat, stated so nobody quotes 9 as the job:
> that bounds the ENUMERATION surface, not the semantics** — adding a kind to a
> list is not the same as the concat rule being right for it. The real work is
> the byte-prefix codegen, per backend.

## THE SEQUENCING HOLD IS LIFTED — the capacity fix LANDED 2026-09-02

`bug-p-a-string-n-element-loses-its-capacity-in-three-container-shapes` is in
`done/`. All three shapes fixed, and the count matters for this feature: they
were **three different causes across four sites**, one of which is F7's
permissive default firing again (a parameter got `DEFAULT_STR_CAP + 8` = 263).
The attributability argument below has been satisfied rather than waived — the
capacity now reaches every container shape, so a wrong stride measured during P2
can only be the prefix width.

**One result from that work bears directly on P2's testing.** A capacity bug is
invisible when the wrong answer and the right answer coincide: with
`t: string[10]` following an `array of string[10]` parameter, the broken code
and the correct code produce the same stride. **Any P2 test must vary the
capacity between neighbouring declarations**, not merely use a frozen string
somewhere.

### The original hold, kept for the record

## SEQUENCED BEHIND THE CAPACITY FIX — do not start this in parallel with it

**`bug-p-a-string-n-element-loses-its-capacity-in-three-container-shapes` lands
first.** frankB holds it, filed the constraint, and declined this feature on
sequencing grounds rather than interest (2026-09-02). The reason is
attributability, and it is the deciding kind:

that ticket's finding is that `UFldStrCap` holds a record field's OWN capacity
while `ir.inc:11260` reads it as the field's ELEMENT's capacity, so
`inner: array[0..1] of string[10]` delivers 0 and `FrozenStrSlotSize`
substitutes `DEFAULT_STR_CAP`. The declared 10 is not mis-sized — it is
dropped. **Change the prefix width first and a wrong stride afterwards cannot
be attributed to a layer:** is the prefix wrong, or was the capacity never
delivered to it? `DEFAULT_STR_CAP` under a 1-byte prefix gives 256 instead of
263 — just as wrong, and just as reasonable-looking. Fix the thread, then
change what flows through it.

Both diffs apply cleanly to `FrozenStrSlotSize` territory and neither produces
a git conflict, which is exactly why this is written down instead of left to
the merge. **If you want this feature sooner, take frankB's ticket too and do
both in that order** — one agent, one sequence — rather than running them
concurrently. Message frankB first either way.

## LANDING ORDER — step 3 is the one serialising item on the board besides `make pin`

Approved by the owner 2026-09-02, relayed via frankuser. Each step lands
independently green:

1. **byte-prefix codegen per backend**, behind `EmitStoreStrLen` /
   `EmitLoadStrLen`
2. **the nine conversion/enumeration arms**, including `tyString -> tyShortString`
3. **the re-type of `string[N]` to `tyShortString`** — THIS is the serialising step

**Owner, verbatim:** *"that big flip should be LAST. and likely, we dont want
any other work done at that point since this affects our self-compile
capability."*

It serialises rather than merely being risky because `tyString` is "the
self-host model" (`defs.inc`, the `IR_SETLEN_STR = 61` comment — citation
checked, it reads *"Frozen inline strings (tyString, the self-host model)"*),
so the flip changes the layout of strings the compiler itself uses and the
FIXEDPOINT is what breaks. **Recovery: reseed from the pin and `touch` the
sources** — the pinned binary predates the flip by construction, and `cp`
stamps a newer mtime so `make` no-ops without the touch.

**Whoever runs step 3 tells the coordinator BEFORE starting**, so the tree can
be quiet. Steps 1 and 2 need no such stop.

### The exposure number needs reconciling before step 3 is scoped

The plan rests on splitting the flip in two — re-type explicit `string[N]`
(stated as 3 declarations plus 7 `array of string[N]`, so ten sites) while
leaving bare `string` alone, which avoids touching all 69 of its uses and
avoids changing both slot (264->256) and prefix width (8->1). **Leaving bare
`string` untouched is the right call and is not in question here.**

**But the ten does not reproduce. Measured 2026-09-02 at `9ff7a582e`:
`compiler/**` contains ZERO explicit `string[N]` or `ShortString`
declarations.** All 21 `string[N]` occurrences and all 37 `ShortString`
occurrences are **prose inside comment blocks** — bug write-ups, field
comments, playbook-style notes. The single non-comment hit is
`rtti_emit.inc:967`, the string LITERAL `'ShortString'` in a type-name
function. Spot-checked two that look most like code and both are inside `{ }`:
`symtab.inc:6901` (`type TS = string[20];` inside a comment that closes at
6906) and `defs.inc:3054` (a field comment).

If that holds, step 3's explicit-declaration exposure inside the compiler is
**nothing**, and the entire self-host risk lives in what bare `string` means —
precisely the half the plan already declines to touch.

**What this does NOT do:** it does not lift the owner's instruction. He called
for a quiet tree and that is his call, not a grep's. What it changes is the
SCOPE ESTIMATE, and it should be reconciled before anyone plans a fleet stop
around ten declarations that may not exist. **Whoever reconciles it: my grep
was `string\[[0-9]+\]` and `\bShortString\b` over `compiler/*.pas *.inc`.
The way it could be wrong is a declaration reaching a fixed string through a
named alias defined outside `compiler/**`** — that would not match, and it is
the branch to check rather than re-running my pattern.

### Two load-bearing claims that gate step 1, not step 3

Both flagged by frankuser as unverified, and neither is an edit:

- **Bare `string` may mean different things inside `compiler/**` than in user
  code.** In user code plain `string` measures 8 — a managed `tyAnsiString`
  handle — while `defs.inc` calls `tyString` the self-host model. How that mode
  is selected was NOT traced, and the count of 69 rests on it.
- **The normaliser in `symtab.inc` presents fixed/short strings as `tyString`
  values on the grounds that they are "codegen-identical (same inline
  word-prefixed layout)". A byte prefix makes that sentence false.** The
  concentration behind the named emit pair is not total — aarch64 emits a
  length word inline in at least two places.

**So step 1's first job is an AUDIT for sites assuming an 8-byte prefix without
going through `EmitStoreStrLen`/`EmitLoadStrLen`, not an edit.** Note the eight
hardcoded arms in the section below are already eight such sites, found before
anyone went looking.

### A record of pleasant surprises is not evidence about the last step

This feature has measured cheaper than estimated four separate times — the kind
plumbed at 63 sites including every backend, `FrozenStrSlotSize` already
returning `cap+1`, 20 of 29 kind lists already naming it, capacity carriers
needing no change. **That record is about steps 1 and 2 and says nothing about
step 3**, which is the only step whose failure mode is the self-host fixedpoint
rather than a test.

### A third site class, not in the counts above

The backends **hardcode the 8-byte length word** in their char-to-inline-string
store arms; none of them calls `FrozenStrSlotSize` or `SizeOfSlot`, so they do
not appear in any grep of the sizing-oracle surface:

| backend | arm | writes |
| --- | --- | --- |
| x86-64 | `ir_codegen.inc:4573` (`IREmitStoreCharAsString`) | `mov qword [rdi], 1` / `mov byte [rdi+8], sil` |
| i386 | `ir_codegen386.inc:1900` | `mov dword [edi], 1` / `mov dword [edi+4], 0` / `mov byte [edi+8], al` |
| aarch64 | `ir_codegen_aarch64.inc:1918` | same shape |
| arm32 | `ir_codegen_arm32.inc:1671` | same shape |

Measured by inspection at `f74d2f851`; no build run for this note.

**Updated 2026-09-02: the predicted growth happened and it is now EIGHT arms,
not four.** `bug-a-char-into-shortstring-through-a-pointer-is-x86-64-only`
landed at `e4cba526a` (verified on origin/master), adding the matching
`IR_STORE_MEM` arms on i386/aarch64/arm32 which previously refused outright.
So each of the four backends now carries the literal 8-byte length word in
BOTH its `IR_STORE_SYM` and `IR_STORE_MEM` arm. That is **favourable for this
feature, not a conflict** — the shape is now uniform across four backends
instead of implemented-on-one-refusing-on-three, so the edit is mechanical
rather than implement-here-un-refuse-there. It is simply eight sites.

**Why this paragraph exists at all:** "grep the sizing oracles" is how someone
will scope this feature, and it comes back short by all eight. None of these
arms calls `FrozenStrSlotSize` or `SizeOfSlot` — they write the layout
literally. Scope this feature by the LAYOUT, not by the oracle's callers.

## Measured, fresh binary

Owner, 2026-09-02: *"shortstring is more or less what we call frozenstring"* —
then, correctly, *"iirc shortstring is 255(+1) char max ... since indeed
frozenstring can have arbitrary length."* Both halves confirmed:

```
                pxx      FPC (-Mobjfpc)
ShortString     263      256
string[10]       18       11
string[255]     263      256
string[256]     264      REJECTED: "string length must be a value from 1 to 255"
string[1000]   1008      REJECTED
```

`cap+8` against `cap+1`, uniformly.

**The 255 ceiling re-measured properly after the owner questioned it** — the
first version of this claim was one mode and stated generally. `string[1000]`
is rejected in **all eight FPC modes** (default, objfpc, delphi, fpc, tp,
macpas, iso, extendedpascal) with *"string length must be a value from 1 to
255"*; the boundary is exact (`string[255]` → 256, `string[256]` → rejected);
and no switch lifts it (`-Sh` swaps to ansistring rather than extending the
shortstring). **The limit is the REPRESENTATION, not a policy**: a 1-byte
length prefix cannot count past 255, so FPC could not raise it without ceasing
to be a shortstring. NOT checked: an obscure source directive — but any such
directive would have to widen the prefix, which is the same change. **`ShortString` is a strict SUBSET of
frozenstring**, and the reason is the header itself: a 1-byte length prefix
*cannot* express a cap above 255. The wide kind must therefore stay for N>255 —
this is not a replacement, it is the second of two.

> **PROVENANCE.** The first run of this measurement returned `8` for every row,
> from a `compiler/pascal26` that had not been rebuilt in a session where dozens
> of commits touched `compiler/**` — the exact stale-binary trap CLAUDE.md
> names. Rebuilt (`converged after 2 round(s)`, not the stamp path) to
> `5f275966bf50` at `bf92c45a7`; every number above is from that binary. The
> stale one was wrong by exactly 7 bytes on every row and looked plausible.

## OUR RECORD ALIGNMENT ALREADY MATCHES FPC — only the width differs

The owner read the earlier no-padding measurement as *"FPC has packed record
default to true, apparently."* Measured, and it is not: the earlier record had
TWO shortstring fields, which need only byte alignment, so nothing had to be
padded. Packing was never on.

```
                            FPC        pxx
record  string[2]+LongInt    8  b@4     16  b@12
packed  string[2]+LongInt    7  b@3     14  b@10
record  Byte+LongInt         8  y@4      8  y@4      <- identical
packed  Byte+LongInt         5  y@1      5  y@1      <- identical
```

**The bottom two rows are the finding.** Our padding and packing rules already
agree with FPC exactly. The top two diverge only because our `string[2]` is 10
bytes and FPC's is 3 — after which BOTH compilers correctly align the `LongInt`
to 4 from wherever the string ended.

**So this feature is the whole gap.** If `string[2]` were 3 bytes, `TU` would be
8 with `b` at offset 4 — byte-identical to FPC — with no alignment work
required. That is a much stronger claim than "sizes get closer": records
containing fixed strings become byte-compatible, which is what `file of T`
interop actually needs.

## CAPACITY STORAGE NEEDS NOTHING — the carriers are already kind-agnostic

The owner asked where the capacity is stored, and then answered the follow-on
himself: *"if we track that for fixedstrings, we can use the same field for
shortstrings already."* **Correct, and it withdraws a caution the coordinator
had just given about needing a new carrier per keying.**

`SymSubHi`'s own comment says it outright — *"frozen fixed-string capacity (max
chars) for **tyFixedString/tyShortString** slots"* — and every call site
confirms the shape: the capacity table stores a bare `N` while the KIND travels
beside it in a separate table.

```
FrozenStrSlotSize(tk,                       SymStrCap[retSymIdx])
FrozenStrSlotSize(tk,                       SymPtrElemStrCap[...])
FrozenStrSlotSize(IntToTypeKind(UFldTk[i]), UFldStrCap[i])
FrozenStrSlotSize(Syms[i].ElemType,         SymStrCap[i])
```

Kind tables: `UFldTk`, `AliasTk`, `ArrTypeElemTk`, `Syms[].ElemType`. Capacity
tables: `SymStrCap`, `SymSubHi`, `SymPtrElemStrCap`, `UFldStrCap`, `UFldSubHi`,
`AliasStrCap`, `AliasSubHi`, `ArrTypeElemStrCap`, plus the transient
`LastTypeStrCap`/`LastTypeSubHi`.

**So a `string[10]` that re-types writes `10` into the SAME StrCap slot and
`tyShortString` into the SAME Tk slot, and `FrozenStrSlotSize` already returns
11 instead of 18 with no change.** No tenth carrier, no new table.

**Keep the two problems separate.** That the capacity has no canonical home —
nine carriers keyed three ways, which is why the clamp can be right while the
stride is wrong in one expression — is a real design defect and belongs to
[[umbrella-sizeof-is-one-answer]]. It is **not** an obstacle to this feature,
and this feature does not make it worse.

## OVERFLOW/TRUNCATION IS SAFE TODAY, AND THIS CHANGE DOES NOT TOUCH IT

The owner raised the real semantic worry: the cap is **compile-time-only
information**, so `a: string[10]; a := 'hello'+' '+'world'` has to be clamped by
something that was TOLD the cap. Measured, and it is:

```
                            pxx              FPC
a := 'hello'+' '+'world'    [hello worl] 10  [hello worl] 10
25x accumulate loop         [xxxxxxxxxx] 10  [xxxxxxxxxx] 10
r.inner[0] := 20 chars      [hello worl] 10  [hello worl] 10
guard / tail after store    intact           intact
```

Byte-identical to FPC in every shape tried, and **correct even in the record-
field-array shape where frankB measured the stride as 264.** That is a sharper
statement of this umbrella's thesis than the four-oracle census: in
`r.inner[0]` the capacity reaches the **clamp** (which correctly uses 10) while
the **stride** falls back to the `tyString` default. One number, two consumers,
two side-tables — one populated, one not.

**For this ticket the consequence is simple: the clamp bounds the LENGTH, not
the prefix**, so 8 bytes of prefix becoming 1 does not touch the overflow
machinery. The cap ceiling dropping to 255 is a parse-time check, not a runtime
one.

**Limit of the claim:** four shapes measured (bare var, concat expression,
25-iteration accumulate, record-field array). NOT covered — the open-array
parameter shape in
[[bug-p-a-string-n-element-loses-its-capacity-in-three-container-shapes]],
which reads `a[2]` empty despite a correct stride and is frankb-a9's.

## THE PREFIX IS 8 BYTES ON EVERY TARGET — and tyShortString is not a byte prefix TODAY

The owner asked whether `tyString` uses a *word* for the length. Measured, and
the word "word" is the confusing part: it means a **machine word**, not Pascal's
2-byte `Word`. `FrozenStrSlotSize` returns **`cap + 8` hardcoded** — NOT
`cap + TARGET_PTR_SIZE` — so the prefix is 8 bytes on every target despite the
comment calling it "NativeInt".

**And `tyShortString` has no byte-prefix semantics today.** A normaliser in
`symtab.inc` makes fixed/short strings present as a plain frozen `tyString`
*value*: *"they are codegen-identical (same inline word-prefixed layout); only
the slot SIZE differs, and that is carried by the storage kind + SymStrCap.
Normalising the node value-kind here keeps every existing `= tyString` value
check (write, concat, compare, ...) working without widening ~150 sites."* So
`FrozenStrSlotSize(tyShortString, cap)` already returns `cap+1` while the
codegen writes a word. Nothing exercises the mismatch yet.

### The cost structure, corrected

An earlier version of this ticket quoted **9 sites** for the mixed-kind work.
That number is right for what it measured (enumeration lists omitting
`tyShortString`) and **was not measuring the load-bearing thing.** The real
structure:

| number | what it is | does it change? |
| --- | --- | --- |
| **306** | `tyString` comparisons (252 `=`, 54 `in [...]`) | **NO** — the normaliser exists to keep them working. That is the design. |
| **13** | refs to the named `EmitStoreStrLen`/`EmitLoadStrLen` pair (symtab 7, ir_codegen 2, one each in 386/aarch64/arm32, pasparser_lval 1) | **YES** — this is where the prefix width lives |
| **9** | enumeration lists omitting `tyShortString` | yes, but they are kind lists |

**The design already anticipated this**: value kind normalised, storage kind
carries the width. That is why every measurement has come out cheaper than
expected.

### THE HAZARD — name it before starting

The normaliser's justification is that fixed and short strings are
**"codegen-identical"**. A byte prefix makes that **false**. Any site that reads
the length through the normalised VALUE kind, rather than through
`EmitStoreStrLen`/`EmitLoadStrLen`, then uses the wrong width **silently** —
and the concentration is not total: aarch64 emits `str x9, [x6] (length word)`
inline in at least two places, and 16 comments across the backends name the
length word directly.

**First job is therefore an audit, not an edit**: find every site that assumes
the prefix is 8 bytes without going through the named pair. Per the guard rules,
a test for this must assert the STRIDE and a `string[N]` whose content length
differs from its capacity — a value check cannot see a wrong prefix width when
the string happens to fill its slot.

## THE BIG FLIP IS LAST, AND IT SERIALISES THE FLEET (owner, 2026-09-02)

*"that big flip should be LAST. and likely, we dont want any other work done at
that point since this affects our self-compile capability."* **This is a hard
constraint, not a preference** — treat it like `make pin`: one of the few things
that genuinely serialises, per CLAUDE.md's "sequence the few things that
genuinely serialise ... landing order when a change is only correct as a whole".

**And the flip is really TWO flips of very different risk.** Measured in the
compiler's own sources:

```
string[N] declarations       :  3
array of string[N]           :  7
plain `string` declarations  : 69
```

**Flip A — explicit `string[N]`, N <= 255, re-types to `tyShortString`.**
Touches **10** declarations in the compiler. The capacity carriers and
`FrozenStrSlotSize` already handle it (see above). Low exposure.

**Flip B — bare `string` changes kind.** Touches all **69**, and changes both
the slot (264 -> 256) and the prefix width (8 -> 1) for every string the
compiler itself uses, because `tyString` is *"the self-host model"*
(`defs.inc:1118`). **This is the one that endangers self-compile.**

**Leaving bare `string` exactly as it is — still `tyString`, still
`LOCAL_STR_CAP + 8` — means Flip B never happens** and Flip A's self-host
exposure is ten declarations rather than sixty-nine. That is a far smaller
thing to stop the fleet for, and it is the default this ticket recommends.

> **VERIFY BEFORE TRUSTING THIS SPLIT.** In USER code plain `string` measures 8
> — a managed `tyAnsiString` handle — while `defs.inc` calls `tyString` the
> self-host model. So bare `string` means different things in the compiler's own
> sources than in user code, and **the coordinator did not trace how that mode
> is selected.** The 69 rests on it. Establish it first.

Recovery if the flip does break the fixedpoint: reseed from the pin and `touch`
the sources — the pinned binary predates the flip by construction, so it is
always a valid seed. Say which pin in the commit.

### ANSWERED: "IS THE WALKER ONE FIX OR THE FIRST OF A CLASS?" — A CLASS, FOUR CAUSES

frankuser's question, 2026-09-02, and the answer matters more than any of the
four fixes: **a walker-only fix would have closed ONE of four and left three.**
All four present as "a frozen prefix read at the wrong width" and they have
genuinely different causes:

| # | site | cause | scope |
| --- | --- | --- | --- |
| 1 | `IRFrozenKindOfAddr` (`ir.inc`) | `p^` lowers to a pointer LOAD tagged tyPointer, matched neither arm, fell to the tyString default | **shared — all 7** |
| 2 | `EmitStrCmpReg` (`symtab.inc`) | signature had **no kind at all**; hardcoded the layout 4 times | x86-64 |
| 3 | arm32 compare callers `:2055 :2095 :2140 :2190` | extractor was width-aware; **all four callers passed `IntToTypeKind`** | arm32 |
| 4 | x86-64 `IR_STORE_MEM` | never converted, **and read its dest kind from a stale `symIdx` belonging to another arm** | x86-64 |

**(1) closes READ and WRITE together on every target**, which franks-ab's
evidence predicted before the fix existed: the corrupted memory from
`p^ := c` was BYTE-IDENTICAL across two word sizes and four independently
written backends. Nothing but a shared cause produces that. The pointee's kind
was never missing — it is `PtrElemTk` on the pointer's own symbol and no
reader asked. **The arm lives in the walker so i386 inherits the fix rather
than the hole**, since it is not a caller yet.

**(3) is the one that should not have happened**, and it is the design finding.
`IRStrTkOf`'s docstring already prescribes the remedy verbatim — one
substitution rather than one per site — the fix was designed, named,
documented and applied on aarch64, and arm32's four sites simply never got it.

**THREE SITES NOW CARRY A COMMENT WARNING THE NEXT AUTHOR NOT TO USE
`IntToTypeKind` HERE — aarch64 `:2022-2027`, riscv32 `:503-507`, arm32
`:1299` — AND ARM32 VIOLATED ITS OWN COMMENT AT FOUR CALL SITES.** Two is a
smell, three is a design flaw, and a comment is not a mechanism. **The real
question for the morning is why asking a frozen prefix its width is a per-site
decision at all** — the same shape as `normalise-dont-special-case`. Banked
deliberately rather than acted on: this is a normalisation decision, not a
fix, and it is the owner's.

**Measured after all four: 24/24 four-mode configurations against the FPC
3.2.2 oracle on x86-64/aarch64/arm32/riscv32, plus the write probe giving
FPC's exact bytes on all SIX runnable targets, plus six comparison shapes
green on five of six.**

### NOT IN THIS CLASS: wasm32's comparison bug is PRE-EXISTING

**`var_var`, `diffcap` and `var_ne` are wrong on wasm32 while `var_lit` and
`lit_var` are correct** — literal operands right, variable operands wrong.
That is operand selection in `WasmStrParts`, not prefix width.

**Proven not ours: the pinned compiler, with NO flag, produces byte-identical
wrong answers.** It predates every commit of this feature. Do not merge it
with the width class — merging is what would send the next reader to operand
selection when arm32's problem was one identifier. frankwasm owns it.

**AND WIDTH IS NOW RULED OUT BY MEASUREMENT RATHER THAN ASSERTED, WHICH
MATTERS BECAUSE I LATER ARGUED THE OPPOSITE FROM THIS SEAT.** frankwasm
measured at HEAD, at DEFAULT, with the walker fix present:

| | `SizeOf(TS)` | `var_var` | `var_lit` | `lit_lit` |
| --- | --- | --- | --- | --- |
| wasm32 | 18 | **FALSE** | TRUE | TRUE |
| native | 18 | TRUE | TRUE | TRUE |

`18 = cap 10 + 8`, so the VARIABLE carries the same 8-byte prefix the literal
does and **there is no narrow kind anywhere in that program.** The failing pair
and a passing pair are therefore both SAME-WIDTH, and width cannot discriminate
between them. That is a quantity; the paragraph above it was a pattern of rows.

**What I got wrong, and it is the same error mirrored.** I told frankwasm its
"operand selection, not width" reading was the symptom of a width bug —
variable-vs-literal IS the cross-width pair under `-dPXX_SHORTSTRING`, since
literals keep their 8-byte pool prefix permanently. **True for x86-64 and
arm32, where a width-only fix turned all six shapes green, and not a mechanism
for a backend I had not measured.** frankwasm had already retracted offering a
mechanism for backends IT had not measured; I made the identical move in the
message correcting it, from the shared-surface seat, where a mechanism claim
travels furthest. Caught by frankwasm within the hour.

**The generalisable part: the row pattern survives across two unrelated causes,
which is what makes one explanation look like it covers both.** Same shape as
this ticket's own census artefact — the ratios survived the double-count, which
is what made an artefact look like a distribution. A symptom that is stable
across backends is evidence of a shared cause ONLY if the quantity behind it is
also shared. Ask for the quantity.

**Clean separation, recorded as a positive result:** the walker fix `764dc3a30`
is in frankwasm's tree and `var_var` is still FALSE. The walker correctly did
not touch this. That is the scope of the walker fix being right, not a residue.

**Correction to a population figure in circulation: riscv32 does NOT refuse the
flag.** It accepts it and passes all four modes plus all six comparison shapes;
it is a converted backend, measured here.

### PHASE 2 STATUS — SAY IT AS "N VERIFIED", NEVER AS "SEVEN CONVERTED"

**The count and the qualification must be ONE phrase, because the count is the
repeatable part and the caveat is not.** "Seven backends converted, with a
caveat on xtensa" loses its second half in one hop; "six verified, xtensa
converted-unexecuted" cannot be halved without becoming obviously incomplete.
Same discipline CLAUDE.md already applies to self-host fixedpoint versus
"zlib matches the gcc oracle" — two claims that must never be conflated.

| backend | codegen | how it is verified |
| --- | --- | --- |
| x86-64 | done | native, and the FPC 3.2.2 oracle directly |
| aarch64 | done | `qemu-aarch64`, six configurations vs the oracle |
| arm32 | done | `qemu-arm`, four configurations vs the oracle |
| i386 | open | `qemu-i386` (or native ia32) — runner exists |
| riscv32 | open | `qemu-riscv32` — runner exists |
| wasm32 | open | **`wasmtime` runs it — measured, see below** |
| xtensa | open | `qemu-xtensa`, with `--platform=posix --xtensa-soft-mulhigh` |

**wasm32 IS RUNNABLE, and the earlier claim in this ticket's own reporting that
it was not is WRONG.** It was inferred from `tools/run_target.sh` having no
wasm32 arm and never measured. `wasmtime` is installed and runs a frozen-string
probe correctly today: `string[10] := 'hello'` prints `hello|5|h`. What is
genuinely missing is tooling, not capability — a `wasm32)` arm in
`run_target.sh` and a `test-wasm32` target. **That is an afternoon of tooling,
not an open question about what a green would mean.** The instrument answered a
question about the harness and was read as a question about the platform.

**XTENSA CAN RUN, AND THE CLAIM ABOVE THAT IT COULD NOT WAS MINE AND WAS
FALSE — NOT JUST NOW, BUT EVER.** I wrote that xtensa *"cannot compile a
frozen-string program at all today"* from one observation: bare
`--target=xtensa` refusing with `external (dynamic) symbols are not supported
on this target`. That refusal is the **ESP platform default** — bare-metal /
FreeRTOS, no libc, no dynamic segment, deliberately — and not a property of the
backend. Measured:

```
--target=xtensa                                       refuses (ESP default)
--target=xtensa --platform=posix --xtensa-soft-mulhigh builds, and
                                        qemu-xtensa prints hello|5|h
```

Those two flags are the standard xtensa invocation on dozens of Makefile rows
from :17920; `run_target.sh:88-100` documents both and names the misread
outright; **two frozen-string programs already compiled for xtensa in the suite
before phase 2 existed** (`test_cross_frozen_strlen_deref` Makefile:17975,
`test_frozen_string_cross_b305` :18065); and `symtab.inc:11541` records the
compiler itself built that way. Four corroborations, all sitting in the tree,
none of which anyone checked before the claim had re-sequenced a session.

**TWICE IN ONE EVENING I TURNED A DEFAULT'S REFUSAL INTO A PLATFORM'S
INCAPABILITY, AND THAT IS THE DURABLE PART OF THIS ENTRY.** First wasm32 —
`run_target.sh` has no `wasm32)` arm, which is a fact about the HARNESS, and I
reported it as "no runner exists". Then xtensa — a default profile refuses,
which is a fact about the PROFILE, and I reported it as "the backend cannot
compile this". **Neither instrument errored. Both answered correctly about
something narrower than the claim I drew from it**, which is exactly the
failure mode CLAUDE.md describes, committed by the session quoting it. The
guard that would have caught both is the same one line: *before writing "X
cannot", try the second invocation.*

**Do NOT write "seven verified" until xtensa's rows have actually run.** It is
a plan, not a result. The floor is no longer "six verified, xtensa
converted-unexecuted" — but the replacement is "six verified, xtensa in
progress", not seven.

**The three that were found by RUNNING, none of which a reading would have
caught** — this is the estimate for how many remain per backend:
1. `Length`'s arm accepts a POINTER-typed node, so `IRStrTkOf` short-circuits
   on the node's own kind and only `IRFrozenKindOfAddr` consults the symbol.
2. arm32's WIDE prefix is TWO stores, so a helper copied from a 64-bit backend
   writes garbage into the high half of the length.
3. `PXXWriteFrozenW` is SHARED RUNTIME, not backend code — see below.

### `compiler/builtin/builtinheap.pas` IS SHARED SURFACE FOR THIS FEATURE

**Not obvious, and it broke a backend that had already been called complete.**
`PXXWriteFrozenW` hardcoded a machine-word prefix and is called by aarch64,
arm32, riscv32, xtensa and wasm32 — only x86-64 emits the padding inline. A
frozen write with a FIELD WIDTH was therefore wrong on aarch64 after its
conversion was declared done.

It survived because the pad is `max(0, wid - len)`, a RUNTIME quantity, so the
HELPER is what reads the prefix — and at width 0 the helper is never called.
Width 0 was all the tests had. `test_shortstring_mixed_widths` now carries
`pad`/`padw` rows; positive control confirmed, `pad` collapses to `<>` with the
fix reverted.

`PXXWriteFrozenBW` is the one-byte sibling. **Two procedures rather than a
width parameter, deliberately:** the caller knows the width at COMPILE time, so
a parameter would put a runtime branch inside every write, and a wrong value
there is not a misformatted field — reading a 1-byte prefix as a machine word
is a `write()` of the address space. Both survive phase 4, since bare `string`
stays tyString with its machine-word prefix. **A backend picks between them; it
does not add a third.**

### A BACKEND'S ACCEPTANCE ROWS MUST INCLUDE A NONZERO FIELD WIDTH, FROM THE START

frankc-af's point, 2026-09-02, and it is the right generalisation of the
`PXXWriteFrozenW` hole: **at width 0 the runtime helper is never called, so a
suite made entirely of width-0 rows certifies a backend as complete while its
width path is broken.** That is exactly what happened to aarch64. If each
backend writes its own acceptance rows from the aarch64 example, each one
re-earns the same green that was wrong.

`test_shortstring_mixed_widths.pas` carries `pad` and `padw` (both `:9`) for
this reason. **Wire that file, do not hand-write a width-0 suite.** The
positive control is recorded: `pad` collapses to `<>` with the fix reverted.

**AND THE WIDTH-0 BYPASS IS NOT UNIFORM ACROSS BACKENDS, which makes the row
MORE necessary rather than less** (franks-ab, 2026-09-02): **xtensa calls the
shared helper at EVERY width including 0, where arm32 calls it only at
`wid > 0`.** So "every test used width 0" is a *masking* explanation on some
targets and cannot be the explanation on others — on xtensa a width-0 test
already exercises the helper, and a bug there would have shown up without any
field width at all.

That cuts both ways and both are worth knowing: a backend in the xtensa shape
gets helper coverage for free from rows it already has, and a backend in the
arm32 shape has a whole path that no existing row can reach. **Do not reason
about the coverage of the OTHER backends from your own.** The reason the
aarch64 defect survived is specific to aarch64's dispatch, not a general
property of the tests.

**CALL SITES OF THE SHARED WRITE HELPER — AND THE FIRST COUNT WAS INFLATED,
WHICH POINTED FOUR BRIEFS AT THE SMALLEST PART OF THE JOB.**

A grep of the helper NAME gave wasm32 6 against every other backend's 1-2, and
that number went into four briefs, led with, as the reason wasm32 was hardest.
**frankwasm re-counted by opening them: three of the six are comments, and two
of the three code lines are ONE site (`WasmWriteHelper` then `WasmCall`).** The
aarch64 row was inflated the same way (one comment, one call), as was riscv32's
(the call and its own `if procIdx < 0` guard).

| backend | real W/BW decision sites |
| --- | --- |
| wasm32 | 2, and only **1** is a genuine W-vs-BW choice |
| all others | 1 |

**The literal path must KEEP `PXXWriteFrozenW` and is not a choice at all:** an
interned literal is laid out in `Data[]` with an 8-byte prefix by construction
(`ir_codegen_wasm32.inc` states it at 2596 and relies on it at 2612 and 6281
via `Strs[si].Offset + 8`), and a literal is never a tyShortString variable.
Same reason `IR_INDEX`'s `AN_STR_LIT` arm keeps its `-7` permanently.

**This is CLAUDE.md's own rule, broken by the person quoting it all evening:
*a finding that falls out of a grep needs the same interrogation as one that
falls out of a hypothesis*.** I relayed the table without opening a single
site. It did not merely overstate a number — it aimed four sessions' attention.

**The inflation was SYSTEMATIC, not random, which is why it looked plausible.**
Every `FindProc` in this codebase is followed by an `if procIdx < 0 then
Error(...)` guard naming the same string, so a name grep counts every real call
site TWICE by construction, and comment references add more on top. A count of
helper call sites taken by grep is therefore roughly double the truth
*everywhere*, and the ratios between backends survive — which is exactly what
makes it read as a real distribution rather than an artefact.

**WHERE THE REAL wasm32 EXPOSURE IS, and no grep of the helper name reaches
any of it:** the width-8 assumptions spread through the backend — `Length`
loading the prefix as an `i32.load` at offset 0 and treating it as the low word
of an 8-byte field (4305), the frozen store and copy paths (4588, 4683), and
several `+ 8` address computations. **"Pick, don't add a third" still stands
and is still cheap; it was simply never the hard part.**

### The per-target guard is ONE ROW PER TARGET so parallel work does not collide

`TargetHasByteStrPrefixCodegen` (`util.inc`). It was a chain of
`TargetArch <> X` in a single condition, which meant every session converting a
backend edits the SAME LINE to enable its own target — five conflicts in one
expression, each of them a correct change, and a merge that resolves them by
keeping one. A row conflicts only with itself. **Add your row; do not touch the
others.** The whole function goes at phase 4 with the flag.

### P4's DEFINITION OF DONE INCLUDES DELETING `-dPXX_SHORTSTRING` (added 2026-09-02, phase 2)

**Phase 2 introduced an opt-in define, `-dPXX_SHORTSTRING`, and P4 is not done
until it is GONE — same commit as the flip, not a follow-up ticket.** It is
listed here rather than filed separately on this ticket's own reasoning about
Track T's `--shorts` dodge: *"a ticket whose entire content is 'stop working
around a thing that now works' is exactly the ticket nobody picks up, and the
dodge then becomes permanent by default."* An off-by-default scaffolding flag is
that ticket, and within a week it reads as a legitimate feature nobody dares
delete.

**Why it exists at all:** phase 2 as written was not hard, it was
INCONSISTENT — *"nothing re-types yet, so nothing observes it"* together with
*"produce a positive control"* demands a guard for code that has no reachable
spelling, and a guard that cannot fail prints PASS. No spelling could produce a
`tyShortString` variable, so seven backends of machine code would have been
written and none of it executed. The flag is the reachable spelling: under it,
`string[N]` with N <= 255 binds to `tyShortString`. Off by default, so the
fixedpoint, the pin and every existing test are byte-for-byte unaffected.

**P4's acceptance rows, then, are three and not two:**
1. `string[N]`, N <= 255, binds to `tyShortString` with no define set.
2. The offset assertion — chars start at +1, `s[0]` is the length byte.
3. **`PasDefineExists('PXX_SHORTSTRING')` returns zero grep hits**, and the
   per-target refusal it guards is gone with it. The flag's whole purpose was
   to make phase 2 testable before phase 4 existed; once `string[N]` re-types
   unconditionally, the flag's `then` branch IS the default and the `else`
   branch is the dead one.

**The four build combinations were measured before the backend grind, not
after** — `PXX_MANAGED_STRING` and `PXX_SHORTSTRING` are two independent axes,
so there are four, and the frozen x shortstring corner is the one no default
build visits. **Two of the four were broken, and both bugs were on x86-64,
the backend already declared complete:**

| mode | `b := s` (narrow -> wide) | cause |
| --- | --- | --- |
| managed x shortstring | `out of memory (heap arena mmap failed)` | `EmitAnsiStrFromInlineString` hardcoded an 8-byte read |
| frozen x shortstring | length 255, 255 blanks | the frozen->frozen arm read the width off `IRTk[valueNode]` |

**The direction is the lesson, and it generalises past this feature.** Both
readers fall back to `tyString` when they cannot tell, and `tyString` is the
WIDE answer — so every wide -> narrow path was correct and every narrow -> wide
path was wrong. A single-width test cannot see this at all, and
`test_shortstring_byte_prefix` holds exactly one string. `test_shortstring_
mixed_widths` is the four-mode guard, and its two positive controls fire in
DISJOINT modes: reverting the frozen->frozen half moves rows only under frozen
x shortstring, reverting the frozen->managed half only under managed x
shortstring. Neither half alone would have been caught by a three-mode matrix.

## CONSTANTS: the landing order, and it is narrower than it looks

The owner named the sequencing risk: *"the big catch is — constant strings.
right now we all parse them as fixedstring (i think, or do we convert them all
to ansistring?). so, all plumbing has to be in place before we convert short
string constants to shortstrings."* Measured — and it is **neither**:

**An untyped string LITERAL types as `tyString`.** Three source comments say so
(`pasparser_expr.inc:631`, `:5590`, `:9539`). It has no storage of its own and
is converted at the point of use, so a `tyShortString` destination needs only a
conversion ARM — one of the nine sites above. **Nothing about literals has to
change at all.**

**A TYPED constant is what forces the issue.** `const T: string[10] = 'hello'`
measures **18** — real `.data`, emitted at compile time, byte-identical in
layout to a var of the same type. These are what must not change representation
before the readers understand the new one.

```
                          pxx     FPC
typed const string[10]     18      11
var plain string            8     256
var string[10]             18      11
```

**LANDING ORDER, each step independently green:**
1. byte-prefix codegen per backend (load/store the length as a byte)
2. the nine conversion/enumeration arms, including `tyString -> tyShortString`
3. only then, typed constants for `N <= 255`

**AND ONE THING NOT TO DO.** That table shows FPC's plain `string` is **256
bytes** — its default string genuinely IS a shortstring, which is the `{$H}`
default. Ours is an 8-byte managed handle. Someone will read the 8-vs-256 row
as the last piece of parity and map plain `string` onto `tyShortString`. **That
would replace managed strings with 256-byte stack blocks, and it is not part of
this ticket.** The owner asked for a second kind alongside `tyFixedString`, not
a new default.

## Why it is cheaper than "a later codegen slice" suggests

`tyShortString` is **not** a new kind to build. 63 sites, 18 files:

```
symtab 15  pasparser_decl 11  pasparser_lval 9  pasparser_expr 6
pasparser_proc 3  defs 3  rtti_emit 2  pyparser 2  ir_codegen386 2  ir 2
+ abi, cparser, ir_codegen, and the aarch64 / arm32 / wasm32 backends
```

`FrozenStrSlotSize(tyShortString, cap)` already returns `cap+1`. The name
binding at `pasparser_decl.inc:540` is a **one-line interim** that says so in
its own comment. What is missing is the codegen that loads and stores the length
as a byte rather than a word.

## The asymmetry with the set decision — this does NOT come free

[[decide-a-what-a-set-costs-bits-bytes-bounds-and-what-file-of-t-writes-to-disk]]
concluded that set file IO needs no representation change, because our 32-byte
mask is a byte-exact **zero-extension** of FPC's and truncation suffices.

**Strings have no such trick.** The length word is at the FRONT and is a
different width, so an on-disk fixed string is a genuine conversion under the
current layout — and a record containing one cannot blit (18 in memory, 11 on
disk, every later field shifted). Implementing this removes that for N<=255,
where sets could not be fixed so cheaply. **Strings in records are also far more
common than sets in records**, so the same argument is worth more here.

Blocks-relation: [[feature-pascal-typed-and-untyped-files]] — this is the
difference between `file of T` blitting and marshalling for the common case.

## THE CLUSTER WAS NOT A CLUSTER — my count was wrong (corrected 2026-09-02)

This ticket said *"eight open tickets name shortstring, several cross-target"*
and offered it as a lead. **Seven of the eight are in `done/`. One is open.**
frankc-af's census (`586eae2f8`) established it; the count came from an
`ls devdocs/progress/*/` that globbed EVERY folder, `done/` included, and I read
the result as open tickets. **The instrument did not error — it answered a
different question.**

Worse in a specific way: I hedged the *inference* (*"I have not established the
interim mapping causes any of them"*) and not the *premise*. The hedge made the
claim read as careful, which made the unmeasured number MORE credible rather
than less, and a peer spent a census on it.

**The one survivor is not a layout question and this feature would not close
it.** `bug-a-char-into-shortstring-through-a-pointer-is-x86-64-only` is a
missing EMITTER ARM — three explicit `Error()` arms beside working code, at
exactly one intersection (char VALUE + string DEST + POINTER store); a literal
through a pointer works everywhere, a char without a pointer works everywhere.
Under either layout each backend still needs the arm written; the byte prefix
makes them marginally simpler and removes none. riscv32 now passes, so a
non-x86-64 reference already exists.

**So: strike the cluster as support for this feature.** What survives untouched
is the `file of T` argument, which stands on its own and was always the real
one — a record containing a `string[10]` is 18 bytes in memory and 11 on disk,
plus the record padding (offset 112 vs 101) that the byte prefix also removes.
**The justification is narrower, not weaker in kind.**


## The byte prefix is NOT the whole record-layout gap — alignment is hardcoded

Checked 2026-09-02 (frankC) against the packing measurement added in
`76342c379`, because that claim is now the load-bearing argument for this
ticket's rank and it deserved a second instrument.

**The packing half reproduces exactly.** pxx and FPC agree with no string in
sight:

| | pxx | FPC `-Mobjfpc` |
| --- | --- | --- |
| `record a: Byte; b: LongInt; end` | 8, b@4 | 8, b@4 |
| `packed record a: Byte; b: LongInt; end` | 5, b@1 | 5, b@1 |
| `record a: Byte; b: Byte; end` | 2, b@1 | 2, b@1 |

**But "the only divergence is the string field's own width" is not right, and
"no alignment work" is the part to correct.** Isolating the string field:

| | pxx | FPC |
| --- | --- | --- |
| `record a: Byte; s: string[4]; end` | 24, **s@8** | 6, **s@1** |
| `record s: string[4]; end` | 16 | 5 |
| `record a: Byte; s: string[4]; b: LongInt; end` | 24, s@8, b@20 | 12, s@1, b@8 |

pxx pads **seven bytes** before the string. FPC pads none — a shortstring is a
byte array and aligns to 1. So a mixed record diverges in TWO ways: the string's
width *and* the string's alignment. The `LongInt` observation holds — once each
compiler has placed the string, both align `b` correctly relative to their own
offset — but that is downstream of a field that is already in the wrong place.

**Why the size fix alone will not move it** (read from source, not measured —
there is no 5-byte string today to measure with): the record layout does not
derive a frozen string's alignment from its size. It is a literal, at three
arms in `pasparser_decl.inc`, and **each already names `tyShortString`**:

```pascal
else if (fTk = tyFixedString) or (fTk = tyShortString) then
begin
  fSize  := FrozenStrSlotSize(fTk, fStrCap);   { becomes cap+1 -- this is the fix }
  fAlign := TARGET_PTR_SIZE;                   { stays 8 -- this is not }
end;
```

`TypeAlign`/`TypeFieldAlign` are not consulted here, so making
`FrozenStrSlotSize` return `cap+1` would give a `string[4]` field five bytes
that are still 8-aligned: `record a: Byte; s: string[4]; end` would go from
24/s@8 to 16/s@8, not to FPC's 6/s@1.

**This does not weaken the ticket — it sharpens the work item.** The blit
argument stands, and the alignment side is three lines (`fAlign := 1` for
`tyShortString`, the wide `tyFixedString` keeping pointer alignment). It just
has to be in the plan, or the feature lands, `SizeOf` matches FPC, and records
still do not blit — which is the failure mode where the acceptance test passes
and the goal is missed.

**Acceptance should therefore assert an OFFSET, not just a size.**
`record a: Byte; s: string[4]; b: LongInt; end` must be 12 with s@1 and b@8. A
size-only row can be satisfied by a record that is the right total with the
fields in the wrong places.

### MEASURED IS NOT WIRED — wasm32 is the only converted backend with zero flagged rows

Review of `0973746b0` (wasm32, phase 2 backend four). **The conversion itself is
clean** — verified against the source, not the commit message: every surviving
literal 8 in `ir_codegen_wasm32.inc` is correctly invariant (`WASM_STR_SLOTS` is
a pool slot count with one use at :5978; `Strs[si].Offset + 8` at :2692/:4385/
:6425 is interned literals, permanently 8 by construction; :2534/:2555 are
PXXAlloc alignments; :567/:1344/:1392 are prose about USER-written pointer
arithmetic). The three primitives ask `FrozenStrPrefixSize` (:2165/:2177/:2191,
store at :4767/:4780), and :4240/:4242 branches to the EXISTING
`PXXWriteFrozenBW` rather than inventing a third path, with :4139 keeping the
wide helper permanently on the `IR_CONST_STR` literal arm. All three review
classes pass.

**The finding is about coverage, and it is this ticket's own nonzero-field-width
rule one step further out.** Counting Makefile rows that pass a mode flag:

| arm32 | riscv32 | aarch64 | xtensa | **wasm32** |
| --- | --- | --- | --- | --- |
| 36 | 31 | 29 | 6 | **0** (of 22 rows) |

The eight configurations in that commit were really measured and they are not
wired anywhere. wasm32's one standing shortstring row is
`test_shortstring_trunc` at DEFAULT — which, **by the commit's own byte-identity
proof (35 modules identical before and after), is exactly the path the change
did not touch.** So the standing test covers the proven no-op and none of the
conversion, and `test_shortstring_mixed_widths` — the nonzero field width `s:9`
that reaches `PXXWriteFrozenBW` — is wired for the other four and not for this
one.

**Why this is not ordinary missing coverage: P4 deletes the flag.** Today an
unwired backend is a gap in a path most programs never take. After the flip
`string[N]` re-types unconditionally, and that same backend becomes an
UNVERIFIED DEFAULT. The window in which this is cheap to fix closes at P4, which
is the argument for wiring it before the flip rather than after.

`run_target.sh` now has a `wasm32)` arm and `test-wasm32` runs 22 executed rows
under `wasmtime`, so the tooling that would have blocked this already exists —
what is missing is rows, not capability. Routed to frankwasm and frankc-af
(who built the arm) rather than taken, to avoid two sessions in one Makefile
region; shared-surface on-call will take it if neither has it.

#### Two properties of the wasm32 rows that a reviewer will misread (frankwasm)

Recorded BEFORE the rows land, because both are cases where the correct result
looks like a mistake and the mistake looks correct.

**`ssbp_short` printing `sizeof 11` against `ssbp_default`'s `18` is the
POSITIVE CONTROL for the whole set, and must not be collapsed as redundant.**
If the short row ever prints 18, the backend silently ignored the flag — and
**every other row in the set still passes**, because they would all be
measuring the default path twice. This is this ticket's own recurring shape:
the guard that cannot fail prints PASS. The pair IS the instrument; either row
alone is decoration.

**`ssmw_short` being byte-identical to `ssmw_default` is the CORRECT result and
will read as a copy-paste error.** Cross-width conversion must yield the same
VALUES at either prefix width — that is what `w2n`/`n2w` mean — so identical
output is the property under test, not a duplicated row. Anyone tempted to
"fix" it by making the two differ would be asserting that conversion changes
the value.

### PHASE 2 IS ONE BACKEND FROM DONE — i386 alone

`TargetHasByteStrPrefixCodegen` now carries six of seven rows: x86-64, aarch64,
arm32, riscv32, xtensa (`fe8662e24`), wasm32 (`0973746b0`). **Only
`TARGET_I386` is missing.** Note that `0973746b0`'s message lists xtensa as
still open — it was already in; read the function, not a commit message, for
what is converted.
