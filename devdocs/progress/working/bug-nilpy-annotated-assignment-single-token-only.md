---
track: N
prio: 60
type: bug
owner: agent-n
---

# NilPy: an annotated assignment only accepted a SINGLE-TOKEN annotation

Found 2026-07-20 while smoke-testing the session's features together.

```python
from typing import Dict, List

d: Dict[str, int] = {}      # error: near  Dict  List  d >>> Dict
xs: List[int] = []          # error, at module scope AND inside a def
n: int = 5                  # fine
```

The identical annotation on a FIELD works — `self.d: Dict[str, int] = {}` was
fixed earlier in the session — which is what makes this one confusing to hit.

## Cause

`PyParseStatement`'s annotated-assignment branch matched on
`Tokens[TokPos + 2].Kind = tkAssign`, i.e. it required the annotation to be
exactly ONE token, and read it with `PyTypeFromTokenIndex`, the narrow reader
that knows only int/float/bool/str/class.

Same class of defect as the method-parameter one fixed earlier: two readers
for one grammar, and the narrow one wins wherever it is still wired up. The
rich reader is `PyAnnTypeAt` (Optional / Callable / Any / List / Dict / set /
forward refs), which is what fields and parameters already use.

## Fix

Read the annotation with `PyAnnTypeAt`, then require `=` at whatever token it
stopped on. Also records the annotation's class identity on the new symbol,
which the single-token path never did.

## Gate

`test-nilpy` green with the container-annotation cases added to the dict
test + `--tier quick` + self-host byte-identical + `make fpc-check`.
