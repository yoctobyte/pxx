---
track: U
prio: 25
type: decide
blocked-by: []
summary: "pxx evaluates Assert() by default; FPC ignores it unless -Sa. So Assert(False) raises EAssertionFailed here and is a no-op there — code that passes its own test suite under FPC can die under pxx, and vice versa. With -Sa the two agree exactly, so this is purely a question of which default we want. Options: keep ours, match FPC, or add {$ASSERTIONS}/-Sa and pick a default."
---

# Assertions are on by default here and off by default in FPC — which default do we want?

- **Type:** decision (Track U) — no code is wrong today; the question is which
  behaviour we commit to.
- **Status:** decided
- **Opened:** 2026-08-21, from the exception-semantics differential in
  `bug-a-unhandled-exception-exits-1-not-217`.

## The fork

```pascal
try
  Assert(1 = 2, 'assertmsg');
except
  on e: Exception do WriteLn('c:' + e.ClassName);
end;
WriteLn('end');
```

| compiler | output |
| --- | --- |
| `fpc -Mobjfpc` (default) | `end` |
| `fpc -Mobjfpc -Sa` | `c:EAssertionFailed` / `end` |
| `pxx` (default) | `c:EAssertionFailed` / `end` |

So pxx's behaviour is exactly FPC-with-`-Sa`, and the *only* difference is which
way the switch points when nobody touches it. FPC's default is `{$C-}`
(assertions off); Delphi's is off in Release and on in Debug.

## Why it is worth a ruling rather than a default guess

It cuts both ways, which is what makes it a decision and not a bug:

- **Ours is the safer default.** An assertion that silently evaporates is a
  check the author believed they had. Code arriving from an FPC project has
  been *developed* with its assertions inert, so pxx is the first compiler that
  ever ran them — and it will find real bugs, and also fire on assertions that
  were wrong all along and never noticed.
- **Theirs is the compatible default.** Under the compat tag's rule ("behave
  like the reference implementation"), a program that FPC accepts and runs
  must run here. A third-party unit whose stale `Assert` is false now halts a
  program that works fine under FPC. That is exactly the upward-compatibility
  direction the N track spells out for CPython, applied to P.

## Options

1. **Keep assertions on by default.** Zero work. Accepts that some FPC code
   dies here with a diagnosis FPC would have skipped. Document it as a
   deliberate dialect divergence.
2. **Match FPC: off unless asked.** Maximum compat, and it silently disarms
   assertions in code written *for* pxx — the failure mode that is invisible
   until it matters.
3. **Implement the switch and then choose.** Add `{$ASSERTIONS ON/OFF}` /
   `{$C+}` / `{$C-}` and `-Sa`, so either default is a one-line change and
   per-unit control exists. Then pick a default (recommendation: keep ON, and
   let `--strict-*`-style compat flags turn it off with the rest of the
   FPC-parity switches). This is the only option that leaves the user in
   control, and it is small.

**Recommendation: option 3, defaulting to ON.** The switch is worth having on
its own merits, and once it exists the default stops being a one-way door.

## Notes

- Nothing else about assertions diverges: the class raised
  (`EAssertionFailed`), catchability, and the message all match.
- If option 2 or 3 lands, the conformance sweep (`pxx.skip`'s `dialect-pass`
  entries) is where the FPC-parity spelling belongs, per the compat tag.

---

# DECIDED 2026-08-25 — **option 3: implement `{$ASSERTIONS}` / `{$C±}` / `-Sa`, default ON**

Decided by an agent under the no-human-available rule
(`devdocs/progress/decided/README-agent-decisions.md`). **Derived** — the
dialect contract already specifies this shape for every divergence, so there was
less to decide here than the ticket assumed.

`meta-dialect-extensions-and-fpc-strict`, the contract every extension follows:

> *"1. **Be available by default** (lenient) or behind an explicit opt-in switch
> — never silently mandatory. 2. **Be disabled / rejected under the strict
> family** (`--strict` / `--mimic-fpc` / the relevant `{$...}` strict
> directive), so a strict compile is FPC-faithful."*

Assertions-evaluated-by-default is a divergence from FPC in pxx's favour, so by
clause 1 it is a legitimate default and by clause 2 it must be switchable off
under the strict family. That is option 3 with the default ON, spelled out in
advance. Options 1 and 2 each drop one of the two clauses.

## What settles the ticket's own framing

The ticket presents this as "ours is safer versus theirs is compatible" and
treats it as a one-way door. It is not a door at all once the switch exists —
which is why the contract asks for the switch *first*. The recommendation was
already right; what was missing was noticing that it is mandated rather than
preferred.

## Direction of the default, since clause 1 permits either

ON. An assertion that silently evaporates is a check the author believed they
had, and code written *for* pxx would be the population harmed by a silent
default-off — a failure mode invisible until it matters. The compat direction is
served exactly and losslessly by the flag: `-Sa`-off is bit-identical to FPC's
default, so no FPC program is denied a way to build.

## The upward-compatibility objection, and why it does not carry

The ticket invokes the N-track rule ("a program the reference accepts and runs
must work here") applied to P. That rule is stated for **NilPy** specifically, in
`frontend-compat-philosophy.md`, and the same document explicitly says Pascal
does **not** inherit it: *"This is the one most likely to be got wrong, because
it inverts the usual instinct."* Borrowing N's rule into P is the exact confusion
the philosophy doc was written to stop.

That said, the concern behind it is real and cheap to answer: `--mimic-fpc`
should imply assertions-off along with the rest of the FPC-parity switches, so
a corpus build gets FPC's behaviour without naming this flag. Folded into the
work below.

## Scope note

`{$C+}`/`{$C-}` and `{$ASSERTIONS ON/OFF}` are the same switch under two
spellings; per-unit granularity is what makes the switch worth having beyond a
default flip. Contract clause 4 applies: a test on both sides — the assert fires
in the default dialect, and the same source is a no-op under `-Sa`-off.

## Re-filed as work

Track **P**: `feature-p-assertions-switch-and-strict-default`, prio 30 —
implement `{$ASSERTIONS ON/OFF}`, `{$C±}` and `-Sa` (default ON), wire
`--mimic-fpc` to turn it off, and add the `pxx.skip` `dialect-pass` entry so the
conformance sweep runs with FPC's polarity.

## Log
- 2026-08-25 — decided, commit 28c19f214.
