---
slug: bug-p-ten-constructs-fpc-rejects-are-accepted-and-silently-wrong
title: "Ten constructs FPC rejects compile clean here, and five of them produce a silently wrong value"
track: P
prio: 55
type: bug
blocked-by: []
status: done
owner: claude-A
created: 2026-08-25
summary: "A 28-construct sweep of things fpc 3.2.2 rejects: pxx accepts 10 of them with NO diagnostic and exit 0. Laxness by itself is dialect policy, but five of these are not lax, they are WRONG -- `i[2]` on an Integer reads out of bounds (-2099249120), `for s := 1 to 3` makes the rest of the program not run, `New(i)` overwrites an Integer with a heap pointer, `Inc(s)` empties an AnsiString, `Length(i)` answers 1. That is the compat-tag escape rule: silent wrong behaviour is a bug, not a parity nitpick."
---

# The sweep

28 one-construct programs, each otherwise identical and valid, each rejected by
`fpc -Mobjfpc -O1`. Measured against pxx at `f687061db`. 18 are diagnosed; these
10 compile clean, exit 0, and print:

| construct | fpc | pxx exit | what actually happens |
| --- | --- | --- | --- |
| `i := i[2]` (i: Integer) | Illegal qualifier | 0 | **i becomes -2099249120** — an out-of-bounds read off a scalar |
| `for s := 1 to 3 do ;` (s: AnsiString) | Illegal counter variable | 0 | **the program produces NO output at all** — the trailing WriteLn never runs |
| `New(i)` (i: Integer) | Illegal qualifier | 0 | **i becomes a heap pointer** (264241264) |
| `Inc(s)` (s: AnsiString) | Incompatible type | 0 | **s is emptied** — `'x'` becomes `''` |
| `i := Length(i)` | Illegal qualifier | 0 | **answers 1** |
| `while i do ;` (i: Integer) | Type mismatch | 0 | no output — same disappearing tail as the `for` |
| `b := r < 1` (r: a record) | Illegal qualifier | 0 | answers FALSE off garbage |
| `F1(1) := 3` | Illegal expression | 0 | accepted, no effect |
| `with i do ;` | Illegal expression | 0 | accepted, no effect |
| `if i then ;` (i: Integer) | Type mismatch | 0 | treated as `i <> 0` |

# The line between dialect and defect

`devdocs/dev/` and CLAUDE.md are explicit that **PXX's dialect is deliberately
lax by default** and that FPC-parity strictness belongs behind `--strict-*`
flags. Two rows here are plainly that kind of laxness and should be left alone
(or flagged, not fixed): **`if i then`** and **`while i do`** with an ordinal
condition is the C rule, deliberate and useful — except that the `while` row
*also* swallows the rest of the program, which the `if` row does not, so the
two are not the same finding.

The other rows are not laxness in any useful sense. Nobody wants `Inc` on a
string to empty it, or `New` on an Integer to overwrite it with a pointer, or a
`for` loop over a string counter to delete the remainder of the program. The
compat tag's own escape rule covers exactly this: *"a compat finding that means
silent wrong behavior is promoted to a normal bug ticket in the owning lane"*.

# Ranked inside the ticket

1. **`for s := 1 to 3 do ;` and `while i do ;` losing the program tail** —
   control flow silently disappears, and that can hide in a large unit for a
   long time. Worst of the set; possibly one cause for both.
2. **`i[2]` and `New(i)`** — an out-of-bounds read and a scalar overwritten with
   a heap pointer. Memory-unsafe, and they are the two most likely to appear as
   a typo in real code (`i[2]` where `a[2]` was meant).
3. **`Inc(s)`, `Length(i)`, `r < 1`** — wrong values, contained.
4. **`F1(1) := 3`, `with i do`** — accepted and inert. Diagnostics wanted, no
   wrong behaviour.
5. **`if i then`** — deliberate dialect; only worth a `--strict-*` mention.

# Method, so it can be re-run

