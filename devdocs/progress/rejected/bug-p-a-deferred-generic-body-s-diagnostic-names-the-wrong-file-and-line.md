---
slug: bug-p-a-deferred-generic-body-s-diagnostic-names-the-wrong-file-and-line
title: "DUPLICATE of bug-p-a-specialized-body-reports-errors-in-the-wrong-file"
track: P
prio: 60
type: duplicate
status: rejected
blocked-by: []
owner: ""
summary: "Duplicate. Filed by the coordinator from frankB's rung-6b evidence within minutes of frank-rust filing the same defect from the rtl-generics probe, neither having seen the other. Merged into bug-p-a-specialized-body-reports-errors-in-the-wrong-file, which now carries both instances and is raised to p60."
---

# Duplicate — see [[bug-p-a-specialized-body-reports-errors-in-the-wrong-file]]

All evidence from this ticket is folded into that one, including frankB's grep
counts (`TKey`: zero occurrences in the file the error names, 65 in the file it
came from) and the p60 argument (a false file attribution is not diagnostic
parity; it misroutes triage on the corpus campaign's own path).

**Kept as a record rather than deleted**, because the duplication is itself worth
seeing: two agents hit the same defect from two different corpora within minutes,
which is evidence about the bug's reach, and it is also a coordination miss of
mine — I filed from a worker's report without checking whether another worker had
one in flight.
