---
track: N
prio: 60
type: feature
claimed: claude-n-uforth
---

# NilPy: list type v1 (pylib TPyList, literals, subscripts, methods, len)

Part of [[feature-nilpy-corpus-uforth]] milestone 1. The biggest single rung:
uforth's stacks are List[Any] (Word.forth_body, Frame.body, VM.stack...).

Design (settled this session):
- **TPyList = a real class in a new builtin unit `compiler/builtin/pylib.pas`**
  (Track B file, language-neutral lib): growable raw-memory array of 16-byte
  variant slots ({VType,Payload} — builtin.pas's TVariantRecord model, VType 0
  = None). Reference semantics like Python (class = heap pointer). Methods
  append (returns Self for literal-desugar chaining) / pop / insert / clear /
  count; `property Items[i] default` gives xs[i] read+write through the
  EXISTING default-indexed-property machinery — no subscript work in the
  frontend. Negative indices Python-style; out-of-range = runtime error halt.
- **Frontend**: `[a, b, c]` desugars to create + chained .append() calls
  (one expression, no statement context needed); List[...] annotations map
  to tyClass/TPyList; `len(x)` resolves to a plain pylib function; pylib is
  auto-used by every .npy.
- Frozen-string build assumption: variant payloads are copied raw (no
  refcount). The managed-string build needs a revisit — noted here.

Later rungs: slices, for-in over lists, dict (same pattern: TPyDict),
in/remove/index/extend/sort.

## Gate

test-nilpy green (+ test_nilpy_list.npy vs CPython), self-host, quick tier.
