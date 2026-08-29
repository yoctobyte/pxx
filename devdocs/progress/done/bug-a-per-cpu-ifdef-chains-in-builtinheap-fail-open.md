---
track: A
prio: 60
type: bug
blocked-by: []
summary: "The per-CPU {$ifdef} chains in compiler/builtin/builtinheap.pas have no terminal {$else}, so a target with no arm gets whatever the pre-chain default was — and for PXXSysOpenRO and PXXSysLseek there is no default at all: Result is NEVER ASSIGNED. Both are guarded only by {$ifndef PXX_ESP} and have arms for x86-64/i386/arm32/aarch64 only, so on HOSTED RISCV32 and on wasm32 they compile and return the return slot's leftover contents. PXXStrLoadFile then does `if fd < 0 then Exit` on that garbage and, if it happens to be non-negative, calls PXXAlloc(size + ...) with an equally garbage size. Four instances of the same generator shape in this one file; the systemic fix is a terminal else that fails LOUD, not four more arms."
status: done
owner: ""
---

# The per-CPU `{$ifdef}` chains in `builtinheap.pas` fail open

- **Type:** bug (RTL / builtin) — **Track A** (`compiler/builtin/**`).
- **Filed:** 2026-08-28 by the wasm32 lane, from an audit the coordinator asked
  for after `bug-a-pxxsyswrite-has-no-wasm32-arm` turned out to be an instance
  of a shape rather than a one-off.
- **Not a wasm ticket.** wasm32 is how it was noticed; **hosted riscv32** is the
  shipping target that hits it today.

## The shape

Every per-target syscall wrapper in this file is written as a run of
`{$ifdef CPU_x}` blocks with **no terminal `{$else}`**. Adding a target means
adding an arm; forgetting to means the routine silently does nothing, or worse.
There is no place for the compiler to say "this target has no arm."

Four instances in this one file:

| routine | arms | pre-chain default | what an armless target gets |
| --- | --- | --- | --- |
| `PXXSysWrite` (1537) | 5 + wasm32 | `Result := 0` | "wrote nothing, no error" — **fixed**, see `bug-a-pxxsyswrite-has-no-wasm32-arm` |
| `HeapMmap` (681) | 5 | `Result := 0` | a heap that bumps from **address 0** — filed, `bug-a-heapmmap-has-no-wasm32-arm-so-the-heap-starts-at-address-zero` |
| **`PXXSysOpenRO` (1861)** | **4** | **none** | `Result` **never assigned** |
| **`PXXSysLseek` (1877)** | **4** | **none** | `Result` **never assigned** |

The first two at least return a *defined* wrong value. The last two do not.

## The two that are worse, and who they hit

```pascal
function PXXSysOpenRO(path: Pointer): Int64;
begin
{$ifdef CPUX86_64}  Result := __pxxrawsyscall(2,  Int64(path), 0, 0);    {$endif}
{$ifdef CPU_I386}   Result := __pxxrawsyscall(5,  Int64(path), 0, 0);    {$endif}
{$ifdef CPU_ARM32}  Result := __pxxrawsyscall(5,  Int64(path), 0, 0);    {$endif}
{$ifdef CPUAARCH64} Result := __pxxrawsyscall(56, -100, Int64(path), 0, 0); {$endif}
end;
```

`PXXSysLseek` is the same four arms. Both sit inside `{$ifndef PXX_ESP}` —
**ESP is excluded deliberately and says so in the header comment; nothing
excludes riscv32 or wasm32.** Meanwhile `PXXSysRead` and `PXXSysWrite`, twenty
lines earlier and in the same group, *do* carry `CPU_RISCV32` arms (63 / 64,
"hosted linux (qemu-user)"). So the drift is visible in the file: riscv32 was
added to read and write and not to open and lseek.

The caller makes the consequence concrete (`PXXStrLoadFile`, 1912):

```pascal
  fd := PXXSysOpenRO(path);
  if fd < 0 then Exit;                     { garbage may well be >= 0 }
  size := PXXSysLseek(fd, 0, 2);           { garbage }
  ...
  base := Int64(PXXAlloc(size + PXX_HDR_SIZE + 1, 8));   { garbage-sized alloc }
```

So on hosted riscv32, `LoadFile` on a target with no `open` does not fail — it
proceeds on an uninitialised fd and allocates an arbitrary amount of memory.

## The fix that is NOT four more arms

Adding `CPU_RISCV32` to both closes today's instance and leaves the generator
running: the next target repeats it, exactly as wasm32 just did twice.

Give every chain a terminal `{$else}` that fails **loud**:

```pascal
{$ifdef CPUAARCH64} ... {$endif}
{$if not (defined(CPUX86_64) or defined(CPU_I386) or defined(CPU_ARM32)
          or defined(CPUAARCH64) or defined(CPU_RISCV32))}
  {$error PXXSysOpenRO has no arm for this target}
{$endif}
```

A compile-time refusal is the right failure here for the same reason the wasm32
backend records an unlowered body rather than skipping it: a target that cannot
do something must say so, not return a plausible value. If a target genuinely
should be a no-op (ESP has no filesystem), that is an explicit arm saying
`Result := -1`, not an absence.

