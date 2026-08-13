---
track: N
prio: 40
type: bug
blocked-by: [bug-nilpy-exception-args-attribute-missing]
status: done
owner: claude-A-N
---

# Exception `repr()` is the default object repr (KeyError's message: FIXED 2026-08-09)

```python
try:
    raise KeyError("inner")
except KeyError as e:
    print(str(e), repr(e))

try:
    {}["nope"]
except KeyError as e:
    print(str(e))
```

| | CPython | pxx |
| --- | --- | --- |
| `repr(KeyError('inner'))` | `KeyError('inner')` | `<__main__.KeyError object at 0x...>` |
| `str(KeyError('inner'))` | `'inner'` (quoted!) | `inner` |
| `str()` of a real missing-key error | `'nope'` | `key not found` |
| `repr(ValueError('v'))` | `ValueError('v')` | `<__main__.ValueError object at 0x...>` |

Three separate things:

1. **No `__repr__` on exceptions.** Every exception falls back to the default
   object repr, so `repr(e)` prints an address. `ClassName(args)` is what
   CPython prints, and it is what appears in logs and in `%r` formatting.
   The @dataclass `__repr__` generator landed 2026-08-09 does exactly this shape
   already (class name, parenthesised arguments) — the exception case wants the
   same builder over `e.args`.

2. **`KeyError.__str__` is the REPR of its argument**, uniquely among builtin
   exceptions — `str(KeyError('inner'))` is `"'inner'"`, with quotes. It reads
   like a quirk and it is, but it is also what every "key not found" message in
   real logs looks like, so a diff against CPython output will trip on it.

3. **A genuine missing-key raise loses the key entirely**, reporting the fixed
   text `key not found`. That is the most useful of the three to fix: the key is
   the whole content of the message, and without it a KeyError says nothing.

## Found by

An exception/class-hierarchy sweep against CPython. Everything else in that
sweep matched exactly — custom exception classes, `super().__init__`, catching
by base class, tuple `except`, `else`/`finally` ordering, `type(e).__name__` —
so these three are the residue.

## Gate

`make test-nilpy` + self-host byte-identical, CPython-diffed over `str`/`repr`
of KeyError, ValueError, a bare `Exception`, a user-defined subclass, the
zero-argument and multi-argument forms, and a real missing-key lookup.

## 2026-08-09 — items 2 and 3 FIXED; item 1 (repr) still open

A missing key now reports the KEY. All four raise sites went through one keyless
`PyKeyError`, so they all had the key in scope and all four now pass it.

The message is built with **`pyvar_repr`, not `pystr_of`**, which fixes item 2
at the same time and for free: CPython's KeyError is the one builtin exception
whose `str()` is the REPR of its argument, so a missing string key now reports
`'nope'` with the quotes and a missing int key reports `7` without them. A
str-based fix would have passed the int case and failed the str one — which is
why `test/test_nilpy_keyerror_names_the_key.npy` asserts both kinds, plus an
empty-string key, a key containing a quote, and all four raise sites.

**Item 1 is untouched:** `repr(e)` on any exception is still the default object
repr (`<__main__.KeyError object at 0x...>` where CPython prints
`KeyError('nope')`). The test says so and deliberately does not pin it — the
current answer contains an address and is not even stable run to run.

The @dataclass `__repr__` generator that landed the same day is the shape that
half wants: class name, parenthesised arguments. It would need `e.args`, which
is its own open item.

## 2026-08-09 (later) — item 1 (repr) FIXED for everything except KeyError

`repr(e)` on an exception with no `__repr__` of its own now renders
`ClassName('msg')` instead of `<__main__.ValueError object at 0x...>`. Covers the
builtins and user-defined subclasses, in `%r`, inside containers, and for caught
exceptions. Pinned by `test/test_nilpy_exception_repr.npy`.

**KeyError is deliberately excluded and keeps the address form.** It cannot be
rendered correctly from a Message alone: its message is stored ALREADY REPR'D so
that `str()` matches CPython's quirk, so quoting it again gives
`KeyError("'nope'")`, and not quoting it gives `KeyError(k)` for a
user-constructed `KeyError("k")`. Both are wrong in opposite cases, and which one
you hit depends on WHO RAISED IT. Neither ships. An address is obviously
unhelpful; a wrongly quoted key would look authoritative.

The empty-message case renders as `ValueError()`. `ValueError('')` is
indistinguishable from it given one Message field, and the zero-argument
spelling is far the commoner.

**Both of those are the same root, and it is `e.args`:** a pxx Exception carries
a single Message string where Python carries an argument tuple. Until that
exists, KeyError's repr and the `ValueError('')` case cannot be right. That is
the next piece of this ticket.

