## Philosophical parking lot

> In an ideal collaboration the human's job is deletion.

Worth pondering. If AI generates, and the human curates — is curation just
deletion? Is that enough? Is it the most human thing left?

Counterproposal: it is up to humans to keep, to God to delete, and to AI to
randomize the screw-ups.

---

## Missing features

- class properties (getters and setters), mostly syntactic sugar, some namespace thingies. 

- variants
  possibly we can implement variant type as pure object/class implementation, especially since we already have operator overloading. therefore eliminate the need for any hardcoded implementation (although that could be faster. but no-one uses variants because they are fast).

- **float Write/WriteLn**: no float-to-string conversion or direct writeln of float values.
  Belongs in a standard library rewrite of Write/WriteLn rather than hardcoded compiler
  intrinsics. FPC-compatible usage of WriteLn will require that rewrite anyway, so hold
  off on compiler-level float printing until then.

- **float cast intrinsics**: no Trunc(), Round(), Float(), Int() etc.
  Integer↔float coercions happen implicitly in binary ops (cvtsi2sd) but explicit casts
  are missing. Trunc/Round need compiler builtins (cvttsd2si/cvtsd2si on x86-64) or
  inline asm; the rest (Frac, Floor, Ceil, Int) can be pure Pascal on top of those.
  Defer until unit system exists — implement in a system/math unit, not as hardcoded
  compiler intrinsics, to keep the compiler arch-neutral.

- **inline assembler** (`asm...end` blocks): useful for float casts, SIMD, and other
  low-level code, but a significant project. Defer until after IR/multi-arch work;
  inline asm is inherently arch-specific and needs the arch abstraction layer first.



 