Each case is a program of the form: fixed header declaring `r: TR; c: TC;
i: Integer; s: AnsiString; b: Boolean; arr: array[0..3] of Integer;
d: array of Integer; p: PChar`, the one bad statement, then
`WriteLn(i, s, b, r.a)`. Compare `fpc -Mobjfpc -O1` error count against pxx's
exit status, then RUN the pxx binary — the run is what separates "lax" from
"wrong", and it is the step that turns this from a parity list into a bug
ticket. Generator kept in the session scratchpad; it is 40 lines and worth
rewriting rather than recovering.

# Related

- [[bug-p-an-assignment-is-not-type-checked-at-all]] — filed 2026-08-24 from
  the same kind of sweep, and since fixed for assignments: the four
  assignment rows in this sweep (`i := r`, `r := i`, `i := s`, `s := i`) are all
  correctly diagnosed now, which is why they are not in the table above.
- [[feature-a-error-does-not-halt-so-a-parse-can-be-speculative]] — the sweep
  came out of that ticket's slice-5 measurement; the diagnostics that DO fire
  and their recovery behaviour belong there, the missing ones belong here.

## Five of the ten closed 2026-08-25 (claude-A) — the ones that were WRONG, not lax

The ticket's own ranking said to take the corrupting rows first and leave the
inert ones. Done, in that order, and the top row turned out to be worse than
filed.

### `for s := 1 to 3` did not merely drop the tail — it SEGFAULTS

Filed as *"the program produces NO output at all"*. Adding one more statement
after the loop turns it into a segfault: the loop machinery increments the
counter's SLOT, and for a managed string that slot is the HANDLE, so the body
runs against a walked pointer. The small case exits 0 having printed nothing;
the larger one faults. That is the expensive shape — a wrong VALUE far from the
cause, not a crash with a location.

A counted `for` now requires an ordinal counter, FPC's "Illegal counter
variable". The for-IN form is exempt and must stay so: its counter binds to an
ELEMENT and is legitimately a string, a record or a class.

### The other four

| construct | what it did | guard |
| --- | --- | --- |
| `i[2]` | took `Syms[i].ElemType` — for a scalar, its own type — and emitted an element load off the variable's own address: an **out-of-bounds read** | the index fallback refuses an ordinal/float base that is not an array |
| `New(i)` | allocated `TypeSize(tyUnknown)` bytes and stored the block address **into the Integer** | `New` requires a pointer-typed target |
| `Inc(s)` | desugared to `s := s + 1`, the string CONCAT path took it, and the variable was **destroyed** — `'x'` became `''` | Inc/Dec refuse string/record/class/set/variant |
| `Length(i)` | read a `[data-8]` length header off an Integer's VALUE and answered **1** | Length refuses a plain ordinal/float operand |

Every guard is placed in the FALLBACK arm, after every legal shape has been
claimed — so the guard fires on what is left over rather than on a list of bad
cases. That is the difference between a check that stays right as shapes are
added and one that goes stale.

All five **recover** (`ErrorRecover`), so one compile reports all five, which is
[[feature-a-error-does-not-halt-so-a-parse-can-be-speculative]] item 2 doing its
job on the first new diagnostics written since it landed.

### The positive half is the real risk, and is tested

Five guards at once, and a guard one shape too wide is a compiler that rejects
valid Pascal — worse than the laxness it replaces. So
`test/test_indexing_length_for_new_inc_positive.pas` walks the whole legal
surface: a counted `for` over Integer, Char, Boolean, an enum, Int64, Word, a
subrange and `downto`, plus `for..in` over a dyn array and a string literal;
indexing a string, a fixed string, a Char array, a static array, a dyn array, a
jagged array both spellings, a 2-D array both spellings, a PChar and a typed
pointer; `Length` of all of those plus an open-array parameter, a record's
static-array field, a whole 2-D array, a literal and `''`; `New`/`Dispose` over
a record pointer and a typed pointer; `Inc`/`Dec` over Integer, Char, Int64, an
enum and a pointer with a step. **Byte-identical to fpc 3.2.2 natively and under
qemu on i386, aarch64, arm32 and riscv32.**

Self-host is the other half of that check and it converged in one round every
time: 37k lines of this compiler's own Pascal passed all five new guards
unchanged.

