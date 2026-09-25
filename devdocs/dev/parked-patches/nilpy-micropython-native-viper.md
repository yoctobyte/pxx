# nilpy-micropython-native-viper

Parked 2026-09-25 at the wrap-up, by frankH (Track N). The aim is to let
st7789py.py (MicroPython driver census, row `st7789`) compile unchanged. Its
walls are `@micropython.viper` at :617 and `@micropython.native` at :946.
The owner's decision (relayed by frankuser):

- native: a no-op.
- viper: keep the meaning. `uint` is an int annotation; `ptr8`/`ptr16`/`ptr32`(buf)
  are indexable little-endian views over a bytearray. Pure-Python semantics.
- Refuse unimplemented viper-only constructs in a plain sentence.

**Done, in `nilpy-micropython-native-viper-parser.patch`**
(compiler/pyparser.inc only). It applies cleanly (`git apply --check`) on
b011e5a41c, and independently of nilpy-class-body-scope.patch.

- `PyCodeEmitterDecoratorAt` / `PyEatCodeEmitterDecorator` eat
  `@micropython.native|viper|bytecode` in the class body and in both module
  loops. `asm_thumb`/`asm_xtensa`/`asm_rv32` are refused by name.
- `PyDecoratorTailBefore` makes the static/classmethod/property/overload
  lookbacks step over those lines. st7789 stacks `@micropython.viper` ABOVE
  `@staticmethod`.
- The annotation `uint` reads as int. A PARAMETER annotated `ptrN` is refused
  with a sentence, because reading it as Any would index by byte whatever the
  width said.
- An expression arm beside `const(...)`: `ptr8/16/32(x)` becomes a call to
  pylib `pyptr_view(x, width)`, typed as its class.

**Left:**

1. Put `nilpy-micropython-viper-ptrview-pylib-DRAFT.pas` into
   compiler/builtin/pylib.pas. That means the implementation bodies, plus a
   `TPyPtrView = class` declaration beside TPyFile, modelled on
   lib/rtl/mimic_array.pas `array_`:
   - `FBuf: TPyBytes`, `FWidth: Integer`
   - `at`/`put`, and `property Items[i: Integer]: Int64 read at write put; default;`
   - `__getitem__`/`__setitem__` on Variants
   - the interface declaration of `pyptr_view`
   - an `if o is TPyPtrView then PXXObjRelease(FBuf)` arm in PyObjFinalize

   The draft has never been compiled.
2. The fixture row: write through ptr16 and read the bytes back, diffed
   against the expected LE bytes. Include a ptr32 and a ptr8 row, and a
   store wider than the element (truncation).
3. Compile st7789py.py unchanged (census row `st7789`), then re-run
   tools/mpy_driver_census.sh.
4. Check that the builtin-arm route really reaches the default property on a
   Pascal class. mimic_array proves it for a statically typed local, and a
   `glyph = ptr8(glyphs)` over an unannotated (Variant) parameter goes through
   the call's Variant boxing. Neither has been measured for this class.
