---
track: A
prio: 40
type: bug
blocked-by: []
summary: "A typed const array is emitted as BSS plus generated code that fills it element by element at startup, instead of being stored as initialised data. Measured at ~29 bytes of code per element for UInt64; Int64, Double and Cardinal all do it too, so it is every typed const array, not a 64-bit case. A 696-entry table costs 20 KB of code and 0 bytes of data. A string constant of the same bytes costs ~0 code and lands in .data, so the data path exists — the array lowering just does not use it."
status: done
owner: claude-A
---

# A typed const array is built by startup code, not stored as data

- **Type:** bug (codegen / const lowering) — **Track A**.
- **Filed:** 2026-08-19 by frank3-b, from
  [[bug-b-strtofloat-is-3600x-slower-than-cpython-for-small-exponents]], where
  Eisel-Lemire's 696-entry power-of-ten table cost **+42 KB of code** in every
  binary that links `sysutils` — about 31 KB more than the table's own bytes.

## The bug

A typed constant array does not become initialised data. It becomes a BSS
reservation plus generated code, one store per element, run at program start.
Cost measured at **~29 bytes of code per element** for `UInt64`, plus the
startup time to run it, in **every** binary — including one that never reads
the array.

**Not specific to 64-bit types.** Same 696-element shape, same result — `data`
never moves and the storage is uninitialised BSS:

| element type | code delta vs 1-element | data | bss delta |
| --- | --- | --- | --- |
| `UInt64` | +20,152 | unchanged | +5,560 (695 x 8) |
| `Int64` | +16,680 | unchanged | +5,560 |
| `Double` | +20,228 | unchanged | +5,560 |
| `Cardinal` | +15,986 | unchanged | +2,776 (694 x 4) |

## Repro — two programs differing only in element count

```pascal
program tsz0;
const T: array[0..0] of UInt64 = ($1);
var s: UInt64; i: Integer;
begin s:=0; for i:=0 to 0 do s:=s+T[i]; writeln(s<>0); end.
```

versus the same with `array[0..695]` and 696 literals.

| | code | data | bss |
| --- | --- | --- | --- |
| 1 element | 54,204 | 1,560 | 9,512 |
| 696 elements | 74,356 | 1,560 | 15,072 |
| delta | **+20,152** | **0** | +5,560 |

`+5,560` bss is exactly `695 * 8`, so the storage is reserved but uninitialised;
`data` does not move at all; and `+20,152` code over 695 extra elements is
**29 bytes per element** of fill-in-at-startup.

## The data path exists — a string constant uses it

The same 5,568 bytes written as an `AnsiString` constant of `#nn` escapes:

| | code | data |
| --- | --- | --- |
| baseline | 54,204 | 1,560 |
| 696 u64 as a string const | 54,217 | 7,144 |

**+13 bytes of code and +5,584 of data.** So the backend can and does place
constant bytes in `.data`; the typed-array lowering simply does not take that
route.

## Why it matters beyond one table

Any lookup table — CRC tables, codec tables, trig tables, the power-of-ten
table that prompted this — pays 4x its own size in code and a startup pass. It
also puts a real thumb on the scale against writing table-driven code at all,
which is the wrong incentive: the natural, readable spelling is the one being
penalised.

It is worst for the targets least able to afford it. On ESP32/xtensa a 10 KB
table becomes ~40 KB of flash plus boot-time stores.

## Not worked around, deliberately

`lib/rtl/sysutils.pas` keeps the plain const array. Re-encoding the table as a
string blob to dodge this would have hidden the bug and made the table
unreadable, which is exactly what
`CLAUDE.md`'s platonic-code rule forbids. The cost is recorded in that unit's
header instead. **When this is fixed, sysutils gets ~31 KB smaller with no
change to its source** — worth re-measuring then as the check that the fix
landed.

## Suggested check when fixing

The table above is the regression check — every one of those `code` deltas
should collapse to roughly the element bytes moving into `data`. Also confirm
the array lands in a **read-only** section where the target supports one, since
nothing may write to a typed constant.

---

## Fixed 2026-08-21

### Measured, same two programs the ticket used

| | code | data | bss |
| --- | --- | --- | --- |
| 1 element | 58,340 | 1,616 | 42,440 |
| 696 elements | 58,340 | 7,176 | 42,440 |
| delta | **+0** | **+5,560** | **+0** |

