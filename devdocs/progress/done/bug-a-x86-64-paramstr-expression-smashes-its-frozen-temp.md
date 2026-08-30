---
slug: bug-a-x86-64-paramstr-expression-smashes-its-frozen-temp
track: A
prio: 70
status: done
---

# `ParamStr(i)` as an EXPRESSION smashes the stack when the argument is longer than 256 bytes (x86-64)

Found from the wasm lane while building the argv oracle: the NATIVE build is
what diverged, not the new backend.

## Repro

```pascal
program b2;
var i: Integer;
begin
  WriteLn('count=', ParamCount);
  for i := 1 to ParamCount do
    WriteLn('expr[', i, ']=[', ParamStr(i), ']');
  WriteLn('done');
end.
```

```
$ long=$(printf 'x%.0s' $(seq 1 300))
$ ./b2 alpha "$long"
count=2
expr[1]=[alpha]
expr[2]=[xxxx...300 of them...]
expr[3]=[]
expr[4]=[]
...            <- runs forever; 1.1M lines before it was killed
```

`ParamCount` is 2 and the loop prints `expr[3]`, `expr[4]`, … — the counter and
its bound are no longer what the program set them to.

Threshold, measured by bisection: **258 bytes is fine, 260 is not.**

## Cause — measured, not inferred

`ParamStr(i)` in expression position desugars to `ArgStr(i, <hidden temp>)`
with a **frozen** temp, `AllocVar('', tyString)`
(`compiler/pasparser_expr.inc:1846`, and the same in `pyparser.inc:43029`). A
frozen local is `LOCAL_STR_CAP + 8` = **264 bytes** (`defs.inc:56`).

The x86-64 fill is `EmitArgvToString` (`compiler/symtab.inc:6048`), and its
copy is **unbounded**:

```
  EmitB($80); EmitB($3C); EmitB($0E); EmitB($00);   { cmp byte [rsi+rcx], 0 }
  EmitB($74); EmitB($05);                           { je +5 }
  EmitB($48); EmitB($FF); EmitB($C1);               { inc rcx }
  EmitB($EB); EmitB($F5);                           { jmp -11 }
  EmitB($48); EmitB($89); EmitB($C8);               { mov rax, rcx }
  EmitStoreStrLen(dstIdx);
  EmitLeaStrDataRdi(dstIdx);
  EmitB($F3); EmitB($A4);                           { rep movsb }
```

`rcx` is the full `strlen(argv[i])` with no clamp, so `rep movsb` writes
`8 + strlen` bytes into a 264-byte slot. Anything past that is the adjacent
frame slot — in the repro, the loop's own control state. It also writes a
length word larger than the capacity, so `Length()` reports 300 for a buffer
that holds 256.

The index bounds check right above it is correct and unsigned; it is only the
LENGTH that is unchecked.

## Scope

- **x86-64 only.** `EmitArgvToString` emits x86-64 bytes directly.
  riscv32 routes the same construct through `PXXCStrToFrozen`
  (`ir_codegen_riscv32.inc:2553`), which clamps at 255 (`builtinheap.pas`), so
  it truncates instead of overflowing. aarch64 / arm32 / i386 / xtensa show no
  call to either and want checking as part of this ticket.
- **The MANAGED destination is fine.** `ArgStr(i, s)` with `s: string` goes
  through `EmitArgvToStringManaged`, which sizes the allocation from the
  length. Verified: 300-char argument, correct output, no corruption.
- **Not just a synthetic input.** Any argument over 256 bytes does it, and a
  long absolute path or a quoted list of flags reaches that in ordinary use.

## Suggested fix

Clamp `rcx` to `LOCAL_STR_CAP` before the `rep movsb`, the way
`PXXCStrToFrozen` clamps at 255 — the destination's capacity is known at emit
time from `dstIdx`, so this is a `cmp`/`cmova` in `EmitArgvToString`, not a
signature change. Truncating matches what riscv32 already does; silently
overwriting the neighbouring slot matches nothing.

Worth deciding at the same time whether the two paths should share one
routine, since they currently disagree about the clamp AND about the limit
(256 vs 255) — `normalise-dont-special-case`.

## Test

