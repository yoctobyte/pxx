---
track: N
prio: 80
type: bug
---

# test-nilpy stopped at row 593 from 2026-10-02 on: a vacuous leak row

Found 2026-10-19. `make test-nilpy` exited at
`assert_no_leak.sh nilpy_lambda_captured`, which reported "only 49 allocations
— too few to show anything". It fails the same way at a clean HEAD
(7dbf6fe4df), so the cause was not the sysdash work. The recipe runs to Makefile
line ~8730, so **nearly the whole Nil Python suite had not run since the row
landed in 6f3a8bb040 (2026-10-02)**.

**Cause:** in the `leak` arm, the loop in
test/test_nilpy_a_lambda_returning_a_captured_heap_value_returns_it.npy only
returned borrowed names, so it allocated nothing per pass. assert_no_leak
rightly refuses a row that cannot show a leak. The `keep` control allocated
`[i]`, so the two arms were not measuring the same thing.

**Fix:** a fresh list per pass, returned through a lambda, dropped in the
leak arm and kept in the control (the sibling lamctor row's shape). The leak
arm is ok at allocs=13891 live=37, the control trips, and the HEAP_DEBUG row is
unchanged.

**Lesson:** a red row early in a long serial recipe hides every row after it,
and "the suite is red" read as one failure, not ~8000 unrun lines.
