# PXX Documentation

**Documentation snapshot:** 2026-06-05

`PXX` is the provisional project and compiler name. The executable is still
called `compiler/pascal26` while the name and artifact migration remain open.
Implementation may change faster than these documents. For exact current
behavior, treat the source and regression suite as authoritative and use the
snapshot date when assessing compatibility claims.

User-facing documents:

- [License And Use Notice](../LICENSE.md) - public research visibility only; no license or usage rights granted yet.
- [Acronyms And Glossary](acronyms.md) - expansions for acronyms and shorthand used across the docs, source, and handovers (WIP, IR, RTL, RTTI, LFM, ABI, ...).
- [Philosophy](philosophy.md) - project vision, design constraints, language priority, and what this is not.
- [Command Line](cli.md) - invoking the compiler, output files, options, and build commands.
- [Pascal Dialect And Compatibility](pascal-dialect.md) - supported Pascal surface, PXX/FPC identity, and conditional compilation.
- [Features](features.md) - build baseline, language frontends, native output, and library loading.
- [Wrapper-Free C From Nil Python](wrapper-free-c-from-nil-python.md) - public overview of the SQLite proof: `.npy` imports `sqlite3` directly, with compiler-lifted out-params and copied C strings instead of handwritten wrappers.
- [ESP32 And ESP-IDF Direction](esp32-esp-idf-roadmap.md) - public note on ESP32 as an embedded target, ESP-IDF C imports, FreeRTOS as a target profile, and fast native iteration.
- [Limitations](limitations.md) - unsupported or only partially supported language, ABI, platform, and tooling areas.
- [Inline Assembler](inline-asm.md) - x86-64 inline asm support, supported instruction set, variable passing, limitations, and TODO.
- [GUI (GTK3 + LFM streaming)](gui.md) - LCL-compatible widgetset on GTK3, of-object events, and `.lfm`-streamed component trees.
- [Plan: RTTI → Streaming → LFM](plan-rtti-streaming-lfm.md) - agent-executable phased plan for Lazarus/LCL enablement (RTTI, published, component streaming, resources, LFM).
- [Project TODO](todo.md) - consolidated remaining-work list: standing bugs, the LCL arc, interfaces (detailed), language gaps, targets, and the units refactor.
- [Rainy Afternoon Backlog](rainy-afternoon.md) - compact list of known non-critical bugs, limitations, and optional cleanup work.
- [Project State Audit](project-state.md) - dated compact inventory of verified support, confirmed bugs, missing Pascal features, design debt, and the latest benchmark snapshot.
- [Anomaly: non-reproducible miscompile (2026-06-02)](anomaly_2026-06-02_2000.md) - forensic record of a one-off, self-cleared, deterministic-toolchain miscompile; suspected hardware bit flip. Evidence in [`anomaly-evidence-2026-06-02/`](anomaly-evidence-2026-06-02/).

Navigation:

- [Code Map (`agents/codemap/symbols.md`)](../agents/codemap/symbols.md) - concise per-file index of constants, types (with fields), globals, and routine signatures (with the doc-comment above each), all with line numbers. Regenerate with `make symbols` (`tools/gen_symbols.py`, stdlib only). Read this before grepping the large `.inc` files.

Architecture and current state:

- [Implementation Architecture](architecture.md) - include chain, generic machinery, library resolution, key gotchas, class/method layout, dialect switches, operator overloading.
- [IR Backend Status](ir-handover.md) - IR pipeline, coverage, and known gaps. The IR path is the development focus and has reached self-recompile fixedpoint.
- [Compatibility Status](compatibility.md) - dated implementation inventory and bootstrap policy.
- [Target Roadmap](roadmap.md) - planned CPU targets and the fixedpoint gate each must pass.
- [ESP32 And ESP-IDF Direction](esp32-esp-idf-roadmap.md) - embedded target strategy for ESP-IDF, FreeRTOS compatibility, and CPU-family staging.
- [Allocator Platform Design](allocator-platform-design.md) - syscall-free internal heap with optional hosted or RTOS hooks.
- [Garbage Collection Thoughts](garbage-collection-thoughts.md) - why GC is not the default (root-finding cost, bare-metal tension) and the per-target/per-frontend memory profile decision (ARC / arena / hosted collector).
- [Runtime Emission Size Audit (2026-06-02)](runtime-emission-size-audit-2026-06-02.md) - measured hello-world overhead and deferred feature-reachability cleanup for embedded targets.
- [Plan: Async, Coroutines, And Yield](plan-async-coroutines.md) - deferred shared state-machine design for Pascal, Nil Python, and future frontends.
- [Plan: Refcounted Compiler Strings](plan-refcounted-compiler-strings.md) - status and remaining decisions for flipping the compiler's own `AnsiString`s from frozen 8 MB inline buffers (~1.6 GB BSS) to refcounted handles. Managed self-compile fixedpoint is reached; default flip/reseed remains a product decision.

Additional project material:

- [Lineage and Acknowledgements](lineage.md) - the people and languages this project is built on.
- [C Interoperability](c-interop.md) - detail on Pascal-to-C header imports and supported C preprocessing.
- [Developer Notes](developer-notes.md) - rough project-shape notes and informal positioning.

Historic / design archive (`historic/`, point-in-time — superseded by the above):

- [Handover: `default` Keyword Design & Prompt](historic/handover-default-keyword-2026-06-05.md) - archived implementation prompt; `default` assignment is now implemented and covered by `test/test_default_keyword.pas`.
- [Handover: GUI final mile](historic/handover-final-mile.md) - archived plan; stock `test/gui/helloworld` support is delivered and summarized in `gui.md`.
- [Handover: Managed-Strings Self-Compile — Fixedpoint](historic/handover-managed-strings-record-layout-2026-06-05.md) - archived drive log for the managed-string self-compile fixedpoint.
- [Handover: Next Compiler Work](historic/handover-next-work.md) - archived 2026-06-02 runtime/allocator resume checklist; durable items now live in `project-state.md`, `todo.md`, and allocator/threads plans.
- [Handover: Resume Python-Ready Variant Work](historic/handover-sis-ai-2026-06-02.md) - archived Variant/Nil Python resume brief after the runtime gate.
- [Handover: Nil Python ↔ C Binding And Inference](historic/handover-nilpy-c-binding-2026-06-02.md) - archived binding-first plan, superseded by the wrapper-free SQLite path.
- [Handover: Wrapper-Free Nil Python ↔ C](historic/handover-wrapper-free-nilpy-c-2026-06-03.md) - archived delivered arc: `.npy` imports `sqlite3` directly with lifted trailing `T**` out-params and copied `char*` returns.
- [Implementation Handover (2026-05-28)](historic/handover-2026-05-28.md) - dated session snapshot; durable parts now in `architecture.md`.
- [Phase 2 Handoff](historic/phase2-handoff.md) - RTTI-via-typed-pointers resume checklist; delivered 2026-05-30.
- [IR Fixedpoint Milestone](historic/selfcompile-milestone.md) - 2026-05-28 IR-to-IR self-recompile fixedpoint record.
- [Language Status](historic/language-status.md) - timestamped feature inventory with AST/IR complexity estimates.
- [Interfaces Design Notes](historic/interfaces-design.md) - fat pointers, COM vs lightweight model, prerequisite chain.
- [RTTI Design Notes](historic/rtti-design.md) - reflection as data-emission, opt-in via published.
- [Implementation Plan](historic/implementation-plan.md) - ordered phase-by-phase plan for missing language features.
- [Rust Frontend](historic/rust-frontend.md) - memory-management approach and scope for the planned Rust frontend.
