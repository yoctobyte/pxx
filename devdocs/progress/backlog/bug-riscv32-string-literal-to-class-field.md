---
prio: 55
---

# riscv32: storing a string LITERAL into a class field gives an empty string

- **Type:** bug (cross-target codegen — riscv32 only)
- **Track:** A — core (riscv32 backend / frozen-string store)
- **Status:** backlog — opened 2026-07-13.
- **Found by:** splitting the reproduction for [[bug-cross-metaclass-new-with-args]] — this
  is NOT a metaclass bug, it just happened to be in the same test.

## Reproduction
```pascal
type
  TA = class
    F: string;
    procedure SetLit;
  end;
procedure TA.SetLit;
begin
  F := 'lit';                  { -> '' on riscv32 }
end;
...
  a.F := 'direct';             { -> '' on riscv32 }
```

Measured 2026-07-13 (same program, all targets):

| form | x86-64 | i386 | aarch64 | arm32 | riscv32 |
| --- | --- | --- | --- | --- | --- |
| `F := 'lit'` (literal, in a method) | ok | ok | ok | ok | **''** |
| `a.F := 'direct'` (literal, qualified) | ok | ok | ok | ok | **''** |
| `F := 'cat:' + n` (concatenation) | ok | ok | ok | ok | ok |
| `s := 'viavar'; a.F := s` (via a variable) | ok | ok | ok | ok | ok |

So it is specifically a **frozen string LITERAL stored straight into a class FIELD**. Route
the same literal through a local variable, or produce it with a concatenation (a managed
result), and it stores fine. It is silent — no crash, no diagnostic, just an empty string —
which is the worst shape for a bug and means anything riscv32 that initialises a field from a
literal has been quietly wrong.

## Where to look
The literal is a frozen string (inline storage, 8-byte length prefix, chars at +8) and the
field is a managed slot; the store must materialise a handle. Compare the riscv32 emit for
`IR_STORE_MEM` / the frozen-literal-to-managed-slot path against i386, which is the closest
target (ILP32, and it works). The concatenation case working says the managed-handle store
itself is fine — it is the FROZEN LITERAL source operand that is being dropped.

## Gate
`make test` + self-host byte-identical + cross (riscv32 in particular).
