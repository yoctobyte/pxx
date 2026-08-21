---
track: A
prio: 55
type: feature
blocked-by: []
summary: "A nil receiver, a nil procvar call or a nil interface call dies as a raw memory fault today — on Linux via the MMU, on ESP not at all. Emit the check at the site instead: PXXNilRef + PXXNilRefHook, the fifth member of the PXXDivZero/Overflow/RangeError/IoError family, so sysutils upgrades it to a catchable EAccessViolation. The payload is catchability and a named line, not a nicer message."
status: done
owner: claude-A
---

# Emit nil checks at the site, so a nil deref is catchable

- **Track A** (codegen + `compiler/builtin/builtinheap.pas`; the RTL half is the
  one-line hook install in `lib/rtl/sysutils.pas`).
- Raised 2026-08-21 by the user while going over
  [[decide-segv-runtime-error-default]], which turned out to be conflating three
  separate things. This is the one with the value in it.

## Why this is not "a nicer message"

`--fpc-mem-errors` (landed 2026-08-21, `6b5bbd6cc`) turns a memory fault into
`Runtime error 216` and exit 216. That is mustard after the meal — the program
is already dead, the message names no line, and `try..except` never runs.

An **emitted** check is a different thing:

- it fires **before** the fault, at a site the compiler knows, so it can name
  the line;
- it is an ordinary call, so the hook can **raise** — `try ... except on E:
  EAccessViolation` works, with no unwinding out of signal context. This is the
  user's stated reason for wanting it: *"potentially some of those
  otherwise-segfaults would be catchable with an exception catcher, and that is
  genuinely useful."*
- it works on **targets that have no signals at all**. `EmitSignalRuntimeForTarget`
  gives xtensa no signal runtime on purpose, and skips riscv32 under
  `--esp-profile=bare`. So on the ESP32 family a check is not the better
  mechanism, it is the only one.

## The mechanism already exists — this is its fifth member

