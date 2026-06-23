
## Also: signed 32-bit `shr` widened to 64-bit (2026-06-23)

The same 32-vs-64 promotion bites signed `integer`/`longint` shifts when the high
bit is set:

```pascal
var i: integer; begin i := -8; writeln(i shr 1); end.
{ fpc: 2147483644 (32-bit: $FFFFFFF8 shr 1)   pxx: 9223372036854775804 (64-bit) }
```

pxx sign-extends the 32-bit operand to 64 bits before shifting; FPC shifts in the
declared 32-bit width. (`and`/`or` with a literal mask are fine — `-1 and $FFFF`
= 65535 in both.) Root is shared with the cardinal case: 32-bit integer
expressions should be evaluated in 32-bit width, not promoted to 64-bit.
