# Inline assembly

PXX has a rudimentary inline assembler. Two forms, both usable in user code.

## Raw bytes (`db`) — all targets

`asm … end` with `db` emits literal machine-code bytes. This works on every
target (you supply the encoding):

```pascal
begin
  asm
    db $b8, $3c, $00, $00, $00   { mov eax, 60  (sys_exit) }
    db $bf, $2a, $00, $00, $00   { mov edi, 42  (exit code) }
    db $0f, $05                  { syscall }
  end;
end.
```

## Mnemonics (x86-64)

x86-64 supports a small set of Intel-syntax mnemonics that read/write named
locals and parameters directly. A statement-level block may list clobbered
registers after `end`:

```pascal
procedure DoSwap;
var n, m: LongInt;
begin
  n := 42; m := -7;
  asm
    mov eax, n
    xchg eax, m
    mov n, eax
  end ['eax'];        { clobber list parsed }
end;
```

## `assembler` functions

A whole-function asm body: parameters are already spilled to their stack slots
and readable by name; leave the result in the accumulator (`eax`/`rax`):

```pascal
function AddMul(a, b: LongInt): LongInt; assembler;
{$asmMode intel}
asm
  mov eax, a
  add eax, b
  add eax, eax        { (a+b)*2 }
end;
```

A routine cannot be both `assembler` and `generator`.

## Scope

This is intentionally minimal — enough for syscalls, swaps, and small intrinsics,
not a full assembler. The per-target text-assembler encoders and the depth
roadmap live in [`developer/inline-asm.md`](../developer/inline-asm.md).
