---
prio: 15
---

# pxx evaluates binary-operator operands (and CALL ARGUMENTS) left-to-right; FPC evaluates right-to-left

- **Track:** A (fix, if ever, is in `compiler/ir.inc` AN_BINOP lowering /
  backend codegen — shared core). **Tag:** compat (FPC-parity). Owning frontend
  for the semantics: P (Pascal).
- **Found:** 2026-07-16, pasmith seed 27863 (see
  `bug-t-pasmith-with-rung-mutates-global-inside-function`, the generator side).
- **Status:** DOCUMENTED, deliberately unfixed. Rainy-day only.

## The difference

Order of evaluation of a binary operator's two operands is **unspecified** in ISO
Pascal and in FPC's documentation. The two implementations pick opposite orders:

- **pxx:** left operand first (left-to-right).
- **FPC:** right operand first (right-to-left).

Observable only when one operand has a side effect the *other* operand reads —
i.e. **badly written code** that already relies on unspecified behaviour. Minimal:

```pascal
program ord;
var r: word;
function sidef: word; begin r := 810; sidef := 0; end;
var res: word;
begin
  r := 778;
  res := r xor sidef;   { FPC prints 810 (r read after call), pxx prints 778 }
  writeln(res);
end.
```

Both compilers are internally self-consistent across O0/O2/O3. Neither is wrong.

## Why it is NOT fixed

- **Unspecified by the spec** — there is no "correct" order to converge on. Fixing
  it means *choosing to mimic FPC*, not correcting a bug.
- **Only bites code that is already broken** — well-defined programs never place a
  side effect in one operand that another operand observes.
- **High blast radius, low reward.** The change (lower/emit the right operand
  before the left in the generic scalar AN_BINOP path, `compiler/ir.inc` ~line
  4721) re-emits code for *every* arithmetic/comparison expression: a self-host
  reseed, potential -O3 W1 operand-scheduler interaction, and a real risk of
  surfacing latent order-assumptions in the RTL/self-host. Reluctant to ship for
  a purely cosmetic parity gain.
- **NOTE (verified 2026-07-16):** swapping only the two `IRLowerAST` calls in the
  lowering does **nothing** — an IR value is a *subtree* consumed by IR_BINOP
  (the b346 landmine), so runtime operand order is decided in the **backend**
  codegen (`ir_codegen*.inc` IR_BINOP `IREmitNode(left)` vs `right`), per target.
  A real fix must touch all six backends, not the shared lowering. This is what
  makes it genuinely expensive, not a two-line swap.

## When it might matter

Only under a future **strict `--mimic-fpc` / `--strict-fpc`** mode where
byte-for-byte FPC behavioral parity on *unspecified* constructs is a goal (e.g.
importing real-world FPC code that leans on FPC's right-to-left order). Even then,
prefer a diagnostic ("operand has a side effect a sibling reads") over silently
reordering. Not worth doing outside that context.

## Same divergence, second construct: CALL ARGUMENTS (2026-08-22)

Found independently by the parameter-passing differential family, before this
ticket was read — which is itself the useful part of the report: the two
constructs look unrelated from a test, and are one decision in the compiler.

```pascal
function A(x: Integer): Integer; begin WriteLn('A', x); Result := x + 1; end;
function B(x, y: Integer): Integer; begin WriteLn('B', x, y); Result := x * y; end;
begin
  WriteLn(B(A(1), A(2)));
end.
```

```
FPC : A2 A1 B23 6        <- arguments right-to-left
pxx : A1 A2 B23 6        <- arguments left-to-right
```

Everything this ticket already says applies unchanged: unspecified in ISO Pascal
and in FPC's documentation, observable only when one argument has a side effect
another argument reads, and therefore only in code that already depends on
unspecified behaviour. The result (`6`) and the callee's own view of its
parameters are identical; only the order of the side-effect prints differs.

**Scope note for whoever eventually takes this:** it is one decision with two
lowering sites, and fixing either alone would leave the codebase inconsistent
with itself, which is worse than being consistently different from FPC. If it is
ever done, do both — `AN_BINOP` lowering and the argument loop in
`IRLowerCallArg`'s callers — in one change, and gate it on the full suite: a
right-to-left argument order interacts with the by-ref temp queue
(`PostCallIntfSym`) and with the deferred-argument optimisation
(`ArgSymAddrClean`), neither of which is order-neutral by construction.

Still prio 15, still rainy-day. Recorded here rather than as a second ticket so
the pair cannot be fixed by halves.
