---
summary: "aarch64: writeln(d:0:1) of a large Double prints a wrong integer part — 9007199254740991 comes out as 9007199254740990.4, and QWord-max shifts a whole decimal digit. Not ULP rounding: the digits are wrong"
type: bug
track: A
prio: 45
---

# aarch64: `writeln(d:0:1)` of a large Double prints wrong digits

- **Type:** bug — Track A (aarch64 backend or the shared decimal-formatting path)
- **Status:** backlog
- **Opened:** 2026-08-05
- **Found by:** Track A+C, cross-checking the Pascal side while fixing
  `bug-c-int64-to-double-cast-truncates-on-32bit`. **Pre-existing** — reproduced
  identically on `stable_linux_amd64/default/pinned`.

## Symptom — aarch64 only

```pascal
var i: Int64; q: QWord; d: Double;
begin
  i := 9007199254740991; d := i; writeln(d:0:1);   { FPC 9007199254740991.0 }
  q := 18446744073709551615; d := q; writeln(d:0:1);
  writeln(Int(9007199254740991):0:1);              { FPC 9007199254740991.0 }
end.
```

| line | FPC | pxx aarch64 | pxx x86-64 / i386 / arm32 / riscv32 |
| --- | --- | --- | --- |
| 1 | `9007199254740991.0` | **`9007199254740990.4`** | `9007199254740991.0` |
| 2 | `18446744073709552000.0` | **`922337203685477580.7`** | see note |
| 3 | `9007199254740991.0` | **`9007199254740990.4`** | `9007199254740991.0` |

## Why this is filed despite the no-float-formatting rule

The standing rule (user, stated repeatedly) is that **float formatting and libm
ULP rounding are out of scope**. This is filed anyway because it is not a
last-place-digit disagreement:

- `2^53-1` is **exactly representable** in a double. There is no rounding
  question — the correct decimal expansion is exact, and every other target
  prints it exactly. `.4` is not a rounding of `.0`.
- Line 2 loses a whole **decimal digit** (`9.2e17` where the value is `1.8e19`),
  which is a magnitude error, not a precision one.

So the *values* are wrong on aarch64 in a way the other four targets are not.
If on inspection this turns out to be genuine ULP/rounding territory after all,
close it as out-of-scope rather than chasing it — that call belongs to whoever
looks, and it is the reason this sits at prio 45 rather than higher.

## Note on line 2's other targets

x86-64 has a *separate*, unrelated defect on that line
(`bug-a-x86-64-qword-to-double-assign-halves-above-2-63`). i386 / arm32 /
riscv32 print `18446744073709551616.0` where FPC prints
`18446744073709552000.0` — those two ARE the same double at different print
precision, and that difference is the out-of-scope kind. Three different things
share one line; do not conflate them.

## Repro

```
printf 'var d: Double;\nbegin d := 9007199254740991; writeln(d:0:1); end.\n' > /tmp/a.pas
./compiler/pascal26 --target=aarch64 /tmp/a.pas /tmp/a_p && qemu-aarch64 /tmp/a_p
```