`builtinheap.pas` has a settled pattern: a trap routine with a proc-typed hook
slot, defaulting to nil = message + `Halt(n)` ("FPC-without-sysutils
behaviour"), which sysutils' `initialization` upgrades to a catchable raise.

| trap | hook | sysutils installs | raises |
| --- | --- | --- | --- |
| `PXXDivZero` (200) | `PXXDivZeroHook` | `SysRaiseDivByZero` | `EDivByZero` |
| overflow (215) | `PXXOverflowHook` | `SysRaiseOverflow` | `EIntOverflow` |
| range (201) | `PXXRangeErrorHook` | `SysRaiseRangeError` | `ERangeError` |
| `{$I+}` I/O | `PXXIoErrorHook` | `SysRaiseIoError` | `EInOutError` |
| **nil ref (216)** | **`PXXNilRefHook`** | **`SysRaiseAccessViolation`** | **`EAccessViolation`** |

`EAccessViolation` is already declared (`sysutils.pas:125`) and is currently
unused. So the runtime half is one trap routine, one BSS slot, one `SysRaise*`,
one line in `initialization` — no new machinery, no new design.

## Default-on, opt-out — `--no-div-check`'s model, not `--fpc-float-errors`'

The precedent that matters is the one already in the tree for a **compiler-emitted
check**: `NoDivCheck` (`defs.inc:3114`) — the pre-divide zero check is
**default-on**, `--no-div-check` opts out, and it prints a better message than
FPC. `{$rangechecks on/off}` + `PXXRangeChkI64` supplies the directive shape.

So: `{$nilchecks on/off}` directive, `--no-nil-check` command-line opt-out,
default on. `--fpc-float-errors` is not the precedent — that flag changes
*computation* (it unmasks FP exceptions, so a program that produced a NaN now
dies); a nil check changes only whether a program that was already dead dies
usefully.

## Where the checks go — the default follows the cost, not the taxonomy

The overhead is real and the user named it. It is also **asymmetric**, and the
default should be too. One mechanism, one directive; two different default
answers.

**Default ON — the call-shaped sites**, where a test+branch is noise next to the
call, and where the MMU catch is *worst* because control has already left:

- a method on a nil instance (virtual and non-virtual — the virtual case faults
  on the VMT load, the non-virtual one faults later, inside, on the first field
  touch, which is the plausible-wrong-value case this repo pays for);
- a call through a nil procedure variable or method pointer — this one jumps to
  address 0, so there is no faulting PC and no backtrace worth the name;
- a method call through a nil interface (the IMT load).

**Default OFF, directive-on — bare pointer derefs** (`p^`, `p^.f`). Here the
check is a load in a possibly-tight loop, and on the PC targets the MMU already
catches it for free. `{$nilchecks on}` turns them on for a unit or a region,
the way `{$rangechecks on}` already does.

Do NOT grow a second mechanism for the second case — see
`devdocs/dev/normalise-dont-special-case.md`. It is one `PXXNilRef` and one
directive; only the *default value* differs by site class.

## The action must be a hook, not a hardwired write (the ESP constraint)

Stated by the user: on an MCU, halting is generally not what you want, and
printing is usually fine **but not always** — a program driving a
protocol-sensitive serial link must be able to say "not on my UART". The hook
slot handles this by construction, exactly as `PXXDivZeroHook` does: default nil
prints and halts; a platform or a program installs its own (raise / log / reset
/ nothing). Bake `writeln` + `Halt` into the check site and the ESP profile
inherits a Unix decision it cannot undo.

## Scope and staging

x86-64 first, like every other member of this family, and say in the ticket
which arches are done rather than half-implementing five. **xtensa is the one
that most wants it** (no signals at all), so it is the natural second — not
last.

## Unmeasured, and worth measuring before committing the default

- The cost of the call-site checks on a real workload. The claim "noise next to
  a call" is an argument, not a measurement; the self-host build is the obvious
  subject, and `make compiler/pascal26` timing plus a `-O2` benchmark answers it.
- Whether the non-virtual-method case can be folded when the receiver is
  provably non-nil (`Self` in a method chain, a just-constructed object). If it
  can, most of the cost disappears and the default gets easier.

## Gate

`make compiler/pascal26` + self-host fixedpoint, `tools/gate.sh quick`. A test
per site class asserting **both** that the check raises a catchable
`EAccessViolation` with sysutils in, and that it prints `Runtime error 216` +
exit 216 without it — plus a `--no-nil-check` row asserting the raw fault is
back, in the shape `test_fpc_mem_errors.pas` already uses for its two directions.

---

## Landing 1 (2026-08-21): the runtime, plus the procvar site class

Staged deliberately, one site class per commit, each green on its own. This one
carries the whole runtime half, so the arms after it are call-site work only.

### Runtime — the fifth member, as designed

`builtinheap.pas`: `PXXNilRefHook` (BSS, nil by default), `PXXNilRef` (216 +
`Halt(216)` when the hook is nil), and `PXXNilChkPtr(p: Pointer): Pointer` — the
guard, which returns `p` unchanged unless it is nil.

`sysutils.pas`: `SysRaiseAccessViolation` + one line in `initialization`.
`EAccessViolation` was declared and unused; it now has something that raises it.

216 on purpose: it is FPC's code for a memory fault and what `--fpc-mem-errors`
reports for a real SIGSEGV, so the emitted check and the signal path agree on
the number a program exits with. What differs is everything else — this one
fires *before* the fault, from ordinary call context.

### The guard is pure Pascal, and that is the design decision

`IRWrapNilChk` wraps a call target in `PXXNilChkPtr(...)`, exactly as
`IRWrapChkBounds` wraps a value in `PXXRangeChkI64(...)`. So **every target is
done, not just x86-64** — including the ones the ticket says want it most
(xtensa has no signal runtime at all; riscv32 under `--esp-profile=bare` the
same), where an MMU fault is not a worse mechanism but an absent one.

The ticket said "x86-64 first, say which arches are done". The answer is all of
them, because the check never became machine code.

### Site class 1: a call through a nil procvar / method pointer

`AN_CALL_IND`'s callee, in `ir.inc`. The worst-behaved nil deref — the call
jumps to address 0, so there is no faulting instruction inside the program, no
frame, and a backtrace naming nothing.

### `--no-nil-check`, default on

`NoDivCheck`'s model, as the ticket argues, not `--fpc-float-errors`': a nil
check does not change what a working program computes.

### Measured, all three directions

| build | result |
| --- | --- |
| no sysutils | `before` / `Runtime error 216 (nil reference)`, exit **216** |
| `uses SysUtils` + `try..except on E: EAccessViolation` | caught, message printed, **program continues**, exit 0 |
| `--no-nil-check` | raw fault, exit **139** |

### Cost — measured, not argued

- **Self-host binary: +830 bytes on 8.79 MB (0.009%)**, and the fixedpoint still
  converges. The compiler barely calls through procvars.
- **Microbenchmark, 50M indirect calls in a tight loop, `-O2`: 0.41 s → 0.49 s.**
  That is ~1.6 ns per indirect call, i.e. the cost IS the call to the guard, and
  on a loop that does nothing else it is ~20%. On real code it is invisible; on
  a procvar-dispatch hot loop it is not, and saying so is better than repeating
  the ticket's "noise next to a call", which was an argument, not a measurement.
- Marking `PXXNilChkPtr` `inline` changed nothing measurable (0.49 → 0.48 s,
  inside noise), so the marker was removed rather than left as decoration.
  Removing the call needs an IR-level check node that backends lower to
  test+branch — recorded below as the follow-up, not done here.

### One existing test had to be told which mechanism it is testing

`test_fpc_mem_errors.pas`'s `nilproc` mode is now caught by the emitted check in
BOTH of its directions, so the row would have silently stopped testing the
signal path it names. Both of its compiles now pass `--no-nil-check`, with the
reason at the row. The same flag keeps its `nilmethod` mode honest when arm 2
lands.

### Still to do (this ticket stays open)

1. **Instance receivers** — a method on a nil object, virtual and non-virtual.
   `nilmethod` in `test_fpc_mem_errors.pas` is the waiting repro.
2. **Interface calls** — the IMT load.
3. **`{$nilchecks on/off}`** + the bare-pointer-deref class, default OFF. Needs
   a per-token flag (`TokNilChecks`), the shape `TokRChecks` already has.
4. **Folding provably-non-nil receivers** — the ticket's own open question, and
   where the microbenchmark cost above would go.

**Blocked, for arm 1's method-pointer half:** `ev := nil` on a
`procedure(...) of object` SEGFAULTS AT THE ASSIGNMENT — before any call — on
`pinned` as well as at HEAD, and regardless of `--no-nil-check`. Filed as
`bug-a-assigning-nil-to-a-method-pointer-segfaults`. The guard is already on
that path; it cannot be tested until a method pointer can be set to nil.

---

## Landing 2 (2026-08-21): the receiver site class — and the guard stops being a call

### Site class 2: a method on a nil instance

Both lowering paths, because they are genuinely two paths and either can regress
alone:

- `AN_VIRTUAL_CALL` — faults on the VMT load, so the MMU catches it today on a
  PC and nowhere else;
- the plain `AN_CALL` path — this is the one worth the ticket. A method that
  touches no field **ran to completion on a nil instance and returned normally**.
  Nothing faulted; the program carried on and misbehaved later somewhere else.
  That is exactly the plausible-wrong-value-far-from-the-cause shape
  `devdocs/dev/debugging-playbook.md` opens with.

The key is *"param 0 is named `Self`, is `tyClass`, and is not by-ref"*, not
`Name = 'Self'` alone. A **class** method's `Self` is a metaclass pointer
(`tyPointer`) and a record's / type helper's is by-ref; wrapping either is wrong,
and the name-only key would have wrapped every `class function` in the tree.
`test_nil_check_receiver.pas` carries a `class function Make` for precisely this.

### The guard is no longer a call, and the pure-Pascal claim above is now wrong

Landing 1 wrapped the pointer in `PXXNilChkPtr`, mirroring `IRWrapChkBounds` /
`PXXRangeChkI64`. That is the nicer code and it does not survive contact with a
receiver check, because a receiver check is on *every method call*:

| shape | 60M method calls, `-O2` |
| --- | --- |
| baseline (no checks) | 0.42 s |
| guard as a call (`PXXNilChkPtr`) | **0.65 s** (+48%) |
| guard as inline IR (test + branch) | **0.43 s** (+2%) |

`inline` does not rescue the call form: inline v1 (`inline_expand.inc`) retains
only single-expression bodies with **no call in them**, and the call is this
body's entire purpose. So `IRWrapNilChk` now builds the compare and the
conditional branch as IR at the site and leaves only the cold arm (`PXXNilRef`)
in a routine. `PXXNilChkPtr` is deleted, with the measurement recorded in
`builtinheap.pas` where it stood, so the next reader does not re-derive it.

Landing 1's *"the check never became machine code, so every target is done"*
is therefore superseded: it is IR now, which lowers on every backend anyway —
the portability conclusion holds, the reasoning for it does not.

### Cross-lane fallout, and the gate hole it exposed

Landing 1 added `PXXNilRefHook` to `builtinheap.pas` and used it from
`lib/rtl/sysutils.pas`. `stable_linux_amd64/default/builtin/` holds a **frozen**
copy of the builtin sources, so from `97b1812fe` until the v369 pin every
`$(PXX_STABLE)` build — all of Track B/D/E, `make lib-test`, `make demos` —
failed with `undefined variable (PXXNilRefHook)`. `tools/gate.sh quick` was green
throughout and structurally cannot see this: it never builds anything with the
pinned binary. Filed as [[bug-t-gate-quick-cannot-see-a-broken-pinned-rtl]].

### Not covered yet

- **Interface method calls** (the IMT load) — arm 3.
- **Bare pointer derefs** behind `{$nilchecks on}`, default off — arm 4.
- **Intrinsic-ish members on a nil instance**: `p.ClassName` still segfaults,
  because it lowers to a direct VMT/field read rather than to a call with a
  `Self` param, so neither arm-2 key sees it. Same class as arm 4.
- **Folding provably-non-nil receivers** (`Self` inside a method, a
  just-constructed object). At +2% the pressure to do this is now low.

---

## Landing 3 (2026-08-21): the interface site class

`AN_INTF_CALL`, one line, and the interesting part is **where** the check goes.

An interface VALUE is a single pointer — the instance — and the IMT is resolved
from it at the call by `PXXIntfIMTOf(self, ci)`, which walks the instance's RTTI
blob. So a nil interface did fault today on a PC, but *inside a runtime helper*:
the faulting PC named `PXXIntfIMTOf`, several frames from the `i.Go` the
programmer wrote. Checking the instance pointer before the helper call is what
moves the report back to the call site — and on a target with no signal runtime
it is the difference between a diagnosis and nothing at all.

COM and CORBA interfaces share this path (they differ in refcounting, not in
call lowering), so both are in the test rather than argued about.

| build | result |
| --- | --- |
| default | `caught proc` / `caught func` / `caught corba`, program continues, exit 0 |
| `--no-nil-check` | raw fault, exit **139** |

No measurement for this one, deliberately: the site already contains a call to
`PXXIntfIMTOf`, so a test-and-branch in front of it cannot be a meaningful
fraction of it. Test: `test/test_nil_check_interface.pas`.

---

## Landing 4 (2026-08-21): `{$NILCHECKS}` and the bare-deref site class

This closes the ticket's design, including the part it warned against
duplicating: *"do NOT grow a second mechanism for the second case ... only the
default VALUE differs by site class."*

### The directive is tri-state, and that is the whole design

Every other check directive here (`{$R}`, `{$Q}`, `{$I}`) stamps a **Boolean**
per token. `{$NILCHECKS}` stamps `NILCHK_DEFAULT / _ON / _OFF`, because one
directive governs two site classes whose defaults **disagree**:

| site class | default | reason |
| --- | --- | --- |
| call — nil receiver / procvar / interface | **on** | +2% measured; the fault it replaces lands frames from the call, or (no signal runtime) nowhere |
| bare `p^` | **off** | a test inside whatever loop the deref is in; on a PC the MMU already reports it at the right instruction |

A Boolean cannot represent *"the author said nothing"*, which is precisely the
state those two defaults disagree about — so a Boolean would have forced either
two directives or two flags, i.e. the second mechanism the ticket forbids.
`NilChkWanted(astNode, defaultOn)` resolves the three-way state against the
site's default in **one** place; the five call sites pass their default and
nothing else knows the rule. `--no-nil-check` stays the master off for both.

Plumbing follows `{$R+}`'s exactly: `NChecksVal` (lexer state) → `TokNChecks`
(per token) → `StmtNChecks` (anchored at the **statement's first token**, so a
directive between the RHS and the statement end cannot retro-apply) → `ASTNilChk`
(stamped in `AllocNode`, copied by `CloneAST`).

### Site class 4 is ONE line, because the address path is already normalised

`IRLowerAddress`'s `AN_DEREF` arm. Reads, writes and bases (`p^`, `p^.f`,
`p^[i]`) all route their address through it — `IRLowerDestAddress` delegates to
it and the `AN_INDEX, AN_FIELD, AN_DEREF` value arm calls it — so there was no
double case to find a sibling for. That is `normalise-dont-special-case.md`
paying out rather than being applied.

