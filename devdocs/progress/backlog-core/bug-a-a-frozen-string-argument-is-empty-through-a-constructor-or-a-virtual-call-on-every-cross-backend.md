---
type: bug
track: A
prio: 92
status: open
summary: On i386/arm32/aarch64/riscv32 a string[N] passed to an AnsiString
  parameter of a CONSTRUCTOR or a VIRTUAL method arrives EMPTY — silently, in
  the DEFAULT mode, and it reproduces at the pin. x86-64 is correct.
---

# A frozen string argument is empty through a constructor or a virtual call

**Not flag-gated.** This is the DEFAULT mode. `-dPXX_SHORTSTRING` is not needed
to reach it and does not change it.

```pascal
type
  R = record f: string[10]; end;
  TB = class
    val: AnsiString;
    constructor Create(const a: AnsiString);
    procedure M(const a: AnsiString);
    procedure V(const a: AnsiString); virtual;
  end;
constructor TB.Create(const a: AnsiString); begin val := a; end;
procedure TB.M(const a: AnsiString); begin WriteLn('M <', a, '>'); end;
procedure TB.V(const a: AnsiString); begin WriteLn('V <', a, '>'); end;
procedure P(const a: AnsiString); begin WriteLn('P <', a, '>'); end;
var s: string[10]; r: R; o: TB;
begin
  s := 'plain'; r.f := 'field';
  P(s); P(r.f);
  o := TB.Create(s);   WriteLn('C1<', o.val, '>');
  o := TB.Create(r.f); WriteLn('C2<', o.val, '>');
  o.M(s); o.M(r.f);
  o.V(s); o.V(r.f);
  P('lit'); o.M('lit');
end.
```

| row | x86-64 | i386 / arm32 / aarch64 / riscv32 |
| --- | --- | --- |
| `P(s)` / `P(r.f)` — plain routine | `<plain>` `<field>` | **correct** |
| `TB.Create(s)` / `TB.Create(r.f)` | `<plain>` `<field>` | **`<>` `<>`** |
| `o.M(s)` / `o.M(r.f)` — non-virtual | `<plain>` `<field>` | **correct** |
| `o.V(s)` / `o.V(r.f)` — VIRTUAL | `<plain>` `<field>` | **`<>` `<>`** |
| a string LITERAL, either route | correct | **correct** |

So it is not "frozen strings", not "methods", and not "class arguments": it is
**the constructor path and the virtual-dispatch path**, and only for an operand
the frozen-to-managed conversion has to build a handle for. A literal takes a
different arm and is fine, which is why every class test in the tree passes.

## Reproduced at the pin — not a regression

`stable_linux_amd64/default/pinned`, i386 and arm32: identical `<>` rows.
Measured 2026-09-03 while building the acceptance suite for
`bug-a-i386-copy-and-pos-segfault-under-the-byte-prefix-mode`; that fix and its
x86-64 sibling touch the DIRECT call path only, and the pinned run rules them
out as the cause.

## Where it is, and why the small fix is the wrong one

Every backend carries the frozen-to-managed argument conversion in its
`Procs[...].Params[n].TypeKind = tyAnsiString` ladder — and each backend has
that ladder **once per call path**. x86-64 has four copies (ordered args, direct
call, constructor, method/indirect) and all four convert. The cross backends
have it in the DIRECT call arm and not in the others: i386's `IR_CALL_IND` arm
says in its own comment *"Same shared decision as the direct and virtual paths"*
and then re-derives a ladder that has no string arm at all.

**Three call paths x five backends is fifteen copies of one decision, and today
four of them are right.** Patching the eleven is the microfix; the ladder has
already grown a by-value SET case and a cdecl RECORD case at one site and not
the others, each found the same way. The conversion is target-independent — it
is "this argument is a frozen buffer and the callee wants a handle" — so the
root-cause fix is to do it ONCE in `IRLowerCallArg`, where every call funnels
through, and delete the arms. `devdocs/dev/ir-as-substrate.md` and
`normalise-dont-special-case.md` both point at that shape.

Whoever takes this should decide that first; the fifteen-copy count IS the
finding.

## Acceptance

The program above, five targets, BOTH modes, values asserted — every row must
print its content. Add the wasm32 and xtensa rows if their runtimes can reach
it; they are blank here, not green.


## Prio raised 85 -> 92 (coordinator, 2026-09-03)

**Reproduced independently** at `a154b5ec9`, compiler `9ce317b156e9`, DEFAULT
mode, no flag:

