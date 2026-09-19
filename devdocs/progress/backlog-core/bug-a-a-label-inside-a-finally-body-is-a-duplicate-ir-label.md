---
slug: bug-a-a-label-inside-a-finally-body-is-a-duplicate-ir-label
title: a label inside a finally body is a duplicate IR label
summary: >
  A `finally` body is lowered MORE THAN ONCE -- the normal path, the
  exception path, and once more per early exit (IRLowerCleanupToDepth) -- and
  a `label:` inside it is placed each time under the SAME IR label id, so the
  compile stops with "duplicate IR label definition". Any goto-and-label pair
  inside one finally body refuses, legal as it is: FPC compiles it and runs it
  correctly. The same re-lowering would duplicate any other construct that
  mints a per-body id from a table keyed by the SOURCE label rather than by the
  lowering pass.
track: A
type: bug
prio: 20
owner:
status: open
---

## Reproduce

```pascal
function F: Integer;
label l;
begin
  Result := 0;
  try
    Result := 1;
  finally
    goto l;
    Result := -1;
    l:
    Result := Result + 3;
  end;
end;
```

`pascal26:<line of l:>: error: duplicate IR label definition`, identically on
pin v412 and at HEAD. FPC prints 4.

## Where

`ir.inc`, the try/finally arm: `IRLowerAST(ASTRight[node])` twice (fall-through
and handler), and `IRLowerCleanupToDepth` lowers the same body again for every
`exit`/`break`/`continue` that crosses it. AN_LABEL resolves the name to
`GotoLabelIRId[slot]`, allocated once per body, so each copy places the same id.

The fix is to give each lowering of the body its own ids for the labels that
live INSIDE it (and only those -- a goto out of the body to an outer label must
keep the outer id, though that goto is now refused anyway). Found while writing
`test/test_goto_within_exception_region.pas`, which leaves this case out and says so.