### Cost of the OFF-by-default class, measured anyway

200M `p^` reads in a `-O2` loop that does nothing else: **0.630 s → 0.668 s
(+6%)**, and code grows 58,093 → 68,803 bytes (the reporting machinery is pulled
in whole). 6% is far less than expected for a per-iteration test, and is still
the right default-off: the number to compare it against is 0, and the PC targets
get the MMU's answer free.

### FPC seed

The new call site is at `ir.inc:1770` and the function is defined ~2,800 lines
later; pxx accepts that and the FPC seed does not, so `IRWrapNilChk` now has a
forward next to `IRMaterializeIntfCast`'s
(`bug-a-fpc-seed-drift-emitasmx64-forward`). The gate caught it — the FPC seed
canary is the only step in `gate.sh quick` that would have.

Test: `test/test_nil_check_directive.pas` — all four corners in one program
(deref default unchecked, deref `{$nilchecks on}` read **and** write raising,
call default checked, call `{$nilchecks off}` **not** checked).

### Status: all four site classes are in

Remaining, and both are optimisations rather than coverage:

- fold provably-non-nil receivers (`Self` inside a method, a just-constructed
  object). At +2% the pressure is low.
- `p.ClassName` and friends still fault: they lower to a direct VMT read, not to
  a call with a `Self` param, so no arm's key sees them. Filed separately if it
  ever bites — it is the same shape as class 4 and would want the same default.

## Log
- 2026-08-21 — resolved, commit 3217f6954.
