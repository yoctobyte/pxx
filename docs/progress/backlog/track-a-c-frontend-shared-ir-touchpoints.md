# C frontend — shared-IR touch points that belong to Track A

- **Type:** coordination / heads-up
- **Track:** A (compiler core / shared IR) — raised by Track D (C frontend,
  worktree `feat/cfront`).
- **Opened:** 2026-06-25
- **Why:** the C body frontend lowers to the SAME shared AST/IR as the Pascal
  frontend. Where building it required touching shared lowering (not just
  `clexer/cparser`), Track A should own/review the semantics so a future Pascal
  refactor doesn't silently regress C, and vice-versa.

## 1. Value-bearing top-level `AN_EXIT` now routes through the Halt terminate path

`ir.inc` (AN_EXIT lowering): a `return <expr>` from a top-level C `main` arrives
as an `AN_EXIT` with `ASTLeft <> -1` while `CurProc < 0`. Pascal's program-level
`Exit` never carries a value, so the original lowering discarded it and codegen
emitted `EmitExit(0)`. Added branch: when `CurProc < 0` and the node has a value,
terminate with that value (the `AN_HALT` path) so the C process exit code is the
returned int.

- Guarded by `CurProc < 0` **and** a present value → never fires for Pascal →
  self-host stays byte-identical (verified).
- Landed in commit `202ae37` (Track D, branch `feat/cfront`).
- **Ask of Track A:** confirm this is acceptable shared-IR behavior, or tell us
  to move it behind a C-frontend-only hook. Slice D later made `main` a real
  proc (return via RetSymIdx + entry `exit_group(eax)`), so this branch is now
  only a fallback for the inline-main model — it can likely be retired once the
  C frontend fully commits to the proc-based entry; flagging so A decides.

## 2. Conditional expression `?:` — possible missing AST node

C's ternary `a ? b : c` is an *expression* that yields a value; pxx has no
conditional-expression AST node (Pascal has no ternary). Track D can desugar it
in the C frontend via a hidden temp + `AN_IF` statement, but a first-class
`AN_TERNARY` (or a generic conditional-expression lowering) would be cleaner and
reusable. **Ask of Track A:** do you want to own a shared conditional-expression
node, or should Track D desugar locally? Currently deferred (no `?:` in the
fixtures yet); not blocking, but lua/sqlite use it heavily.

## 3. Already-tracked shared bug the C path also hits

`bug-esp-not-always-boolean` — `not <non-boolean-typed expr>` (e.g. a function
call returning Int64) is typed boolean, so `~0` in C const-eval yields 1 not -1.
Root cause is the shared front-end `not`-typing, owned by Track A. Track D filed
`bug-c-const-eval-bitwise-not` with a C-local XOR-with-(-1) workaround option;
the general fix stays with A.

## Log
- 2026-06-25 — opened by Track D after slices A–D. Going forward, Track D files
  a Track A ticket whenever the C frontend needs a shared-IR/AST change (e.g. a
  new node) rather than absorbing it into the C-only path.

## RESOLVED 2026-06-26 — value-bearing nodes reconciled (read this before adding an AST node)

What went wrong: BOTH tracks implemented the value-bearing nodes in parallel
(Track C on `feat/cfront`, Track A on master) with **different node numbers and
different node shapes**. Merging stacked two definitions → duplicate identifiers +
mismatched lowering. Avoidable: the rule below already existed; it was crossed.

Canonical (master, after merge `556ad7dd`) — these are DONE, do not re-add:

| node               | num | shape |
|--------------------|-----|-------|
| AN_TERNARY         | 67  | Left=cond, Right=AN_PAIR(then,else), ASTTk=result |
| AN_COMMA           | 68  | Left=side-effect (discarded), Right=value |
| AN_INCDEC          | 69  | Left=lvalue, ASTIVal=+1/-1 (lowering scales by stride), ASTSOffset=1 postfix/0 prefix |
| AN_COMPOUND_ASSIGN | 70  | Left=lvalue, Right=rhs, ASTIVal=binop token or Ord(tkAssign) |
| AN_SWITCH          | 71  | Left=selector, Right=AN_BLOCK; markers reuse AN_CASE=17 / AN_DEFAULT=48 |

**Next free AN_ number = 72.** Highest in use = AN_SWITCH=71.

Rules to avoid a repeat (reinforced):
1. C never invents a shared AST node number unilaterally. Need one → file a Track A
   ticket (as section 2 did for AN_TERNARY) and use the number A assigns.
2. If C must prototype a node before A lands it, claim from the TOP of the free
   range and record it HERE the same commit, so A sees the reservation.
3. The C frontend's `cparser` builds nodes in **master's documented shape** (table
   above). Lowering for these lives in `ir.inc` and is **Track A's**; C only emits.
4. AN_CASE/AN_DEFAULT are shared Pascal+C node kinds (17/48) — C switch reuses
   them, does not redefine.
