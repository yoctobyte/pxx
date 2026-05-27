# PXX Documentation

**Documentation snapshot:** 2026-05-27

`PXX` is the provisional project and compiler name. The executable is still
called `compiler/pascal26` while the name and artifact migration remain open.
Implementation may change faster than these documents. For exact current
behavior, treat the source and regression suite as authoritative and use the
snapshot date when assessing compatibility claims.

User-facing documents:

- [Philosophy](philosophy.md) - project vision, design constraints, language priority, and what this is not.
- [Command Line](cli.md) - invoking the compiler, output files, options, and build commands.
- [Pascal Dialect And Compatibility](pascal-dialect.md) - supported Pascal surface, PXX/FPC identity, and conditional compilation.
- [Features](features.md) - self-hosting, language frontends, native output, and library loading.
- [Limitations](limitations.md) - unsupported or only partially supported language, ABI, platform, and tooling areas.

Frontend notes (planned languages):

- [Rust Frontend](rust-frontend.md) - memory management approach and scope for the planned Rust frontend.

Additional project material:

- [C Interoperability](../C_INTEROP.md) - detail on Pascal-to-C header imports and supported C preprocessing.
- [Compatibility Status](../COMPATIBILITY.md) - dated implementation inventory and bootstrap policy.
- [Implementation Handover](../handover.md) - internal architecture and bootstrap notes.
