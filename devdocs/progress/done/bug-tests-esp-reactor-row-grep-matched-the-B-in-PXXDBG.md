---
track: N
prio: 40
type: bug
---

# esp_reactor_is_pointer_width row: its grep matched the B in "PXXDBG"

Found 2026-10-19 in the full row sweep. `grep -o '[0-9]*B'` over the line
`PXXDBG a.datamap   bss 2920B  reactors` printed `B` (zero digits, from
"PXXDBG") as well as `2920B`, so expect_same saw two lines and failed while the
value was right. The row was added in 68f3931050 (2026-10-09), after the recipe
had already started stopping at row 593, so it never ran green.

**Fix:** `grep -o '[0-9][0-9]*B'`.
