---
track: A
prio: 45
type: feature
blocked-by: []
summary: "sysutils.ExceptObject did not exist — a bare `except` block (no `on E: T do`) had no way to reach the exception it caught, and the FPC code that uses that shape failed to compile with 'undefined variable (ExceptObject)'. ExceptAddr already existed and the object was already in BSS_EXC_OBJ, so this is the missing half of a pair: one AST node, one lowering arm reusing IR_EXC_STORE's default slot, one RTL wrapper. No backend changed."
---

# `ExceptObject` was missing, though `ExceptAddr` was not

- **Type:** feature (missing RTL entry point + its intrinsic) — Track A
  (`defs.inc`, `pasparser_expr.inc`, `ir.inc`; wrapper in `lib/rtl/sysutils.pas`).
- **Status:** done
- **Opened:** 2026-08-21, from the exception-semantics differential that also
  produced `bug-a-unhandled-exception-exits-1-not-217`.
- **Closed:** 2026-08-21.

## Symptom

```pascal
try
  raise EConvertError.Create('m');
except
  WriteLn('cls:' + ExceptObject.ClassName);
end;
```

```
pascal26:64: error: undefined variable (ExceptObject)
  near: except W  cls:  ExceptObject >>>  ClassName
```

FPC compiles and runs it. The shape matters more than it looks: a **bare
`except`** — no `on E: T do` binding — is how FPC code that predates the `on`
syntax reads its exception, and `ExceptObject` is the only door into it. The
same call is how a routine *called from* a handler sees what is in flight
without the handler threading it through a parameter.

## Why the gap existed

`ExceptAddr` was implemented (`bug-pascal-exceptaddr-returns-nil`) by adding an
`__pxxExceptAddr` intrinsic over `BSS_EXC_ADDR`. Its sibling slot,
`BSS_EXC_OBJ`, was already being written by every raise stub on every backend
and already being read by `IR_EXC_STORE` — that read is exactly what binds `E`
in `on E: T do`. So the value was present, the load was present, and only the
*name* was missing. This is the double-case shape
`normalise-dont-special-case.md` warns about: one of two arms got built, and
the unbuilt one is the one that stayed broken.

## Fix

Four small pieces, no new IR op and no backend change:

1. `AN_EXCEPTOBJ = 99` (`defs.inc`) — the twin of `AN_EXCEPTADDR = 89`.
2. `__pxxExceptObject` in `pasparser_expr.inc`, written as a copy of the
   `__pxxExceptAddr` arm beside it: reserved prefix, optional parens,
   `EnableExceptionRuntime` so a unit may read the slot without ever raising.
3. Lowering in `ir.inc`: `IR_EXC_STORE` with the slot selector left at its
   **default**, because `IRExcStoreSlot`'s `IRC = 0` case is already
   `BSS_EXC_OBJ`. The arm is three lines and costs the six backends nothing —
   the same property that let the signal intrinsics land free.
4. `function ExceptObject: TObject` in `sysutils.pas`, one line over the
   intrinsic.

The intrinsic stays **untyped** (`tyPointer`) and the cast to `TObject` happens
in the RTL wrapper. That is deliberate: it keeps the parser from needing to
know a class it otherwise has no reason to know, and it is the same division
`ExceptAddr`/`__pxxExceptAddr` already uses.

Also corrected a stale comment above `ExceptAddr`'s declaration, which still
described it as a nil stub with the honest fix "filed" — it had already landed.

## Verification

`test/test_exceptobject_intrinsic.pas`, wired into `test-core`, and
**byte-identical to fpc 3.2.2** across six shapes:

| row | shape |
| --- | --- |
| `idle: nil` | no exception in flight → nil |
| `bare:` | bare `except`, no binding |
| `bound:` + `same: True` | inside `on e: Exception do`, `ExceptObject = e` |
| `report:` | read from a routine the handler CALLS |
| `in:` / `out:` | nested, where the inner handler raises a new exception |

Gate: `make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN.

## Not done

`AcquireExceptionObject` / `ReleaseExceptionObject` are still absent. They are a
different question — they hand *ownership* of the object out of the handler,
which is about the raise machinery's lifetime rules rather than about naming a
slot that already exists. Nothing in the corpus has asked for them yet; file
when something does.