## `str()` of a CONSTRUCTED exception — also FIXED

`str(ValueError("v"))` on an exception that was never raised gave the address
form while a CAUGHT one gave its message. Both routes now return the message and
`test/test_nilpy_exception_str_constructed.npy` asserts them SIDE BY SIDE —
fixing one and leaving the other is exactly the divergence that produced this.

A THIRD route turned up while testing and is filed separately: an Exception
subclass defining its own `__str__` has it IGNORED, printing the constructor
argument instead. Pinned does the same, so it is not a consequence of this work —
it short-circuits before the dunder lookup and never enters `PyUserObjStr`. See
`bug-nilpy-user-str-dunder-on-an-exception-subclass-is-ignored`.

**So `str()`/`repr()` of an exception had THREE routes**, and that is the shape
worth remembering here rather than any individual fix.


## 2026-08-13 — the residue is KeyError-only, and it is BLOCKED on `e.args`

Re-measured across six exception types. The boundary is sharper than the top
table (a pre-work snapshot) shows, and everything below is now correct:

| | str | repr |
| --- | --- | --- |
| ValueError / TypeError / IndexError / RuntimeError | correct | correct |
| a real missing-key lookup | correct — `'nope'`, quoted | **address** |
| a user-constructed `KeyError("k")` | **`k`**, unquoted | **address** |

So the only thing left is KeyError, in both directions, and both directions are
the SAME missing fact: a pxx Exception carries one Message string where Python
carries an `args` tuple. The message is stored already-repr'd on the raise path
(so `str()` matches CPython's quirk) and raw on the construct path, so no
rendering rule can be right for both — as `pylib.pas` records at the exclusion
site, quoting gives `KeyError("'nope'")` and not quoting gives `KeyError(k)`.

**That dependency existed only in prose**, in this file and in a code comment
("the real fix is `e.args`, which is its own open item"), so the ranker could
not see it: this ticket sat at prio 40 in the ready queue while the blocker it
cannot be finished without sat at 30, twenty rows below, looking optional. Now
declared in frontmatter, which is what `tools/progress.sh` reads, so 40
propagates down the edge and [[bug-nilpy-exception-args-attribute-missing]]
ranks as what it is: the thing to do first.

Nothing here needs re-investigating once args lands — the rendering site is
already written and already has KeyError carved out of it by name.

## DONE 2026-08-13 — all three items, once `args` existed

This ticket was blocked on [[bug-nilpy-exception-args-attribute-missing]] and
its three items fell out in order once that landed.

| item | now |
| --- | --- |
| 1. no `__repr__` on exceptions | `repr(ValueError('v'))` is `ValueError('v')` (landed earlier with the dataclass-style repr builder) |
| 2. `KeyError.__str__` is the REPR of its argument | **fixed here** |
| 3. a real missing-key raise loses the key | `KeyError('nope')`, key included |

### Item 2, and why it needed `args` first

The exception repr deliberately EXCLUDED KeyError, for a reason this ticket
stated correctly: its message is stored already repr'd on the raise path, so
quoting again gives `KeyError("'nope'")` while not quoting gives `KeyError(k)`
for a user-constructed one — both wrong, in opposite cases, depending on who
raised.

The fix is to stop having two storage conventions. `KeyError.Create` now reprs
its argument itself and keeps the raw one in `args`, so a user's
`raise KeyError("inner")` and the runtime's own raise agree: `str(e)` is
`'inner'` (quoted, as CPython has it), `repr(e)` is `KeyError('inner')`, and
`e.args` is `('inner',)` unquoted.

**The int-key row is the one that made this more than a rename.** PyKeyError
reprs the VARIANT — `repr(7)` is `7`, unquoted — and routing that text through
the new constructor repr'd it a SECOND time, reporting `'7'` for a missing 7.
The existing `test_nilpy_keyerror_names_the_key` caught it immediately, which is
what that test is for. So the raise site uses `CreateRendered`, which stores an
already-rendered key verbatim, and the quoting stays a property of the repr
rather than a rule about keys.

Test rows added to `test/test_nilpy_exception_args.npy` (`.expected` from
CPython) — the user/miss/int triple, since they are the three ways a KeyError
gets built and the whole point is that they agree. The thirteen other exception
tests were re-run against their exact assertions.

`compiler/builtin/**`, so it carries the pin. Gate: self-host fixedpoint +
`tools/gate.sh quick` GREEN.

## Log
- 2026-08-13 — resolved, commit PENDING-COMMIT.
