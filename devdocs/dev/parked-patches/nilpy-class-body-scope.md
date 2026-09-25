# nilpy-class-body-scope

Parked 2026-09-25 at the wrap-up, by frankH (Track N). It is not landed only
because its full test-nilpy run had not finished when the fleet was scaled
down. The owner's rule for the Blaise pin: land only what is already clean.

**What it does.** A class body is a scope. An attribute initialiser can read,
bare, the attributes bound ABOVE its own line:

```python
class INA219:
    ADC_9BIT = const(0)
    __ADC_CONVERSION = {ADC_9BIT: "9-bit"}
```

That is ina219.py:24/:36. Without the patch this is refused with
`undefined variable (ADC_9BIT)`.

- A class name shadows a module global of the same name.
- A name bound later in the body still reads the module's binding.
- `N = N + 10` reads the module's N before it binds, as in CPython.
- Method bodies are unaffected.

It works through the SAME door that method defaults already use
(`$clsattr.<Class>.<name>` globals, in the ident path beside
`PyDefaultClsCi`). The new pieces are `PyClsBodyCi`/`PyClsBodyUpTo`, set
around the initialiser parse in `PyEmitClassAttrExpr`, and
`PyClsBodyBoundBefore`, a backward walk at the body's own depth from the
start of the current line.

**Contents:**

- compiler/pyparser.inc
- the Makefile row, after the hasattrmod26 row
- test/test_nilpy_a_class_body_reads_the_attributes_bound_above_it.{npy,expected},
  where `.expected` is CPython's output

`git apply --check` is clean on b011e5a41c.

**Measured:**

- The fixture diffs SAME against CPython.
- The pre-patch compiler refuses it, which is the positive control.
- With the patch, the MicroPython driver census reaches 15 of 16
  (ina219 compiles; compiler 09fccec2779e).
- A full test-nilpy run got past the first ~1,750 lines and stopped at an
  UNRELATED upstream red, since fixed in 8a3feafbcc. A re-run was in
  progress and never finished.

**To land:**

1. Apply the patch.
2. `make compiler/pascal26`.
3. Run a full test-nilpy with `PXX_ALLOW_FULL_SUITE=1`. It changes name
   lookup inside every class body, so quick is not enough.
4. `tools/gate.sh quick`.

**Known and accepted (owner):** a METHOD body that names a class-only
attribute bare compiles and reads it, where CPython raises NameError. That
behaviour predates this patch and is in the accept direction.
