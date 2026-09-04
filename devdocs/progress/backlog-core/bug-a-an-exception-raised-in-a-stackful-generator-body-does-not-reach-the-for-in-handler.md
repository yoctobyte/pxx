---
track: A
prio: 65
type: bug
blocked-by: []
summary: "An exception raised inside a STACKFUL (`generator;`, coroutine) body does not propagate to the `for..in` that is driving it: the program dies with `Unhandled exception` even though the loop sits inside a try/except that catches the same raise from a plain procedure and from a `generator; stackless;` body. Measured 2026-09-04; three-way control in the body."
status: open
---

# An exception in a stackful generator body never reaches the for-in's handler

- **Track A.** Measured 2026-09-04 by frankb-78 while trying to measure
  `bug-a-a-generator-body-raising-past-a-managed-temp-is-not-covered-by-the-unwind-landing-pad`.
  It is why that ticket's measurement is stackless-only.

## The three-way control

Same `Once` in all three — `try ... except on E: Exception do Inc(caught) end`,
run 3 times, `gmsg` a global AnsiString:

| what raises | result |
| --- | --- |
| a plain `procedure Plain` called inside the try | `caught=3` |
| `function Gen(n): Integer; generator; stackless;` driven by `for x in Gen(1)` | `caught=3` |
| `function Gen(n): Integer; generator;` (stackful, coroutine) — same source otherwise | **`Unhandled exception: Exception: helloA`**, process dies on the first iteration |

The try is the same try, the raise is the same raise, and only the generator
form changes. This is not the handler failing to match.

## Why it is plausible on this path and not the other

A stackful generator body runs on its OWN coroutine stack and is entered by
`CoSwitch` `ret`ing into it rather than by a call. The exception chain head is
per-thread (`EXC_TOP`), so a raise on the coroutine stack walks a chain whose
frames belong to the consumer's stack — there is no handler on the generator's
own stack, and whatever it finds is not reachable by the unwind it then
performs. A stackless step function is an ordinary call on the ordinary stack
and has none of this.

## What this blocks

- The unwind-landing-pad ticket above could only be measured for the stackless
  form; the stackful frame's behaviour is **UNCHECKED**, not fine.
- `bug-a-a-generator-instance-is-not-freed-when-an-exception-escapes-the-for-in`
  likewise.

## The guard this needs

The three-way control above, as a test, once it is fixed — the stackful row is
the guard and the other two are the controls that say the harness works. Note
that the failure is a process death, so a value assertion catches it without
any census.
