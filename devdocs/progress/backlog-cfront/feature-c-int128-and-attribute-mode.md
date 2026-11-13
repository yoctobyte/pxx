---
track: C
tags: [c, int128, attributes, libtommath]
prio: 30
type: feature
blocked-by: []
summary: "pxx has no 128-bit integer: no `__int128`, no `__SIZEOF_INT128__`, and `__attribute__((mode(TI)))` is refused. It also skips the narrower `mode(QI/HI/SI/DI)` without applying them, so `typedef int i8 __attribute__((mode(QI)))` is a 4-byte int where gcc makes it 1 byte."
status: open
owner: unassigned
---

# 128-bit integers, and `__attribute__((mode(...)))` that is honoured

Split out of [[bug-c-attribute-mode-ti-was-ignored-and-made-a-64-bit-type]].

## What exists

- **mode(TI) and wider:** refused by name since 2026-11-13, because ignoring
  them made a silent 64-bit type.
- **mode(QI), mode(HI), mode(SI), mode(DI), mode(word):** still skipped. The
  typedef keeps its base type. That is right when the base already has the
  mode's width, and wrong otherwise (`int ... mode(QI)` should be 1 byte).
  No corpus program has hit this yet; check before relying on it.

## Who wants 128-bit

- libtommath under MP_64BIT (its default for __GNUC__ on 64-bit). dropbear
  works around it with `-DMP_32BIT` (see tools/dropbear_pxx.py). 64-bit
  digits are roughly 2-4x faster for RSA.
- Common elsewhere: curve25519-donna-c64, BearSSL's 64-bit code, and Rust-
  or Go-style hash/PRNG code ported to C (`(unsigned __int128)a * b` for the
  high half of a product).

## Shape of the work

- A `tyInt128`/`tyUInt128` pair, or a two-register lowering limited to
  + - * (low half and full), shifts, compares and casts. Those are what the
  callers above use. Division is a runtime helper, written in pxx's own RTL
  (no libgcc, per the standing rule).
- `__int128`, `unsigned __int128`, `__SIZEOF_INT128__ 16`, and `mode(TI)` as
  an alias. SysV passes `__int128` in two eightbytes (a register pair).
- x86-64 first. Every other target refuses by name until it gets the
  lowering.
