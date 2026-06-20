# Stack frame corruption on inline string concatenation assignments

- **Type:** bug
- **Status:** backlog
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
