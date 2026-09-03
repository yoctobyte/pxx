---
type: bug
track: A
prio: 80
status: done
summary: Under -dPXX_SHORTSTRING on i386, passing a string[N] to a managed
  string parameter reads its length at the wrong width and segfaults — Copy/Pos
  are two callers of that, not the subject. FIXED.
---

# i386: Copy and Pos segfault under the byte-prefix mode

**Blocks the phase-4 flip on i386.**

```pascal
var s: string[10];
begin s := 'abcdef'; WriteLn('[', Copy(s,2,3), '] ', Pos('cd', s)); end.
```

| target | default | `-dPXX_SHORTSTRING` |
| --- | --- | --- |
| **i386** | `[bcd] 3` | **SIGSEGV** |
| x86-64 / arm32 / aarch64 / riscv32 | `[bcd] 3` | `[bcd] 3` |

Distinct from
`bug-a-string-concat-segfaults-on-x86-64-under-the-byte-prefix-mode`, which is
x86-64 ONLY and leaves `Copy`/`Pos` working there. **The two crashes are on
disjoint targets**, so they are unlikely to be one cause and each needs its own
repro.

Found by a 20-probe both-modes suite across five targets. **x86-64 shows this
row clean** — the native-only blind spot again.


## Not a Copy/Pos bug — the call-argument conversion (2026-09-03)

`Copy` and `Pos` are parsed into ordinary calls to the `__pxxCopy` / `__pxxPos`
helpers, whose parameters are `AnsiString`. Reduced to the shape underneath
both, which has nothing to do with either intrinsic:

```pascal
procedure Show(const a: AnsiString);
begin WriteLn('<', a, '>'); end;
var s: string[10];
begin s := 'abcdef'; Show(s); end.
```

i386 under `-dPXX_SHORTSTRING`: SIGSEGV. Default mode and all four other
targets: `<abcdef>`.

## Cause

`compiler/ir_codegen386.inc`, the frozen-to-managed argument conversion:

```pascal
EmitLoadStrLen386(1, 0, IRStrTkOf(argNode));   { ecx = len }
EmitLeaStrData386(0, IRStrTkOf(argNode));      { eax = chars }
```

`argNode` is the **IR_ARG** node. `IRFrozenKindOfAddr`'s own header says a
frozen string's arg node is tagged tyString generically, so asking it walks back
to nothing and returns the 8-byte default — every time, unconditionally. The
node that can answer is the one `IREmitNode386` just evaluated into eax,
`IRA[argNode]`. Reading a one-byte prefix as eight handed `PXXStrFromLit` a
length in the billions.

**It could not fail in the default mode**: there the right answer and the wrong
answer are both tyString. The expected value collides with the failure value —
CLAUDE.md's "choose a probe whose right answer differs from the default" — which
is also why x86-64's suite showed nothing.

Fixed to `IRStrTkOf(IRA[argNode])`. xtensa already spelled it that way.

## The sibling: riscv32 did not (same commit)

`compiler/ir_codegen_riscv32.inc` had the identical misuse on the external-C
argument path — `EmitLeaStrDataRISCV32(reg_a0, reg_a0, IRStrTkOf(argNode))` —
so a `string[N]` handed to an `external` routine got a char pointer seven bytes
past its first character. xtensa's twin two lines away was already correct.

**Measured, not assumed.** `puts(s)` does NOT reach that arm — a canary forcing
the prefix to 1 unconditionally left the object byte-identical, so the first
three repro shapes I tried were proving nothing. The arm needs the CALLEE's
parameter to be frozen too:

```pascal
type TS = string[10];
function cf(s: TS): Integer; cdecl; external 'cf';
```

`--emit-obj --target=riscv32`, control compiler (fix reverted, rebuilt,
`converged after 1 round`) against fixed:

| mode | control vs fixed | why |
| --- | --- | --- |
| `-dPXX_SHORTSTRING` | **DIFFER — exactly one byte**, `0x85` -> `0x15` | the `addi a0,a0,imm` prefix immediate, 8 -> 1 |
| default | IDENTICAL | both resolve tyString; the fix is a no-op there, as it must be |

## Verified (the i386 half)

Five targets, both modes, values asserted against a `.expected` file read
through `cat -v`, compile rc branched on with `&&`: `Copy` into a variable,
`Copy` inline in a `WriteLn`, `Pos` into a variable, `Pos` on a record field,
`Pos` on an array-of-record field, and a plain user procedure taking
`const AnsiString`. i386 PASSes all rows in both modes; it segfaulted on every
`ss` row before.

## Regression test

`test/test_frozen_arg_and_field_write.pas` carries the `Show(s)` /
`Copy` / `Pos` rows alongside the field-write rows of the sibling ticket — one
file, because the two defects share a program and a `.expected`. Wired native +
four cross batteries, both modes; expectations live in the `.expected` file and
are `cat`-ed by every row, so there is ONE copy of the values rather than ten
that go stale serially.

## Log
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 21544412b.
