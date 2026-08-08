---
track: N
prio: 55
type: bug
status: done
summary: "RESOLVED — `return None` from a `-> Optional[str]` def handed back the TEXT 'None', so `x is None` was False and the value was truthy. The assignment path had the rule; the return path did not. Broke every `while True: ... if tok is None: break` loop."
---

# `return None` from a str-returning def yielded the text 'None'

```python
class VM:
    def f(self) -> Optional[str]:
        return None

a = vm.f()
print(a is None)     # CPython True   pxx False
print(str(a))        # CPython None   pxx 'None' — the TEXT, which is why
```

`-> Optional[str]` is how every "no more input" accessor is spelled, so the
shape this breaks is a loop whose ONLY exit is `if x is None: break`.

## Sibling branches

NilPy spells a None str as a NIL HANDLE (`pystr_none` / `pystr_is_none`). The
ASSIGNMENT path knew that — `x = None` into a str-typed target already lowered
to `pystr_none`, and its comment says why in as many words
(bug-nilpy-none-into-str-field-stores-text). The RETURN path did not: only a
VARIANT-returning def had a `return None` arm, and a str-returning one fell
through to the general expression path, where the nil literal coerced through
variant->string into the text `'None'`.

Same rule, same sentinel, one statement kind apart. Fixed by giving the return
path the arm the assignment path already had.

## What it cost: uforth's `.(`

`.( abc)` printed NOTHING, and an isolated copy of the same word HUNG — one bug
wearing two faces. EXTRA.UFO redefines `.(` as a Forth word with a PYTHON body:

```python
while True:
    tok = vm.next_token()      # -> Optional[str]
    if tok is None:
        break
```

The exit could never fire, so it ran past the end of the line and appended the
string `'None'` forever.

uforth's driver suite went from 8/11 to **10/11 byte-identical** with CPython on
this fix alone.

## Found by

uforth's own `--trace`, diffed between the CPython and pxx runs. That was the
step that mattered: it printed the executed token as
`PyInline(src="... while True: tok = vm.next_token() ...")`, revealing that `.(`
was a PYTHON-bodied Forth word and not the `w_dot_paren` native I had spent an
hour reading. Instrumenting uforth by hand was unavailable — a print inside the
word produces a pxx binary that hangs at startup, itself an open lead.

**A retracted root cause is recorded on
[[bug-nilpy-uforth-dot-paren-prints-nothing]]**: I first attributed this to the
byte-string model, which pure-ASCII input already disproved. Kept there
deliberately.

## Not fixed here, filed instead

- `str(<a None str>)` renders `''`, not `'None'` — pre-existing on the
  assignment path too. Attempted, and REVERTED: making `pystr_of` map a nil
  handle to `'None'` changed `==`/`is` results elsewhere in ways I did not
  understand, which is not something to ship half-understood.
- [[bug-nilpy-empty-str-and-none-are-the-same-value]] — `return ""` also reads
  as None, because Pascal's empty AnsiString IS a nil handle. That contradicts
  pylib's own comment and undermines the sentinel; pre-existing, identical under
  `pinned`.

## Gate

`test/test_nilpy_none_str_field.npy` EXTENDED — it already owned this sentinel
for the FIELD case; the return case and the loop shape (with a runaway guard, so
a broken build FAILS rather than hangs) are now beside it. `make test-uforth`
PASS, self-host byte-identical, `tools/gate.sh quick` GREEN.