`+5,560` is exactly `695 * 8` — the table's own bytes, and nothing else. The
ticket's "every one of those code deltas should collapse to roughly the element
bytes moving into data" is the result, literally.

### sysutils, the check the ticket asked for

`uses SysUtils` program, `pinned` (v369, pre-fix) vs HEAD:

| | code | data | bss |
| --- | --- | --- | --- |
| before | 298,924 | 8,804 | 86,812 |
| after | 258,222 | 19,988 | 75,628 |
| delta | **-40,702** | +11,184 | **-11,184** |

**-40.7 KB of code and -11.2 KB of RAM, with no edit to sysutils' source** —
better than the ~31 KB the ticket predicted. The unit's header note is updated
to record it, because "we did not work around the compiler bug and got the win
for free" is worth having written down as a measurement rather than a principle.

### How: one biased offset, not a per-backend change

A global's `Syms[i].Offset` is a BSS offset, and **~280 call sites across six
backends** reach a global through `EmitGlobRef(Syms[i].Offset)`. Teaching all of
them about a second section was never the job. Instead a data-resident symbol
carries `DATA_SYM_BIAS + dataOffset`, and the **ELF writers' fixup loops decode
it** — three identical five-line arms, plus one in the DWARF location emitter.
Nothing in any backend changed, and every target got the fix at once. Verified
by running the value test on i386, arm32, aarch64 and riscv32: identical output
on all four.

A **bias** rather than a flag or a negative sentinel because offset ARITHMETIC
has to keep working: `Offset + 8` for a field or an element survives a bias and
would silently corrupt a sentinel.

`.data` is writable here (one RWX PT_LOAD) and that is **required, not
incidental**: writable typed constants are a real Pascal feature, and the
ticket's "confirm the array lands in a read-only section" would have turned a
working program into a fault. The test writes to a typed const on purpose.

### Fails closed, all-or-nothing per array

`TryBakeConstArrayIntoData` promotes only when **every** element is a plain
ordinal or float literal covering the whole extent in order. A string element (a
heap handle), a record element (a field list), a `@proc`, a class ref, a set —
any one of them and the whole array keeps the existing startup-store path, which
still works. Refused outright for `--emit-obj` / `--shared`: those writers emit
RELOCATIONS against a section symbol rather than patching an absolute address, so
a data-resident global needs a different section index there. Not done; refusing
is what keeps that honest, and it is the one piece of this ticket left open.

The BSS the array had already been reserved is **reclaimed**, not left as a hole —
otherwise the fix would have traded 20 KB of code for 5.5 KB of dead RAM and the
half of the ticket that matters on an MCU would still be open.

### The trap, found by measuring

**Single.** A float literal is recorded as the DOUBLE's bit pattern whatever the
declared element type is, so baking `array of Single` by copying the low four
bytes gives garbage — `(0.0, -1.5, 2.5, 1e30)` read back as
`(0, 0, 0, 3.06e-4)`. Caught by diffing the value test against FPC, not by
reading the code: the first three arrays in that test were byte-perfect. The fix
lets the HOST narrow (`f := d` through a Double, then read the 4 bytes back),
which is the same IEEE round-to-nearest the target's `cvtsd2ss` would have done
on the path this replaces.

### Left open

- **`--emit-obj` / `--shared`** keep the old path (see above).
- **Local (routine-scoped) typed const arrays** are not promoted — they take the
  `LocalInit*` channel, which is a different mechanism. Global tables are where
  the size goes.
- **A read-only section** for a const that is provably never written. Not done,
  and not obviously wanted: it needs a second PT_LOAD and it forfeits FPC's
  writable-typed-constant semantics.

### Gate

`test/test_const_array_in_data.pas` — every baked element width, a negative low
bound, the three arrays that must NOT bake, and a write to a typed const.
Identical to FPC 3.2.2, and identical on i386/arm32/aarch64/riscv32.
`make compiler/pascal26` fixedpoint (1 round) + `tools/gate.sh quick` GREEN.
`PXXDBG=a.constdata` lists what got baked (documented in `devdocs/dev/debug-switches.md`).

## Log
- 2026-08-21 — resolved, commit PENDING-COMMIT.
