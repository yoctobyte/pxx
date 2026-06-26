# feature: value-bearing expression nodes for the C frontend (ternary + side-effecting exprs)

- **Type:** feature (shared AST/IR — language model)
- **Status:** backlog (slice 1 DONE 2026-06-26, pin v76; slices 2/3 open)
- **Track:** A (compiler core / shared lowering)
- **Opened:** 2026-06-26
- **Found-by:** Track A analysis prompted by the C frontend
  ([[track-a-c-frontend-shared-ir-touchpoints]] #2). Track C/D is told NOT to
  touch shared AST/IR — so A owns these nodes, implements + pins on `master`,
  Pascal self-host stays byte-identical, and the C frontend lowers onto them
  after the pin.

## Why

Pascal is not a C superset at the AST level for ONE reason: C makes **value-
bearing expressions** out of constructs Pascal models as **statements**. Any of
these nested inside a larger expression has no pxx AST node and no lowering:

| C | yields | pxx today |
|---|---|---|
| `a ? b : c` (ternary) | a value | no node (Pascal has no `if`-expression) |
| `x = y`, `a = b = c`, `if ((n=f())>0)` | the assigned value | `AN_ASSIGN` is statement-only (lowering returns a store, not the value) |
| `++x` / `x++` / `a[i++]` | new / old value | `Inc`/`Dec` are statements |
| `(a, b)` comma operator | `b` | `AN_SEQ` is a *statement* chain (Left=stmt, Right=next), not value-bearing |

NOT gaps (already map cleanly): `union`→variant record, function pointers→
`AN_PROCADDR`/`AN_CALL_IND`, `goto`/labels→`AN_GOTO`/`AN_LABEL`, casts/bitops/
enums→`AN_PTR_CAST`/`AN_BINOP`, `do/while`→`AN_REPEAT`, `x+=y`→desugar `x=x+y`
(*only* when the lvalue has no side effects — `a[i++]+=1` falls back to slice 2).
`switch` fallthrough is a separate case-model gap, not an expression node.

The IR layer needs **no new ops**: store-then-yield and `IR_IF`→temp already
suffice. The whole delta is at AST→IR: perform the side effect AND leave the
value available, in C's evaluation order (sequence points). Pascal never had to
sequence side effects mid-expression, so that machinery is absent.

## Slices (do slice 1 first; slices 2/3 are separable and may be parked)

### Slice 1 — `AN_TERNARY` (SHALLOW, the only un-fakeable node) — do this
The only construct that can't be honestly desugared into existing nodes. Cheap:
- New `AN_TERNARY` AST node (`Left=cond`, `Right=AN_PAIR(then, else)` — reuse the
  `AN_IF` shape).
- IR lowering = clone `AN_IF` (ir.inc:3337): `JUMP_IF_FALSE`/labels, but each arm
  stores its value into ONE hidden temp, then `Result := load(temp)`. ~15 lines.
- Result type = the unified arm type (C usual-arithmetic-conversions live in the
  C frontend; the node just carries the resolved type tag).
- Pascal parser never emits it → self-host byte-identical (verify). Optionally
  expose to Pascal later as an `if cond then a else b` expression — out of scope
  here, but the node makes it free.
- Estimate: ~half a day incl. a fixture. Low risk, fully Pascal-safe.

### Slice 2 — value-bearing assignment + pre/post `++`/`--` (RABBIT HOLE risk)
The deep part. Needs a hidden-temp side-effect-hoisting lowering that:
- evaluates each lvalue ONCE (so `a[i++] = x` / `*p++` are correct),
- for assignment-as-expression: store, then yield the stored value;
- for postfix: yield the OLD value, apply the increment after (sequencing);
- for prefix: apply, then yield the new value.
A clean way is a normalization pass that rewrites a side-effecting sub-expression
into `AN_SEQ`-with-value (a value-bearing sequence node, or extend `AN_SEQ` /
add `AN_STMTEXPR`): hoist side effects to temps in evaluation order, leave the
final value. This is where the effort and the ordering bugs live. Park if the C
fixtures don't yet need it; lua/sqlite will.

### Slice 3 — comma operator `(a, b)`
Falls out of slice 2's value-bearing sequence node: evaluate `a` for effect,
yield `b`. Trivial once slice 2's mechanism exists; otherwise a tiny standalone
`AN_SEQ`-value.

## Acceptance
- Slice 1: `t := (c <> 0) ? x : y;`-shape fixture (via the C frontend, or a
  temporary Pascal test harness) computes correctly; nested ternary; ternary as
  a call arg and as an lvalue index; `make test` green; self-host byte-identical;
  pinned so the C branch can build on it.
- Slices 2/3: side-effect order verified (`a[i++]`, `x=y=z`, `while((n=f())>0)`),
  each lvalue evaluated once; valgrind-clean on a managed-field case.

## Notes
- Controlled rollout: A implements on `master`, gates on Pascal byte-identical
  (the new nodes are never produced by the Pascal parser, so the gate is a strong
  safety net), pins; only then does the C frontend (own branch) target them.
- Slice 1 is the recommended standalone landing. Slice 2 is the one to scope
  carefully before starting — it is the actual "is this a rabbit hole" question.

## Slice 1 landed (2026-06-26, Track A — commit 01a92173, pin v76)

`AN_TERNARY` added (defs.inc) + parser `if c then a else b` expression form
(ParseFactor tkIf) + IR lowering (mirrors AN_IF, each arm stored into one hidden
temp via the AN_ASSIGN path, yields a load; short-circuit preserved). Frozen
string-literal arms carried as managed AnsiString. Verified int/bool/char/
pointer/string arms, short-circuit, nesting, ternary in writeln / call arg / RHS;
valgrind-clean; make test green incl cross; self-host byte-identical (Pascal
compiler source emits no ternary, so the node is a pure addition with a built-in
safety net). C frontend (feat/cfront) can now lower `c ? a : b` onto AN_TERNARY
after rebasing on pin v76.

Slices 2 (value-bearing assignment + pre/post ++/--) and 3 (comma operator)
remain open — they need the side-effect-hoisting pass and are the real scope
question. Not started.
