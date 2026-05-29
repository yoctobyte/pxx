# PXX Documentation

**Documentation snapshot:** 2026-05-28

`PXX` is the provisional project and compiler name. The executable is still
called `compiler/pascal26` while the name and artifact migration remain open.
Implementation may change faster than these documents. For exact current
behavior, treat the source and regression suite as authoritative and use the
snapshot date when assessing compatibility claims.

User-facing documents:

- [Philosophy](philosophy.md) - project vision, design constraints, language priority, and what this is not.
- [Command Line](cli.md) - invoking the compiler, output files, options, and build commands.
- [Pascal Dialect And Compatibility](pascal-dialect.md) - supported Pascal surface, PXX/FPC identity, and conditional compilation.
- [Features](features.md) - build baseline, language frontends, native output, and library loading.
- [Limitations](limitations.md) - unsupported or only partially supported language, ABI, platform, and tooling areas.
- [Inline Assembler](inline-asm.md) - x86-64 inline asm support, supported instruction set, variable passing, limitations, and TODO.
- [Plan: RTTI → Streaming → LFM](plan-rtti-streaming-lfm.md) - agent-executable phased plan for Lazarus/LCL enablement (RTTI, published, component streaming, resources, LFM).

Frontend notes (planned languages):

- [Rust Frontend](rust-frontend.md) - memory management approach and scope for the planned Rust frontend.

Additional project material:

- [Lineage and Acknowledgements](lineage.md) - the people and languages this project is built on.
- [C Interoperability](../C_INTEROP.md) - detail on Pascal-to-C header imports and supported C preprocessing.
- [Compatibility Status](../COMPATIBILITY.md) - dated implementation inventory and bootstrap policy.
- [Implementation Handover](../handover.md) - internal architecture and bootstrap notes.
- [IR Backend Status](ir-handover.md) - IR pipeline, coverage, and known gaps.
- [IR Fixedpoint Milestone](selfcompile-milestone.md) - 2026-05-28 IR-to-IR self-recompile fixedpoint record.
- [Target Roadmap](roadmap.md) - planned CPU targets and the fixedpoint gate each must pass.
- [Language Status](language-status.md) - timestamped inventory of implemented, partial, and missing Pascal features with AST/IR complexity estimates.
- [Interfaces Design Notes](interfaces-design.md) - why interfaces are last: fat pointers, COM vs lightweight model, and the prerequisite chain.
- [RTTI Design Notes](rtti-design.md) - reflection as data-emission, opt-in via published, and why it comes before interfaces.
- [Implementation Plan](implementation-plan.md) - ordered phase-by-phase plan for all missing language features; ready for agents to execute.
