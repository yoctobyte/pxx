---
track: A+S
prio: 45
type: bug
status: done
found: 2026-08-29
found-by: frankD
summary: "DEMONSTRATED: both comparisons print WRONG on both ABIs. `'zzz' < 'aaa'` on xtensa compares the two heap HANDLES as signed ints and answers by allocation order — the exact defect PXXStrCmp3 was added to fix, applied to i386/aarch64/arm32/riscv32 with xtensa never visited, because the helper's own comment says 'the four cross backends' when there are five. Fix accepted by frankS."
---

# xtensa has no ordered string compare: `a < b` sorts by heap handle

Found by the invariant sweep
([[audit-a-a-comment-asserting-an-invariant-is-a-claim-about-a-sibling-arm-nobody-checked]])
working the `builtinheap.pas` seam
([[audit-a-builtinheap-invariants-x86-64-inlines-past]]). It is the audit's shape
exactly: a fix applied to the arms someone had open, with the fifth arm never
visited, and a comment that counts the arms wrong.

## What is wrong

`compiler/ir_codegen_xtensa.inc:1622` guards the managed-string compare arm on
equality only:

```pascal
if ((op = Ord(tkEq)) or (op = Ord(tkNeq))) and
   ((IntToTypeKind(IRTk[left]) = tyAnsiString) or (IntToTypeKind(IRTk[right]) = tyAnsiString)) then
```

`<`, `<=`, `>`, `>=` on an `AnsiString` therefore fall past it into the generic
integer arm at `ir_codegen_xtensa.inc:1755`:

```pascal
else if op = Ord(tkLt) then
  EmitAsmXtensa(['movi a4, 1','blt a2, a3, .done','movi a4, 0','.done:','mov a2, a4'])
```

`a2` and `a3` hold the two **handles**. So the comparison is a signed 32-bit
compare of two heap pointers, and the answer is allocation order.

`FindProc('PXXStrCmp3')` appears in `ir_codegen386.inc`,
`ir_codegen_aarch64.inc`, `ir_codegen_arm32.inc` and `ir_codegen_riscv32.inc`.
It does **not** appear in `ir_codegen_xtensa.inc`.

## This is the same defect, re-created by omission

`PXXStrCmp3`'s own header records the original:

> *"the four cross backends had NO ordered-string arm at all ... `a < b` fell
> through to the ordinary integer compare and compared the two heap HANDLES ...
> `'zzz' < 'aaa'` reported by allocation order"*

**There are five cross backends.** The sentence names four and the fix covered
those four. The word "four" is the whole finding: it reads as a complete
enumeration, so nobody counted.

## Evidence

Measured at `e7385984b` with the pinned compiler
(`stable_linux_amd64/default/pinned`), no rebuild.

```pascal
program strord;
var a, b: AnsiString;
begin
  a := 'zzz';
  b := 'aaa';
  if a < b then WriteLn('WRONG: zzz < aaa') else WriteLn('ok: zzz >= aaa');
  if b < a then WriteLn('ok: aaa < zzz') else WriteLn('WRONG: aaa >= zzz');
end.
```

| target | result |
| --- | --- |
| x86-64 native | `ok: zzz >= aaa` / `ok: aaa < zzz` |
| riscv32 under `qemu-riscv32` | `ok: zzz >= aaa` / `ok: aaa < zzz` |
| xtensa under `qemu-xtensa`, Call0 | **`WRONG: zzz < aaa` / `WRONG: aaa >= zzz`** |
| xtensa under `qemu-xtensa`, windowed | **`WRONG: zzz < aaa` / `WRONG: aaa >= zzz`** |

## DEMONSTRATED — frankS, 2026-08-29

**Both comparisons print `WRONG:`, on both ABIs.** Not one — both. The order is a
consistent total order, just the inverted one: `'zzz'` happens to take the lower
handle, so handle order comes out exactly opposite to lexicographic order and
both tests fall the wrong way. A different allocation pattern would have given
one right by luck. **That is the signature of ordering by handle**, and it is
this ticket demonstrated rather than inferred.

**Provenance.** Verified on master, not taken on report:

> **master at `dc62fe3cd` or later, `qemu-xtensa` 10.2.1, both ABIs, with
> `--xtensa-soft-mulhigh`.**

`dc62fe3cd` is an ancestor of `origin/master` and carries the `CPU_XTENSA` arm of
`HeapMmap` (`builtinheap.pas:794`) — both checked here rather than accepted from
the report, since the whole reason this section exists is that I once let a fact
about a tree stand in for a fact about a binary.

One caveat survives and belongs with any quotation of the result:
**`--xtensa-soft-mulhigh` means the oracle is not bit-identical to hardware for
multiplies** (no qemu-xtensa core implements MUL32HIGH, and integer formatting
strength-reduces div-by-10 into a 64-bit multiply). It does not touch string
comparison, so it does not weaken this result — but a verdict that omits it
overclaims.

*Superseded:* an earlier revision of this ticket said the repro did not run on
pushed master and rested on an unpushed heap arm. **That is no longer true** —
the arm landed in `dc62fe3cd`. Left visible rather than deleted, because this
ticket has now been wrong twice about provenance in opposite directions and the
pattern is more instructive than either correction.

### Why it could not run before, which is its own finding

