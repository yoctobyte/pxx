---
track: A
prio: 55
type: feature
blocked-by: []
summary: "A nil receiver, a nil procvar call or a nil interface call dies as a raw memory fault today — on Linux via the MMU, on ESP not at all. Emit the check at the site instead: PXXNilRef + PXXNilRefHook, the fifth member of the PXXDivZero/Overflow/RangeError/IoError family, so sysutils upgrades it to a catchable EAccessViolation. The payload is catchability and a named line, not a nicer message."
status: backlog
owner: unassigned
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