```
            x86-64    i386 / arm32 / aarch64 / riscv32
plain(s)    [hello]   [hello]
ctor(s)     [hello]   []        <-- empty
method(s)   [hello]   [hello]
virtual(s)  [hello]   []        <-- empty
virtual(lit)[hello]   [literal]
```

Raised above the phase-4 blockers, and the reasoning is the goal rather than the
overhaul:

- **It is the DEFAULT mode.** Every byte-prefix ticket in this family needs
  `-dPXX_SHORTSTRING` to bite. This one ships today, in the build every consumer
  of `$(PXX_STABLE)` uses.
- **It is four of seven targets on the ctor/virtual rows, and x86-64 is correct
  on THOSE** — but see the correction below: the proc-var indirect row was empty
  on x86-64 too, so that row is five targets, not four. The blindness argument
  holds for the rows it was made about and was stated too broadly. — so the dev
  loop, `gate.sh quick` and the pin are all blind to it by construction.
- **A constructor taking a string is not an edge case.** `the-goal-cross-cross`
  is pxx hosting itself somewhere that is not Linux/x86-64 and compiling DOSBox
  for such a target. Any OOP Pascal cross-compiled today silently gets empty
  strings into its constructors.

**A literal works through both routes, which is why every class test in the tree
passes.** That is the guard trap: the population that would catch this is
"non-literal string argument through a constructor or virtual call", and nothing
in the suite constructs it.

**Do not microfix the ladder.** franka-29's count is the finding: the conversion
is re-derived once per call path per backend — ordered args, direct,
constructor, method/indirect, ~15 copies of which 4 are right — and the same
ladder has already drifted twice on other axes (a by-value SET case, a cdecl
RECORD case), each landing at ONE site. The conversion is target-independent
("this argument is a frozen buffer and the callee wants a handle"), so the
answer is `IRLowerCallArg` once and delete the arms. `root-cause-over-microfix`,
and the overhaul is the smaller job because it deletes cases.


## FIXED at the root — the conversion moved into IRLowerCallArg (2026-09-03)