`test/wasm/check_argv.sh` covers the same three shapes on wasm32 and passes;
it deliberately keeps its diffed slice under the threshold and carries a
comment pointing here, so restoring the long argument to that slice is the
regression test once this is fixed.

---

## Resolved — frankA, 2026-08-30

**Reproduced at HEAD first**: 300-byte argument, 1,290,845 lines before the
timeout killed it, `ParamCount` = 2 while the loop printed `expr[3]`, `expr[4]`,
… The control with short arguments was clean, so the ingredient really is the
length.

### Fix

Clamp `rcx` in `EmitArgvToString` before `mov rax, rcx`, so **one** clamp fixes
both the stored LENGTH and the `rep movsb` COUNT and they cannot disagree —
`cmp rcx, cap` / `jbe` / `mov rcx, cap`. Truncating is the established contract
for a frozen slot (`abi.inc`: *"capped at LOCAL_STR_CAP, the ShortString norm"*),
not something invented here.

### The 255-vs-256 question the ticket left open is answered by MEASUREMENT

The ticket asked whether the two paths should agree, since `PXXCStrToFrozen`
stops at `len < 255` while the slot holds `LOCAL_STR_CAP` = 256. I clamped at
**255**, and the deciding evidence is not the slot size — it is FPC:

```
                   pxx (fixed)   FPC 3.2.2
  Length(ParamStr(1))    255         255
  s := ParamStr(1)       255         255
  ArgStr(i, s)           300          --
```

**FPC answers 255 for this exact program**, because `ParamStr` returns a
ShortString. So 255 buys FPC parity *and* cross-target agreement with what
riscv32/xtensa already produced, in one choice. Clamping at `LOCAL_STR_CAP` would
have made a 256-byte argv entry render differently from FPC *and* differently per
target — a divergence a differential run would later file as its own bug. The
one wasted byte is the correct trade and is now named `FROZEN_CSTR_CAP` in
`defs.inc` with that reasoning attached, rather than being an unexplained literal
in two places.

Measured across the threshold the ticket bisected (258 ok / 260 not): arguments of
100/255/256/258/260/300/1000 bytes all exit 0 with the expected 4 lines, storing
100 and then 255 for everything above. **The 258/260 boundary is gone rather than
moved** — there is no length that corrupts.

### The managed path is deliberately NOT clamped

`ArgStr(i, s)` with a real `string` destination still answers **300**. That path
goes through `EmitArgvToStringManaged`, which sizes the allocation from the
length, and it is the full-length escape hatch for callers who need one. The test
asserts that row explicitly: if it ever reads 255, the clamp has leaked into the
path that must not have one.

### Test

`test/test_paramstr_long_arg.pas`, wired into the existing ParamCount/ParamStr
block. The **loop is part of the assertion** — its counter and bound are what the
overflow smashed, so reaching `done` at all is the regression check — and the
recipe checks `rc` **separately** from the output under a `timeout`, because the
failure is a runaway rather than a wrong string. Run against `pinned` before
committing: **2,910,710 lines, rc=124**, and `expr[2]len=300`, the over-capacity
length word. Green after.

`tools/gate.sh quick` GREEN.

### Found and fixed on the way, unrelated and committed separately

`gate.sh quick` step 2 was RED on master for **every** lane — `lexer.inc` calls
`CModuleOfTok`, whose body is in `dbg_filetable.inc`, included later; the FPC seed
could not build. Not mine (it reproduced with my changes stashed), arrived with
`5c8de9442`. pxx accepts the order, so the self-host fixedpoint stays green and
nothing in the per-fix loop notices — only the seed build, which is how the
compiler bootstraps. Forward added beside its five siblings.

### Still open, and NOT closed by this

- **aarch64 / arm32 / i386 / xtensa** were listed as "want checking as part of
  this ticket". I have not checked them: this box builds them but does not run
  them, and a cross-target claim from a compile alone is exactly the kind of
  unverified limit that ages badly. Filed as
  `bug-a-argv-to-frozen-string-is-unchecked-on-four-untested-targets`.
- The two fills (`EmitArgvToString`, `PXXCStrToFrozen`) still **duplicate** the
  clamp rather than sharing it; they now agree on the number, which removes the
  observable divergence, but a third target added tomorrow gets a third copy.
  Noted in that ticket rather than pretended away.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
