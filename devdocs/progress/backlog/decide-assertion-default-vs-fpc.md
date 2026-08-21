---
track: U
prio: 25
type: decide
blocked-by: []
summary: "pxx evaluates Assert() by default; FPC ignores it unless -Sa. So Assert(False) raises EAssertionFailed here and is a no-op there — code that passes its own test suite under FPC can die under pxx, and vice versa. With -Sa the two agree exactly, so this is purely a question of which default we want. Options: keep ours, match FPC, or add {$ASSERTIONS}/-Sa and pick a default."
---

# Assertions are on by default here and off by default in FPC — which default do we want?

- **Type:** decision (Track U) — no code is wrong today; the question is which
  behaviour we commit to.
- **Status:** backlog
- **Opened:** 2026-08-21, from the exception-semantics differential in
  `bug-a-unhandled-exception-exits-1-not-217`.

## The fork

```pascal
try
  Assert(1 = 2, 'assertmsg');
except
  on e: Exception do WriteLn('c:' + e.ClassName);
end;
WriteLn('end');
```

| compiler | output |
| --- | --- |
| `fpc -Mobjfpc` (default) | `end` |
| `fpc -Mobjfpc -Sa` | `c:EAssertionFailed` / `end` |
| `pxx` (default) | `c:EAssertionFailed` / `end` |

So pxx's behaviour is exactly FPC-with-`-Sa`, and the *only* difference is which
way the switch points when nobody touches it. FPC's default is `{$C-}`
(assertions off); Delphi's is off in Release and on in Debug.

## Why it is worth a ruling rather than a default guess

It cuts both ways, which is what makes it a decision and not a bug:

- **Ours is the safer default.** An assertion that silently evaporates is a
  check the author believed they had. Code arriving from an FPC project has
  been *developed* with its assertions inert, so pxx is the first compiler that
  ever ran them — and it will find real bugs, and also fire on assertions that
  were wrong all along and never noticed.
- **Theirs is the compatible default.** Under the compat tag's rule ("behave
  like the reference implementation"), a program that FPC accepts and runs
  must run here. A third-party unit whose stale `Assert` is false now halts a
  program that works fine under FPC. That is exactly the upward-compatibility
  direction the N track spells out for CPython, applied to P.

## Options

1. **Keep assertions on by default.** Zero work. Accepts that some FPC code
   dies here with a diagnosis FPC would have skipped. Document it as a
   deliberate dialect divergence.
2. **Match FPC: off unless asked.** Maximum compat, and it silently disarms
   assertions in code written *for* pxx — the failure mode that is invisible
   until it matters.
3. **Implement the switch and then choose.** Add `{$ASSERTIONS ON/OFF}` /
   `{$C+}` / `{$C-}` and `-Sa`, so either default is a one-line change and
   per-unit control exists. Then pick a default (recommendation: keep ON, and
   let `--strict-*`-style compat flags turn it off with the rest of the
   FPC-parity switches). This is the only option that leaves the user in
   control, and it is small.

**Recommendation: option 3, defaulting to ON.** The switch is worth having on
its own merits, and once it exists the default stops being a one-way door.

## Notes

- Nothing else about assertions diverges: the class raised
  (`EAssertionFailed`), catchability, and the message all match.
- If option 2 or 3 lands, the conformance sweep (`pxx.skip`'s `dialect-pass`
  entries) is where the FPC-parity spelling belongs, per the compat tag.