Whether `{$error}` / `{$if defined(...)}` are available in this dialect is the
first thing to check; if not, an explicit `{$else} Result := -1; {$endif}` per
chain is the fallback, and at least the value is defined and negative.

## Related

- Same generator shape, different file: the Track P ticket filed 2026-08-27 for
  a `{$ifdef}` chain of 34 arms with no final `else` silently ignoring a
  compiler directive. Two files, one defect class, one week.
- `bug-a-heapmmap-has-no-wasm32-arm-so-the-heap-starts-at-address-zero` (p70)
  is the instance with the largest blast radius and stays open on its own.

---

> **PROVENANCE NOTE — frank-coordinator, 2026-08-29.** Everything from here down
> was written on 2026-08-28 (`f7bf2dfa3`, `04b745294`) and **never reached this
> ticket.** Both appends were addressed to `backlog/<slug>.md` while the ticket
> lived in `backlog_new/`; `>>` created an empty-headed file at the wrong path
> instead of failing, so the ranker offered TWO entries for one slug — this one,
> complete but missing all of the analysis, and an orphan fragment with no
> frontmatter carrying all of it. Reunited here. Nothing below is edited; the
> wrong table and its correction are both kept, in that order, because the wrong
> one is what a reader may already have seen.

## The proposed fix has an in-repo POSITIVE CONTROL — measured 2026-08-28

Do not argue this fix from first principles. The same codebase already contains the same
missing-arm shape with the **opposite** failure mode, and the difference is one `else`.

`EmitZeroFrameSlot` (`compiler/ir_codegen.inc`) dispatches per target and ends:

```pascal
  else
    Error('compiler error: EmitZeroFrameSlot: unhandled target');
```

It has no wasm32 arm either. The observed result is
`compiler error: EmitZeroFrameSlot: unhandled target` on
`test_dynarray_insert_delete.pas` — **a clean refusal naming the routine and the target**,
filed as `bug-a-emitzeroframeslot-has-no-wasm32-arm` at **p55**.

The chains in this ticket have no terminal `else`, so the same omission produces
`PXXStrLoadFile` allocating on an uninitialised size — **p70, and it took a deliberate audit
to find.**

| | missing arm, terminal `else` | missing arm, no terminal `else` |
| --- | --- | --- |
| example | `EmitZeroFrameSlot` | `PXXSysOpenRO`, `PXXSysLseek` |
| result | compiler error naming routine + target | uninitialised return, arbitrary allocation |
| found by | the first program that hit it | a deliberate audit, weeks later |
| prio it earned | 55 | 70 |

**The 15-point gap between them IS the value of the terminal `else`**, priced by this repo's
own triage rather than asserted. That is the whole argument for this ticket, and it is
empirical.

---

## CORRECTION 2026-08-28 — the positive control above is WRONG in two ways

The table above was written by frank-coordinator and is corrected here rather than edited
away, because the wrong version is the one someone may already have read.

**Error 1 — wrong file.** `EmitZeroFrameSlot` is defined at **`compiler/symtab.inc:10074`**,
not in `ir_codegen.inc`. The original grep ranged over `compiler/*.inc` and the file was never
checked.

**Error 2 — and it inverts the point.** `EmitZeroFrameSlot` has **TWO** per-target chains, one
per size class, and the table described only one:

| chain | targets named | terminal arm | behaviour |
| --- | --- | --- | --- |
| **wide** (`nBytes > TARGET_PTR_SIZE`) | i386, arm32, aarch64, riscv32, xtensa | `Error(...)` | **fails LOUD** — what the table described |
| **narrow** (`nBytes <= TARGET_PTR_SIZE`) | i386, arm32, aarch64, xtensa, riscv32 | **bare `else` that IS the x86-64 implementation** | **falls OPEN** |

The narrow chain is the one **every managed scalar** goes through. So the routine offered as
this family's counter-example is itself a member of it.

### The corrected argument is STRONGER, which is why it is worth restating rather than deleting

The 55-vs-70 contrast still holds, but not for the reason given. Both behaviours live in **one
routine, forty lines apart** — so this is no longer a comparison across two files with other
differences, it is a controlled one:

> **A reader sees the loud arm. Every program runs the silent one.**

That is the whole cost of a missing terminal `else`, demonstrated inside a single routine with
everything else held constant.

### The general rule this yields

> **A dispatch chain whose last arm is a REAL TARGET rather than an error is a fall-open chain
> wearing the shape of an exhaustive one.**

Six named arms and an unnamed seventh reads as *"the default"* when it is in fact **x86-64** —
the bytes are `mov qword [rbp+off], 0`. That is why reading missed it and a probe found it, and
it is the third instance of `refactor-a-target-dispatch-chains-fail-open`'s general case.

**Severity, measured rather than assumed** (frankwasm, `ed1d37a8b`): a probe build emitting
nothing there produces **byte-identical `.wasm` for three slices** — `Code[]` is unread on that
target, so nothing wrong has ever come out of it. **Latent, not active. Prio stays 55, for the
opposite reason to the one recorded.**