`IRLowerCallArg` grew the mirror of the arm that was already there. It had the
MANAGED -> FROZEN direction (frozen param, AnsiString arg: hidden frozen temp,
`tmp := arg`, pass the temp's address); it now has FROZEN -> MANAGED the same
way — a hidden owning `tyAnsiString` local, `tmp := arg` lowered through the
ordinary assignment path, and a load of the temp as the argument.

**It reuses the assignment path rather than growing a second one.** `m := s` for
a managed `m` and a frozen `s` was already correct on all seven backends, so the
conversion is a store plus a load and no backend learns anything new.

### Two things this needed that reading would not have found

**1. A hand-built `IR_STORE_SYM` is not the assignment path.** The first version
did `IRAppend(IR_STORE_SYM, tmp, IRLowerAST(argAST), ...)`, which looks
equivalent and is not — the store arm wants an address where `IRLowerAST` gave a
value. Every call OOM'd: `pxx: out of memory (heap arena mmap failed)`, rc=203,
on the one-line repro. Synthesising `AN_ASSIGN` and lowering THAT is what the
neighbouring arm does, and for this reason.

**2. THE ARG NODE'S TAG IS NOT THE VALUE'S.** `IRAppend(IR_ARG, value, ..., ASTTk[argAST])`
— seventeen sites — takes the kind from the AST, so after the conversion the arg
node still said `string[10]` while carrying a heap handle, and every backend
ladder converted a SECOND time, reading the handle pointer as a `[len][chars]`
buffer. Same OOM, different cause; the IR dump is what separated them
(`3: store_sym tmp <- lea s (tk=23)` then `5: arg ... tk=4`). Added `IRArgTk`,
deliberately narrow — it retags only a frozen-typed AST whose lowered value came
back `tyAnsiString` — and put all seventeen sites through it, so they cannot
disagree about the one question they all ask.

### Verified

**40 measured cells.** Five targets (x86_64 native, four under qemu) x the modes
each program compiles in, values asserted against a written `.expected`.

| program | modes | result |
| --- | --- | --- |
| all shapes x all call paths | default, `-uPXX_MANAGED_STRING` | 10/10 PASS |
| variable x all call paths | all four modes | 20/20 PASS |
| aggregates via `Pos`/`Copy` | default, `-dPXX_SHORTSTRING` | 10/10 PASS |

Shapes: variable, record field, field-of-field, array element with a CONSTANT
index and with a VARIABLE index, field of an array element. Paths: direct,
ordered two-arg, constructor, non-virtual method, virtual (base and overridden),
proc-var indirect.

**Negative control — a rebuilt pre-fix compiler (`009ba51e751c`) fails these**,
and it corrected the ticket: the proc-var indirect row is empty on **x86-64
too**, so this was five targets on that path, not four.

### AND A LEAK THAT EVERY VALUE ROW ABOVE PASSES WITH FULLY PRESENT

The inline conversions called `PXXStrFromLit` per call and nothing owned the
result. Measured with `tools/assert_no_leak.sh`, 3000 calls:

| | allocs | frees |
| --- | --- | --- |
| pre-fix (x86-64, printing CORRECT values on every one) | 3000 | **0** |
| fixed, each of x86-64 / i386 / arm32 / aarch64 / riscv32 | 3000 | 2998 |

An unbounded per-call leak on every target, on the paths that were *right*.

### What is NOT done

**The ~15 inline backend arms are still there.** They are now unreachable for
everything that funnels through `IRLowerCallArg` — the arg node no longer
carries a frozen tag — but "believed dead" is not "proven dead", so they are
left standing rather than deleted on a reading. Deleting them wants a canary
build per backend that turns each arm into an `Error` and a run that must stay
green. That is the remaining work on this ticket.

**Two shapes could not be exercised at all today**, and neither is this fix's
doing:
- Anything but a plain variable under `-dPXX_SHORTSTRING`: overload resolution
  refuses it (`bab799137`, frankb-78, unlanded by agreement so this lands first).
- A frozen FUNCTION RESULT in any mode: same refusal, and it is the shape that
  reaches this conversion by a third route (`Procs[].RetType`, the storage kind).
- `-uPXX_MANAGED_STRING` + the `Pos`/`Copy` intrinsics: `builtin/builtin.pas`
  does not compile in that mode, **at the pin as well**, for an unrelated reason
  (`a Char VALUE is not a PChar`). Blank, not green.


## Corrections and additions after the fix (2026-09-03)

**MY "x86-64 IS THE CORRECT ONE" WAS ONE ROW TOO BROAD.** franka-29's negative
control found the **proc-var indirect** path empty on x86-64 as well, so that
row is five targets. The priority reasoning survives — the ctor and virtual rows
really are cross-target-only and really are invisible to an x86-64 dev loop —
but the sentence claimed more than was measured. **Found by the control, not by
anyone's reading, including mine.**

**IT WAS ALSO AN UNBOUNDED LEAK, ON THE PATHS THAT WERE ALREADY RIGHT.** The
inline conversions called `PXXStrFromLit` per call and nothing owned the result:

```
pre-fix,  x86-64, printing the CORRECT string every time   allocs=3000 frees=0
post-fix, each of x86-64/i386/arm32/aarch64/riscv32        allocs=3000 frees=2998
```

**Every value assertion in this family passes against `frees=0`.** This is
exactly the class CLAUDE.md names — a leak does not corrupt, it just never gives
memory back — and it was looked for *because* the handbook says to. There is now
a wired `assert_no_leak` row per target.

**THE SAME DEFECT EXISTED ONE LEVEL UP, IN THE LAYER THAT FEEDS THE LADDERS.**
Seventeen sites built `IR_ARG` from `ASTTk[argAST]` — **the AST's type, not the
lowered value's**. After the conversion the arg node still said `string[10]`
while carrying a heap handle, so every backend ladder converted a SECOND time
and read the handle pointer as a `[len][chars]` buffer: `out of memory`, rc=203.
**Seventeen copies of one question, each free to disagree — the same shape as
the fifteen ladders, in the layer above them.** Now routed through `IRArgTk`.

**Method note worth more than the fix:** that `out of memory` was hit twice from
two entirely different causes, and **reading could not separate them**. The IR
dump did, in one line — `store_sym tmp <- lea s (tk=23)` then `arg ... tk=4`.

## Remaining work — deliberately not done

**The ~15 inline backend arms are still standing.** They are unreachable for
anything funnelling through `IRLowerCallArg`, and **believed-dead is not
proven-dead**; CLAUDE.md is explicit that deleting code you believe is dead is
still wrong. **This family has already paid for that mistake once** — a session
widened the inline frozen-concat arm, banked it as unreachable, and it was
reachable under `-uPXX_MANAGED_STRING`.

Deleting them wants a per-backend canary turning each arm into an `Error` with a
run that must stay green. **The ticket stays OPEN for this reason**, not because
the bug survives.
