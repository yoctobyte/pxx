---
slug: bug-c-an-empty-asm-with-in-out-operands-is-refused
track: C
prio: 70
type: bug
status: done
owner: pxx2
created: 2026-11-26
closed: 2026-11-26
found-by: pxx2 (Nodisx curl + mbedTLS recipe)
tags: [cfront, inline-asm]
summary: "An empty asm template whose outputs are all read-write (`asm volatile (\"\" : [x] \"+r\" (x) :)`, mbedTLS's constant-time barrier mbedtls_ct_compiler_opaque) was refused as 'an output operand list ... an empty template cannot have written to it'. Every output that an input is tied to (`+r`, or `=r` with a matching \"0\" input) keeps the input's value under an empty template, as with gcc, so those are accepted; an untied `=r` output is still refused. Test c_asmbar26 against gcc."
---
# An empty asm with `+r` operands was refused

mbedTLS 3.6.8, `library/constant_time_impl.h`:

```c
static inline mbedtls_ct_uint_t mbedtls_ct_compiler_opaque(mbedtls_ct_uint_t x)
{
    asm volatile ("" : [x] "+r" (x) :);
    return x;
}
```

It is an optimisation barrier: the compiler may not know `x`'s value
afterwards. Every mbedTLS unit that includes the header (20 of the ones curl
links) failed with the refusal meant for `asm("" : "=r"(x))`, where an empty
template really leaves the output undefined.

## Fix

`ParseCStatementAST`, the empty-template exit: by then a `+` output has been
split into `=` plus an input tied to it, so the question is whether some
input's `TiedTo` names each output (`CAsmOutIsTied`). If all are tied, the
block is accepted as a no-op and each output keeps its value, which is what gcc
gives. pxx does no value-range reasoning across it, so the barrier also does
what it is there for.