**And the guarantee whose own header says it has ONE owner has three mechanisms on wasm32** —
the backend's prologue pass, the x86-64 fall-through, and the loud `Error`.
`root-cause-over-microfix.md` calls three mechanisms for one concept a design flaw, so the fix
here is plausibly **deleting an arm rather than adding one**.

## Log
- 2026-08-29 — resolved, commit PENDING-COMMIT.

## Resolved 2026-08-29 — fixed as the shape, with three corrections to this ticket

All five chains in the file (`PXXSysOpenRO`, `PXXSysLseek`, `PXXSysClose`,
`PXXSysRead`, `PXXSysWrite`) converted from runs of separate `{$ifdef}` blocks
into single `{$if defined}/{$elseif}/{$else}` chains with a terminal arm.
Closes this and `bug-a-three-pxxsys-primitives-return-a-plausible-fd-on-wasm32`
together — one defect that was counted twice.

**Correction 1 — `{$error}` does not exist in this dialect,** so the fix this
ticket proposes cannot be written. The directive dispatcher in `lexer.inc`
handles `ifdef/ifndef/if/ifopt/elseif/else/endif/define/undef` and the strict-*
flags; there is no error/fatal/message. The ticket flagged this as "the first
thing to check" and it was, and the answer was no. `{$if defined(X)}`,
`{$elseif}`, `{$else}` and `not/and/or` all work, which is what made an
exhaustive chain possible at all. **The absent directive is the real missing
mechanism here** — with no way to refuse at compile time, every chain in the
tree can only fail to a defined-but-wrong value. Worth its own Track A ticket;
`lexer.inc` was outside this grant.

**Correction 2 — the armless set is larger than the ticket's table.** The file
header records that xtensa under IDF compiles the `{$ifndef PXX_ESP}` bodies
("riscv32 under IDF compiled all of them, which is the proof the bodies are
fine on an ESP target"). So open/lseek/close are reached with no arm on hosted
riscv32, on wasm32, AND on **xtensa/IDF** — three live targets, one of them
Track S's active campaign, not the two this ticket names.

**Correction 3 — `PXXSysWrite` is marked "fixed" in the table above and was
not.** Adding the wasm32 arm closed that instance and left the generator
running: its pre-chain `Result := 0` still meant an armless target reported
writing nothing *successfully*. `PXXSysRead` is the same, where 0 reads as EOF.
Both are converted here. This is the ticket's own prediction — "adding an arm
closes today's instance and leaves the generator running" — having already come
true once inside the ticket, unnoticed.

### Measured, per the playbook, not reasoned

`PXXSysOpenRO` IR on riscv32 (`PXXDBG=a.ir:PXXSysOpenRO`):

| | IR | meaning |
| --- | --- | --- |
| before | `IR count=1` — one empty `block` | body is EMPTY; `Result` never assigned |
| after | `IR count=4` — `const 1; neg; store Result` | `Result := -1` |

And frankwasm's reproducer from the sibling ticket, run end to end:

| | native x86-64 | riscv32 (no arms) |
| --- | --- | --- |
| `PXXSysOpenRO(nil)` | `-14` unchanged | `-1` (was: return-slot leftovers) |
| `PXXSysClose(7)` | `-9` unchanged | `-1` |
| `PXXSysLseek(7,0,0)` | `-9` unchanged | `-1` |

x86-64 is provably untouched by the first three chains: that build produced a
**byte-identical compiler** (`da54007a8f92`, equal to HEAD) because the else
arms are dead on the host. The read/write conversion does change the binary —
it removes the now-redundant pre-chain `Result := 0` dead store on every target
that has an arm. riscv32 keeps syscalls 63/64, confirmed by IR dump. 12 of 12
loadfile/readln/writeln assertions pass, i386 and aarch64 cross sites included.

### Why -1 rather than something louder

For these five, -1 is not a consolation for the missing `{$error}` — it is the
value they already signal failure with, and `PXXStrLoadFile`'s `if fd < 0 then
Exit` consumes it correctly. The routine now fails the way its own caller
already expects, instead of returning a plausible success.

### Explicitly NOT done

- **`HeapMmap` — UNGRANTED, untouched, unswept.** The sixth instance and the
  largest blast radius; stays on
  `bug-a-heapmmap-has-no-wasm32-arm-so-the-heap-starts-at-address-zero` [p70]
  under the owner's standing "both halves or neither" condition.
- **xtensa's `Result := 0` in read/write is preserved, not judged.** It was
  never chosen for xtensa — it was the default every unnamed target inherited.
  It is now an explicit arm, so the fall-open is gone, but whether 0 (EOF /
  "wrote nothing, successfully") is a lie on xtensa/IDF is **Track S's call**
  and is flagged in the source at both sites.
- The `{$error}` gap, and the `EmitZeroFrameSlot` narrow chain the correction
  above identifies — both outside `compiler/builtin/**`.

## Log
- 2026-08-29 — fixed as the shape, not a fifth arm; resolved. PENDING-COMMIT
