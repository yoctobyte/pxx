---
slug: bug-s-a-direct-call-to-an-interrupt-routine-is-the-same-trap-return-fault-by-another-spelling
track: S
type: bug
prio: 35
status: backlog
owner: ""
created: 2026-09-21
found-by: frankb-8e
blocked-by: []
summary: "The SIBLING SPELLING of the refusal landed in `d305e1afa`, split out rather than closed with it because refusing it needs a design decision and not a predicate. A routine declared `interrupt;` returns via a trap-return (riscv32 `mret`, xtensa `rfe`), so ANY normal entry into it is a fault -- and `@f` is not the only normal entry. A DIRECT CALL, `MyIsr;`, is the same fault and is still accepted with no diagnostic. It is ranked well below its `@proc` sibling on likelihood rather than on severity: the `@proc` form is the natural esp_intr_alloc idiom and a reasonable person writes it by accident, whereas calling an ISR by name is visibly odd. THE OBSTACLE IS NOT THE PREDICATE, WHICH IS ONE LINE BESIDE THE EXISTING ONE -- it is that test/test_esp_interrupt.pas RELIES on a direct call (behind a runtime-false guard, `if counter < 0 then MyIsr;`) as its only way to force the handler body to be emitted, and a structural probe needs some way to do that. So refusing this arm requires an emission-forcing mechanism first: a `{$KEEP}`-style directive, an export, a reference that is not a call, or making `interrupt;` bodies unconditionally retained by DCE. That choice is the ticket. Whoever takes it should decide the mechanism before writing the refusal, because a refusal landed without one breaks the only fixture that proves the ISR codegen is emitted at all."
---

# A direct call to an `interrupt;` routine is the same fault by another spelling

## Why it is filed separately rather than left in a comment

`d305e1afa` refused `@<interrupt proc>` at the AN_PROCADDR convergence point.
That closes the arm anyone hits by accident. It does **not** close the class,
and this repo's own `normalise-dont-special-case` rule says the sibling is
usually a *spelling* rather than a shape — which is exactly what this is. The
code comment in `ir.inc` names it, but a comment is read by whoever is already
editing that function; the point of a ticket is to be found by someone who is
not.

## The mechanism, restated so it does not depend on the sibling ticket

`interrupt;` emits a raw trap routine whose epilogue is `mret` (riscv32) or
`rfe` (xtensa). Those pop privilege state and resume through the machine
exception PC. Entered by a normal `jalr`/`callx`, there is no trap frame to
return through and the caller's return address is never consulted. Nothing
diagnoses it at any stage.

## The actual obstacle

`test/test_esp_interrupt.pas` is a structural probe: it must get `MyIsr`
EMITTED so the prologue/epilogue and `.iram1.text` placement can be inspected,
without ever executing it. Its only lever today is a call behind a
runtime-false guard:

    if counter < 0 then MyIsr;   { never true; forces emission }

Refuse direct calls and that fixture has no way to do its job — and it is the
fixture that proves the ISR codegen exists at all.

## So the ticket is the mechanism, not the refusal

Pick one, then the refusal is trivial:

- a `{$KEEP}` / `{$USED}` directive, or an existing equivalent if one exists
  (**grep before adding one** — this repo has a standing instance of proposing
  a mechanism that already existed under another name);
- exporting the routine, if that already pins a body;
- **making `interrupt;` bodies unconditionally DCE-retained**, which is
  arguably correct on its own terms: a handler's only legitimate caller is
  hardware, so DCE can never see a reference to it and *every* such body is
  reachable-in-fact and unreachable-in-graph. This is probably the right
  answer and it deletes the problem rather than working around it.

**Positive control when it lands, both arms:** a direct call to an `interrupt;`
routine must be REFUSED, and `test_esp_interrupt.pas` (rewritten onto whatever
mechanism is chosen) must still compile AND still emit `MyIsr` — assert the
symbol is present in `.iram1.text`, not merely that the file compiled, or the
new mechanism can silently do nothing and the row still passes.

## Related

- `bug-s-an-interrupt-directive-proc-reached-through-a-normal-call-returns-via-mret-with-no-diagnostic`
  — the `@proc` arm, fixed in `d305e1afa`.
- `devdocs/dev/esp32-hardening-map.md` §1.2.