`Inc(d)` on a Double is left accepted and appears in NEITHER test: it is
laxness of the ordinary kind (it computes `d + 1` and damages nothing), and FPC
rejects it, so it cannot sit in a test whose `.expected` is FPC's own output.
Refused nowhere, asserted nowhere — which is exactly its status.

### Still open — the five inert ones

`F1(1) := 3`, `with i do`, `b := r < 1`, and the two ordinal-condition rows
(`if i then`, `while i do`). None corrupts anything: the first two are accepted
and do nothing, `r < 1` answers off garbage, and the last two are the C rule
this dialect keeps on purpose. Diagnostics are still wanted for the first three;
`if i` / `while i` want at most a `--strict-*` mention. Left for a second pass —
the ticket's own ranking put them at 3-5.

Gate: `make compiler/pascal26` fixedpoint converged in one round;
`tools/gate.sh quick` GREEN.

## The other three closed the same night, and the table's two remaining rows are correct

The section above closed the five corrupting rows and left five "inert" ones.
Three of those are now refused, and the other two turned out to be **correctly
implemented laxness** — one of them mis-measured in this ticket's own filing.

| construct | what it did | guard |
| --- | --- | --- |
| `b := r < 1` | compared the record's first qword against 1 and answered off garbage | ORDERING operators (`< > <= >=`) refuse a record operand with no overload |
| `with i do` | accepted, scoped nothing, ran the body against the enclosing scope | `with` refuses an ordinal or float operand |
| `F1(1) := 3` | emitted the CALL and **silently dropped the store** | a call node returned with an assignment operator still pending is refused |

**Only ORDERING, not equality** — and that asymmetry is deliberate and already
written down. The arithmetic arm one branch above says comparisons are left
alone because *"method-pointer `=`/`<>` are legitimate record compares"*. That
is true of equality and not of ordering, so this is the half that arm left out,
not a widening of it.

**`F1(1) := 3` was the interesting one.** Nothing rejected it because nothing
SAW it: the plain-call branch built the call and returned, leaving `:= 3` for
the NEXT statement, where the catch-all `else` skipped to the `;`. So the call
ran and the store vanished — inert in the ticket's sense, and the worst of the
three, because the code reads as if it assigns. The check is placed at
`ParseStatementAST`'s single exit rather than in the branch that happened to
build this one: `F1(1) := 3` comes out of the plain-call branch, `o.M := 3` out
of the lvalue branch, and one test on the node actually being returned covers
both without a third copy when a third spelling appears.

It also uses `ErrorAt(ASTLine[node], …)` where the ordering check is concerned:
lowering runs long past EOF, so plain `Error` reported the program's LAST line
(`end.`) and pointed its `near:` window there. The sibling arithmetic arm still
does that; left as found rather than changed under this ticket's gate.

### `if i then` and `while i do` are laxness, and the filing was wrong about one

The table in this ticket said `while i do ;` produced "no output — same
disappearing tail as the `for`". Re-measured: it does not. `while i do` with a
non-zero `i` and an empty body is an **infinite loop**, which is what "no
output" was; the sweep runner's `timeout` exit was read as the program's. With a
body that clears the counter it behaves exactly as `i <> 0`:

```
before / after n=4 / if-false
```

So both ordinal-condition rows are the C rule, correctly implemented, and stay.
They want at most a `--strict-*` mention, which is a different ticket.

### Measured

The positive test grew `with` over a record and a class, and ordering over
Integer, Char, AnsiString and an enum. **Byte-identical to fpc 3.2.2 natively
and under qemu on i386, aarch64, arm32 and riscv32**, and the compiler's own
37k lines pass all eight guards (fixedpoint converged in one round each time).
`test_scalar_misuse_is_refused_fail` now asserts eight diagnostics in one
compile, exit 1, no binary.

**8 of 10 refused, 2 correct as they stand — the ticket is closed.**

Gate: `make compiler/pascal26` fixedpoint converged in one round;
`tools/gate.sh quick` GREEN.

## Log
- 2026-08-25 — resolved, commit PENDING-COMMIT.
