---
track: A
prio: 25
type: chore
summary: "`ParseLValue` and `CompileLValueAddress` in pasparser_lval.inc have no callers anywhere in compiler/** — ~130 lines of pre-AST statement-assignment parsing, including direct machine-code emission, that nothing reaches."
---

# Delete the dead Pascal lvalue-statement path

- **Type:** chore (Track A — `compiler/pasparser_lval.inc`, `pasparser_name.inc`)
- **Status:** backlog — opened 2026-08-24, found while converting the
  name-resolution diagnostics in
  [[feature-a-error-does-not-halt-so-a-parse-can-be-speculative]]
- **Owner:** —

## What

```
$ grep -rn 'ParseLValue\b' compiler/ | grep -v ParseLValueAST
compiler/pasparser_name.inc:456:procedure ParseLValue(const name: AnsiString); forward;
compiler/pasparser_lval.inc:3318:procedure ParseLValue(const name: AnsiString);
```

A forward declaration and a body. No call sites. `CompileLValueAddress` (and
therefore `CompileLValueAddressInternal`) is reached only from inside
`ParseLValue`, so the whole chain is unreachable. Statements go through
`ParseLValueAST` and the AST/IR path instead.

The body still contains **direct machine-code emission** (`EmitB($48)` /
`EmitB($05)` to add a field offset into rax) from before the AST existed — which
is the strongest evidence it is a leftover rather than a path someone re-enables.

## Why it is worth a ticket rather than a quiet delete

Two of its `undefined variable` sites were converted to the recoverable error
path in the ticket above before the code was noticed to be dead. Work applied to
dead code is the cost this ticket removes — the next person reads three call
sites of a diagnostic where only one runs, and reasons about behaviour that
cannot happen.

## How

Delete `ParseLValue`, `CompileLValueAddress`, `CompileLValueAddressInternal` (if
it too has no other caller — check) and the two forwards. Nothing else should
move in the same change.

**The gate IS the proof**: `make compiler/pascal26` (the self-host fixedpoint
compiles the whole compiler) plus `tools/gate.sh quick`. If anything reached it,
the build cannot resolve it and fails loudly — there is no silent way to be
wrong about this one.
