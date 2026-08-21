---
track: U
prio: 45
type: decide
blocked-by: []
summary: "NARROWED 2026-08-21. The nil-detection half left as feature-a-emitted-nil-checks; what remains is only what the SIGSEGV handler does for the faults a check cannot catch (wild pointers, stack overflow). Fork is no longer default-on vs opt-in but report-and-RE-RAISE (message + core dump + exit 139, default-on) vs report-and-exit-216 (FPC parity, no core dump). Plus: should --mimic-fpc imply --fpc-mem-errors and --fpc-float-errors?"
status: backlog
owner: unassigned
---

# What should the SIGSEGV handler do — re-raise, or exit 216?

- **Track U** — a decision, not work. The mechanism landed 2026-08-21 as
  `--fpc-mem-errors` (`6b5bbd6cc`, x86-64, opt-in); only the default is open.

## Narrowed 2026-08-21 (user)

The original ticket asked "default-on or opt-in?" over a single mechanism. Going
over it, the user pointed out it was three things wearing one hat:

1. **Detecting the nil references we can see** — a call on a nil object, a nil
   procvar. That is emitted-check plumbing, it is where the value is, and it is
   now its own ticket: [[feature-a-emitted-nil-checks]]. *"Potentially some of
   those otherwise-segfaults would be catchable with an exception catcher, and
   that is genuinely useful."*
2. **Catching the signal and printing nicely** — *"mustard after the meal"*.
   This ticket, and only this.
3. **A catchable `EAccessViolation` from signal context** — tier 2 of the parent
   bug, its own sitting, and largely dissolved by (1): the common shapes are
   caught at the check site before a signal exists.

Doing (1) makes (2) *less* worth defaulting on, not more — the faults left over
are wild pointers and stack overflows, which are exactly the cases where a core
dump is the thing you want. That inverts the original recommendation.

## The fork, as it now stands

The landed stub notes that returning from a SIGSEGV handler resumes the faulting
instruction forever. That means a third shape the original write-up never
considered: **reset the disposition to `SIG_DFL`, then return** — the fault
re-executes, the kernel default applies, and you get the message *and* the core
dump. The choice was never message-xor-core.

- **(A) Report and re-raise — default-on.** Message names the fault kind
  (`access violation: address not mapped` vs SIGBUS's own), then the process
  dies on the default disposition: **core dump preserved, exit 139**. Costs
  nothing but ~200 bytes and the two install syscalls. What it does not buy is
  FPC's exit code, because 139 is the honest one here.
- **(B) Report and exit 216 — stays behind `--fpc-mem-errors`.** FPC's exit-code
  convention for harnesses that key on it. No core dump. This is what shipped.
- **(C) Do nothing; leave the default a bare `Segmentation fault`.** Defensible
  — the shell already prints that, and the program is faulty either way. Weakest
  where there is no shell to print it.

## Recommendation

**(A) as the default, (B) as what `--fpc-mem-errors` promotes it to.** It gives
the out-of-the-box message without spending the core dump, which is what this
repo actually debugs with (`devdocs/dev/debugging-playbook.md`: measure, do not
reason — a core dump is measurement). Pure FPC parity is an exit-code
convention, which is a parity audience, which is what the flag is for.

## Second, smaller question in the same place

**Should `--mimic-fpc` imply `--fpc-mem-errors` and `--fpc-float-errors`?** It
is already the "behave like FPC" umbrella (`compiler.pas:750`, calling
`EnableStrictFpc`) and today implies **neither**. So a user who asked to mimic
FPC still gets exit 139 and quiet IEEE floats. Either the umbrella should cover
them or the flags should say why they are outside it; the current split is not
a decision anyone made. Recommendation: fold both in — the flag names literally
begin with `fpc-`.

## Not asked here

- Whether emitted nil checks are default-on — that is
  [[feature-a-emitted-nil-checks]]'s own question.
- Stack overflow reporting 216 where FPC reports 202 — recorded in the parent
  bug, worked out in
  [[decide-should-a-stack-overflow-raise-estackoverflow-by-itself]].
- Tier 2 (`EAccessViolation` raised from signal context) — parent bug, own
  sitting.

## If A is chosen

The Makefile row in `test/test_fpc_mem_errors.pas` asserts both directions
today (216 with the flag, 139 without) precisely so a default flip shows up as a
failing row rather than a silent change. Under A the no-flag row keeps exit 139
and gains the message, so it is an edit to the expected output, not a deleted
assertion. Release-note the new default line on stderr.