`HeapMmap` in `builtinheap.pas` has arms for x86-64, aarch64, arm32, i386,
riscv32, wasm32 and bare-ESP, and **no `CPU_XTENSA` arm**. Hosted xtensa fell
through to the terminal `Result := -1`, so the heap base was `-1` and the first
allocation faulted at `$FFFFFFFF`. **No hosted xtensa program that allocated
anything had ever run.** frankS's numbers, measured under qemu rather than read
off a table, because xtensa diverges from the generic ABI twice: `__NR_mmap2` is
**80** (generic 222 is literally `Unknown syscall 222` there, the same shape as
read=12/write=13 vs 63/64), and `MAP_ANONYMOUS` is **$800**, so flags are `$802`
— not the 34 every other arm passes. The second is the half that fails quietly:
with 34 the kernel sees no ANONYMOUS bit, tries to map fd -1, and returns EBADF,
a negative errno `PXXAlloc` deliberately does not check, which then becomes the
heap base and faults somewhere else entirely.

### A correction to my own correction

The retraction below was **right to make and wrong about why.** I withdrew the
hang because it was measured on a compiler predating frankS's fix — true, and the
`--where` argument for it is sound. But the hang was not caused by the missing
fix: the program **could not have worked on any pin**, because nothing had ever
allocated successfully on hosted xtensa. So the observation I retracted was
correct; only my explanation of it was wrong, and I replaced a wrong explanation
with a different wrong explanation while congratulating myself on the rigour.

The rule that survives is still the right one — *name the binary, not the tree* —
but it is worth recording that **applying it correctly does not make the
resulting story true.** A retraction is a claim too, and mine went unchecked
because it was self-critical, which is the one kind of claim nobody asks you to
prove.

---

**I could not demonstrate the wrong output — and my first attempt to say why was
itself wrong, so it is withdrawn here rather than quietly edited.**

The attempt hung on hello-world (killed at 120s) and bus-errored on the repro,
and this ticket originally reported that as *"hosted xtensa does not currently
run"*. **That measurement is void.** It ran on the pinned compiler **v393 /
`1d69760deabe`, pinned 22:29**, and frankS landed hosted-xtensa read/write
syscalls at **23:21** — `0cff74f62`, wall 3 of the qemu-xtensa oracle, verified
byte-identical to the x86-64 oracle on both ABIs. `pxx --where` confirms the
pinned compiler resolves builtin units from its own frozen
`stable_linux_amd64/default/builtin/`, which differs from the repo's
`compiler/builtin/builtinheap.pas` — so the toolchain I measured could not have
contained that fix under any invocation.

*"Hosted xtensa hangs"* was therefore **a claim about the past stated in the
present tense** — the provenance trap CLAUDE.md's *"hunt async, verify against a
known sha"* exists to prevent. The sha I needed to name was the **compiler's**,
not the tree's; `git merge-base` said the fix was in my checkout and I let that
stand in for the binary. A run on frankS's verified build is requested, and this
ticket will record whatever it prints, `WRONG:` or not.

**One thing survives the retraction.** For most of this bug's life the target
genuinely had no working oracle, which remains the best available explanation for
how a wrong `<` on an entire target went unnoticed while four sibling backends
were fixed. The oracle arrived the same evening the bug was found, from the lane
that owns the file — [[feature-a-hosted-xtensa-so-qemu-xtensa-can-be-an-oracle]].

**Nothing in the finding depends on that run**, which is why it is filed now:

- the guard and the fallthrough above, read directly;
- `PXXStrCmp3` is called by four backends and not by xtensa (grep, comments
  stripped);
- **code size moves the wrong way.** Same program with `=` vs with `<`:

  | target | `=` | `<` | delta |
  | --- | --- | --- | --- |
  | riscv32 | 242244 B | 242248 B | **+4** — both go through the helper |
  | xtensa | 213020 B | 212968 B | **−52** — the ordered form is *cheaper*, because it drops the whole decompose-and-call sequence for five instructions of integer compare |

  A correct ordered compare cannot be 52 bytes smaller than an equality compare.
  That number is the defect.

## Fix

Widen the `ir_codegen_xtensa.inc:1622` guard to the ordered operators and lower
them to `PXXStrCmp3(lenA, srcA, lenB, srcB)` -> -1/0/1, then map the result to
0/1 per operator — the shape `ir_codegen_riscv32.inc` already has, and the
operand decompose right below the guard is already written and reusable.

While there, fix `PXXStrCmp3`'s header comment to say **five**, or better, to
stop counting: *"the cross backends that do not call this helper have no ordered
string compare at all"* is the durable form, because it stays true when a sixth
target lands.

## Owner

**Routed to frankS and accepted** (2026-08-29). It holds
`ir_codegen_xtensa.inc` and the only working hosted-xtensa build; it will widen
the `:1622` guard with a `PXXStrCmp3` lowering on the riscv32 shape and check the
frozen-`tyString` and `Char` operand forms, not only handle-vs-handle.

## Gate

Track A file ownership on `ir_codegen_xtensa.inc`; Track S by subject.
`make compiler/pascal26` (self-host byte-identical — x86-64 is untouched) plus
the `strord.pas` repro above cross-compiled and, when hosted xtensa runs, exercised
under `qemu-xtensa`. Until then the size delta is the check: after the fix, xtensa's
`<` must be **larger** than its `=`, not 52 bytes smaller.

## Note for whoever takes it

Check `>=`/`<=`/`>` too, and check the frozen-`tyString` and `Char` operand
shapes, not just handle-vs-handle — the equality arm handles three operand
shapes and the ordered arm will need the same three.

## Log
- 2026-08-30 — resolved, commit 0b11cb283.
