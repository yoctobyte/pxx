---
slug: bug-a-irtoplevelstmt-parameter-is-a-node-index-named-k
title: "IRTopLevelStmt(k) takes a NODE INDEX, not a kind — and passing a kind compiles fine"
track: A
prio: 20
type: bug
blocked-by: []
status: open
owner: ""
created: 2026-08-28
summary: "ir_codegen.inc:8813 declares IRTopLevelStmt(k: Integer) and its body is `case IRKind[k] of`, so the parameter is a node index. The name reads as a kind, and passing IRKind[i] compiles cleanly and indexes the IR array with an opcode number — a silently-wrong-value trap with no diagnostic, in a function every backend author will call. Rename plus a one-line comment closes the class."
---

# The trap

```pascal
function IRTopLevelStmt(k: Integer): Boolean;
begin
  IRTopLevelStmt := False;
  case IRKind[k] of        { <-- k is a NODE INDEX }
```

The natural reading of `k` in this codebase is a *kind* — the surrounding code
says `case IRKind[i] of` everywhere, and IR opcode constants are the things
usually being switched on. So `IRTopLevelStmt(IRKind[i])` is the obvious call,
it compiles without a warning, and it indexes `IRKind` with an opcode number.
Both are `Integer`, so nothing catches it.

The result is not a crash. It silently answers a question about whichever node
happens to sit at index `IR_STORE_SYM` (21), so statements get treated as values
and values as statements, in a pattern that varies per body. That is the
plausible-wrong-answer shape `devdocs/dev/debugging-playbook.md` is built around.

# Why the existing backends don't hit it

They don't call it. x86-64, i386, arm32, aarch64, riscv32 and xtensa each
hard-code an **explicit list** of value kinds their top-level loop skips
(`IR_NOP, IR_CONST_STR, IR_CONST_INT, IR_BLOCK, IR_LOAD_SYM, ...`,
e.g. `ir_codegen_riscv32.inc:3858`). Using the shared predicate instead is the
`normalise-dont-special-case` move and is what a new backend will reach for —
so the trap is in front of the *next* backend author, not behind the existing
ones.

# Found

By the wasm32 backend, 2026-08-28, in an audit done *before* the code had ever
run (`36f8753c7` → fixed in the commit that followed). Reading the riscv32 arms
to check three unverified assumptions turned this up as a fourth thing nobody
was looking for. It would otherwise have shipped as arbitrary IR ops being
skipped or spuriously refused, with no diagnostic pointing anywhere near the
cause.

# Fix

Rename the parameter to `node` (or `n`, matching `IRNodeOwnsManagedStr(n)`) and
add a one-line comment saying it is a node index. Low prio because there is
exactly one caller today; the value is that the next backend author cannot make
the mistake.
