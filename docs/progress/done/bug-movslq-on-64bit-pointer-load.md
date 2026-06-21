# Bug — movslq instruction generated for 64-bit pointer/array field load

- **Type:** bug
- **Status:** done
- **Owner:** —
- **Opened:** 2026-06-21

## Description

On x86_64 targets, loading the pointer value of a dynamic array or managed type that is nested inside a record or class field incorrectly generates a `movslq` instruction (Move Doubleword to Quadword with Sign-Extension) instead of a standard 64-bit `mov` instruction. 

This truncates the 64-bit pointer address to 32 bits, and sign-extends the result. Any subsequent reference count modification (such as `incq -0x10(%rax)`) or dereference results in a Segmentation Fault (Exit Code 139) since the upper 32 bits of the pointer address are corrupted.

## Steps to Reproduce

Consider a class accessing a dynamic array field:
```pascal
program test_bug;
type
  TMyRecord = record
    arr: array of Integer;
  end;
  TMyClazz = class
    rec: TMyRecord;
    procedure Test;
  end;

procedure TMyClazz.Test;
var temp: array of Integer;
begin
  // Accessing or assigning the dynamic array field:
  temp := rec.arr;
end;
```

Disassembly of the field load:
```assembly
mov    -0x8(%rbp),%rax   ; rax = Self
add    $0x8,%rax         ; rax = @Self.rec.arr
movslq (%rax),%rax       ; ERROR: Truncates and sign-extends 64-bit pointer!
test   %rax,%rax
je     0x422386
incq   -0x10(%rax)       ; Segfaults due to corrupted address in %rax
```

## Expected Behavior

The compiler should emit a 64-bit instruction (e.g. `mov (%rax), %rax` or `movq`) to load pointer addresses on 64-bit platforms, rather than truncating them with `movslq`.

## Resolution

- 2026-06-21 - DONE (37e22ad). Root cause was target-independent, in the shared
  IR (not the x86-64 emitter). Reading a dynamic-array value from a record/class
  field lowered `IR_LOAD_MEM` with the field node's `ASTTk`, which tags a
  dyn-array with its ELEMENT type (e.g. Integer). On 64-bit targets that became a
  4-byte sign-extending load (x86-64 `movslq`, aarch64 `ldrsw`) and truncated the
  64-bit heap handle. Fix: in the `AN_FIELD`/`AN_INDEX`/`AN_DEREF` value-load
  lowering, force a pointer-width load when the node is a dynamic array
  (`NodeDynDepth > 0`). i386/arm32 were unaffected (4-byte pointers) but the fix
  is uniform. Verified `len=3` (was SIGSEGV) on x86-64/i386/aarch64/arm32;
  self-host byte-identical; `make test` green.
