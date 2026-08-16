---
summary: "Pascal `for` lowering had three defects in one shape: the limit expression was re-evaluated every iteration, a limit at the counter type's maximum looped forever, and the counter was left at limit+/-1 instead of FPC's limit"
type: bug
prio: 65
track: A
---

# `for` loop: limit re-evaluated per iteration; infinite loop at the type maximum

- **Type:** bug (IR lowering — `AN_FOR` in `compiler/ir.inc`). Track A; affects
  every frontend that lowers to `AN_FOR` (Pascal `for`, NilPy `for i in range(...)`)
  and every backend, since the defect is in the shared IR shape.
- **Status:** done
- **Found:** 2026-08-16, Pascal oracle sweep vs `fpc -O- -Mobjfpc` (loops /
  ordinal ranges topic).
- **Related:** the case-selector defect had the identical cause and fix
  (a value node is a subtree the backend re-emits per use, so it must be
  materialised into a temp) — see the `EVALUATE THE SELECTOR EXACTLY ONCE`
  note in `AN_CASE`. `devdocs/dev/normalise-dont-special-case.md`.

## Symptoms — three faces of one lowering

The loop was lowered with the test at the TOP and the limit value node used as
an operand of that test:

```
i := init;  limit := <expr>
start:  if not (i <= limit) goto end
        body
cont:   i := i + 1
        goto start
end:
```

1. **The limit ran once per iteration.** A value node is not a register; each
   backend re-emits its subtree at every use, and the only use sat inside the
   loop. `for i := 1 to Limit do` called `Limit` **4** times for 3 iterations
   (FPC: 1). Worse, a limit that is a plain *variable* was re-read, so
   `n := 3; for i := 1 to n do begin inc(k); n := 0; end` ran **1** iteration
   where FPC runs 3.
2. **A limit at the counter type's maximum looped forever.** `i + 1` wraps to
   the type minimum and `i <= limit` is true again. Every one of these hung with
   no output — the idiomatic `for c := #0 to #255`, `for b: byte := 0 to 255`,
   `for w: word := 0 to 65535`, `for si: shortint := -128 to 127`,
   `for b := 255 downto 0`, `for i := 2147483645 to 2147483647`.
3. **The counter's post-loop value was `limit +/- 1`.** FPC leaves it at the
   limit: `for i := 1 to 5` ends with `i = 5` (pxx: 6), `for i := 5 downto 1`
   ends with `i = 1` (pxx: 0), `for b := 250 to 254` ends with `b = 254`
   (pxx: 255).

Nothing here crashes; (1) and (3) are silent wrong values, which is why the
existing tests never spelled it. (2) is a hang, and only at a boundary no test
happened to iterate to.

## Fix

`compiler/ir.inc`, `AN_FOR`: adopt FPC's shape — entry test once, per-iteration
test at the BOTTOM, comparing for **equality** with the limit so the increment
never runs on the last iteration and therefore can never overflow. The limit is
materialised into a hidden temp unless it is an `IR_CONST_INT` (that exemption
keeps the ordinary `for i := 1 to 10` byte-identical):

```
i := init;  tmp := <limit expr>          { once }
        if not (i <= tmp) goto end       { entry test, once }
start:  body
cont:   if i = tmp goto end              { exit BEFORE incrementing }
        i := i + 1
        goto start
end:
```

## Residual (deliberate, not a regression)

A **zero-iteration** loop leaves the counter at `init`; FPC leaves it untouched
(`i := 99; for i := 3 to 1 do ;` -> FPC 99, pxx 3). ISO Pascal says the counter
is undefined after the loop, and FPC's value is an artifact of holding the
counter in a register — matching it would mean pre-testing before the store,
i.e. a second temp for the init expression. Not worth it; recorded here so the
next sweep does not re-file it.

## Gate

`make compiler/pascal26` (fixedpoint, converged in 2 rounds) + the probes above
diffed against `fpc -O- -Mobjfpc` (all now match) + `tools/gate.sh quick` GREEN.
