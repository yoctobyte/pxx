# Stack frame corruption on inline string concatenation assignments

- **Type:** bug
- **Status:** DONE 2026-06-20
- **Owner:** —
- **Opened:** 2026-06-20
- **Relation:** surfaced in test_pcl_widgets.pas when assigning inline string concatenations directly to properties or passing to methods.

## Problem

Inline string concatenations passed directly to methods or assigned to properties (e.g. `Memo.Text := 'Line 1' + #10 + 'Line 2'`) can corrupt the stack layout in the compiled binary, leading to incorrect values being popped from the stack (such as popping string metadata lengths into parameter registers like `rdi` or `rsi`), resulting in segmentation faults or incorrect function calls.

## Reproduction

```pascal
var
  Memo: TMemo;
begin
  Memo := TMemo.Create;
  Memo.Text := 'Line 1' + #10 + 'Line 2'; // stack layout corruption during setter call
end.
```

## Root cause

When string concatenation occurs inline inside a call argument list or property setter assignment, the compiler generates temporary string values on the stack but fails to correctly manage the stack pointer offsets before making the function or method call. This causes caller and callee register/stack mismatches when parameters are popped.

## Workaround

Assign the concatenated string to a local variable `s` first, and then assign that variable to the property or pass it to the method.

```pascal
var
  s: string;
begin
  s := 'Line 1' + #10 + 'Line 2';
  Memo.Text := s; // Safe, no stack corruption
end;
```

## Fix direction

Correct the stack management and temporary cleanup logic in `compiler/ir_codegen.inc` when compiling inline binary operations (like string concatenation) that serve as arguments or property setters.

## Log
- 2026-06-20 — opened. Discovered during PCL widgets test and worked around.

## Root-cause analysis 2026-06-20 (precise; fix still open)

Confirmed and narrowed on x86-64:
- Triggers ONLY for **frozen `tyString`** concat passed to a **multi-argument**
  call. A method call (implicit Self + the string) is the common case; a plain
  single-arg `Foo('a'+'b')` happens to survive. Managed AnsiString concat goes
  through the heap (PXXStrConcat handle), so it is unaffected.
- The frozen-string concat codegen (ir_codegen.inc ~2144) does
  `sub rsp, 272`, builds the result in that stack buffer, and returns the pointer
  as **rsp itself without restoring rsp** (`mov rax, r11` where r11=rsp). So the
  concat leaves a 272-byte hole at the top of the stack.
- The internal-call arg marshalling (ir_codegen.inc ~2700) is push-all-args /
  pop-into-registers. With the concat arg's 272-byte hole sitting between two
  argument pushes, `pop rdi/rsi/...` pull buffer bytes instead of the real
  arguments — e.g. Self ends up = the concat length. Symptom: `Length(s)` inside
  the callee reads a code/garbage value (e.g. 4223757), and writeln dumps far
  past the string.
- The proc epilogue uses `leave` (rsp from rbp, symtab.inc ~3833), so the leaked
  rsp itself is harmless; the corruption is purely the inter-push hole.

Attempted fix (reverted): auto-spill a `tyString`-concat call arg to a hidden
local (the automatic `s:=a+b; f(s)`) in IRLowerCallArg. It compiles + self-hosts
byte-identical but the produced programs still crash (return address -> 0), even
for a single-arg call inside a proc, for a reason not yet isolated (the manual
`s:=a+b; f(s)` works, so it is something about the IR-lowering-time temp /
emission order, not the frame slot per se). Needs a gdb-step of the emitted
sequence. STORE_SYM tyString (ir_codegen.inc ~1597) also does not restore rsp.

Fix directions (pick one):
1. Make frozen-string concat write into a caller-provided destination (the spill
   temp) and restore rsp — eliminates the stack buffer entirely as an rvalue.
2. In the internal-call arg loop, copy a concat (rsp-dirtying) arg result to a
   stable slot before pushing the next arg.
Either way the multi-arg hole must go.

## DONE 2026-06-20

Fixed in IRLowerCallArg (ir.inc): a frozen-`tyString` concatenation argument is
spilled to a hidden local and passed by ADDRESS (IR_LEA), not value. The extra
twist beyond the spill: a frozen-string LOCAL loaded via IR_LOAD_SYM yields the
inline length word (TypeSize(tyString)=8), so the argument must be the slot
address — IR_LEA — like any frozen-string argument. Eliminates the stack hole.
Validated: method + plain calls, single/multi concat, embedded #10. Reseed
(make bootstrap), make test green. test/test_inline_concat_arg.pas added.
