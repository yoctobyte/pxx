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
- **It is four of seven targets, and x86-64 is the correct one** — so the dev
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
