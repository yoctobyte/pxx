---
prio: 70
track: T
status: done
owner: frankA
---

> **Track T by default: the FAILING STEP named no owner.** Line 16 of 5 is `./compiler/pascal26 /tmp/rust_unity.rs /tmp/test_rust_unity26`. The job's own `src` (`test/test_rust_module_items.rs`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_rust_module_items.rs at 99af5f3270cf in step 16/5, `./compiler/pascal26 /tmp/rust_unity.rs /tmp/test_rust_un` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-08-31T15:49:17Z
- **Test source:** test/test_rust_module_items.rs tools/expect_same.sh +1
- **Failing step:** line 16 of 5 of the job's recipe; it names no source file of its own — so it is the JOB's sources, one line up, that are unproven here, not this step's.
  ```
  ./compiler/pascal26 /tmp/rust_unity.rs /tmp/test_rust_unity26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_rust_module_items.rs'` at 99af5f3270cfd1a2f36857c6d46bc5863a21d6e8

## Range
> **The named sha `99af5f3270cf` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `99af5f3270cf`, last good `2bdb3c4ef3f6`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:41: error: Unsupported operator in IR codegen
(tail)
ok: /tmp/testmgr-scratch-2230407/test_rust_mitems26  [code=3864B  data=560B  bss=33619B  procs=4]
pascal26:41: error: Unsupported operator in IR codegen
  near:    n   >>>  Board  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

---

## Confirmed live at HEAD 763233473 (frank-rust, 2026-08-31) — measurement only, ticket NOT claimed

Still RED. Not stale, not already-fixed, not a load flake.

- Binary: `compiler/pascal26` sha256 `f92c42a698509b6112d882bac1097efd63b1eefed50e960d6c2bad9e77e320a1`,
  built by `make compiler/pascal26` → `converged after 2 round(s)`, self-host fixedpoint verified.
- Repro, no testmgr needed:
  ```
  cat test/rust_unity/*.rs > u.rs && ./compiler/pascal26 u.rs out
  pascal26:41: error: Unsupported operator in IR codegen
    near:    n   >>>  Board
  ```

**Do not read `>>>` as a shift operator — it is the error printer's position
marker.** Current token is `Board`, previous token is `n`. There is no `>>>` in
any of the four sources (`grep '>>'` finds one line, `(b >> i)` in `attacks.rs`,
which is not this). Taking this as a member of the SHR family is the obvious
wrong turn and costs a session; it is the same identifier-standing-in-for-the-
thing shape CLAUDE.md's *The name is not the thing* is about.

**Location.** Line 41 of the concatenation is `pub struct Board {` — the first
token of `board.rs`, i.e. immediately after `attacks.rs` ends on `return n; }`
and the `//!` inner-doc block plus `use crate::attacks::knight_from;` are
consumed. That is why the previous token is `n`: everything between was skipped
or dropped.

**The defect is in the concatenated/module path, not in any one file.** Compiled
alone, each of the four fails only for its expected standalone reason, and none
of them with this error:

| file | alone |
| --- | --- |
| `attacks.rs` | `Rust: no fn main() found` |
| `board.rs` | `Rust: no fn main() found` |
| `movegen.rs` | `Rust: unknown type Board` |
| `main.rs` | `Rust: no associated fn Board::new` |

**Lane is still open and I did not guess it.** The header's Track T is the
watcher's fallback. The error string is emitted by IR codegen (suggesting A) but
is reached through the Rust frontend's module/`use` handling (suggesting R), and
nothing measured here separates the two — whoever takes it should localise that
first rather than inherit either letter from this note.

Recorded and parked under the 2026-08-31 concurrency cap (2-3 active agents);
no code touched, no claim taken.
- 2026-09-01 — resolved, commit PENDING-COMMIT.
