---
track: N
prio: 50
type: bug
---

# `"x" * n` is QUADRATIC — 80k characters takes 19 seconds

```python
s = "x" * 100000
print(len(s))        # CPython: instant     pxx: does not finish
```

Found by a scaling curve, which is the only way this shows up — every small case
is fine and the failure looks like a hang rather than a wrong answer.

| n | wall time |
| --- | --- |
| 10 000 | 180 ms |
| 20 000 | 798 ms |
| 40 000 | 4 397 ms |
| 80 000 | 18 782 ms |

Doubling n roughly quadruples the time: O(n²).

## Root cause — visible in four lines

`pylib.pas`:

```pascal
function pystr_repeat(const s: AnsiString; n: Int64): AnsiString;
begin
  Result := '';
  if n <= 0 then Exit;
  for i := 1 to n do
    Result := Result + s;        { <-- reallocates and copies the whole result, n times }
end;
```

Each `+` allocates a new buffer and copies everything accumulated so far, so the
total work is 1 + 2 + … + n characters. This is the same shape as
[[project_pxx_string_concat_in_loop_is_quadratic]] — the known `s := s + c`
pattern — here baked into a library routine rather than user code.

Note the contrast that makes it easy to miss: building the same string with an
explicit `for` loop of `s = s + "x"` in NilPy reaches 70 000 characters fine, so
the *slow* path is the one that looks like the fast idiom.

## Fix

Size the result once and fill it — linear in the output length:

```pascal
  m := Length(s);
  if (n <= 0) or (m = 0) then Exit;
  SetLength(Result, m * n);
  k := 1;
  for i := 1 to n do
    for j := 1 to m do begin Result[k] := s[j]; Inc(k); end;
```

Guard the length computation: `m * n` can overflow, and a huge `n` should fail
cleanly rather than allocate wildly (Python raises MemoryError / OverflowError).
`pylist_repeat`, added recently for `[0] * n`, should be checked for the same
shape.

## Gate

`make test-nilpy` + self-host byte-identical, plus the scaling curve above:
the point is that 80 000 drops from ~19 s to milliseconds AND that the timing
grows LINEARLY, not that one case got faster. Content must be byte-identical to
the old routine for a range of n and multi-character `s`.
