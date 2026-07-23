---
track: N
prio: 45
type: bug
---

# NilPy: dict insert/lookup is O(N), not O(1) — quadratic build, drives uforth O(N²)

A NilPy `dict` insert is **super-linear**: building N distinct keys is O(N²)
time (each insert appears O(N) — linear scan and/or non-amortised realloc),
where CPython's hashed dict is O(1) amortised.

## Evidence
```
dict build (d["w"+str(i)] = i), wall clock:
  n=2000  0.03s
  n=4000  0.15s   (5x for 2x n)
  n=8000  0.56s   (3.7x for 2x n)   -> ~O(N²)
```
uforth compiling N word definitions (each `define_word` does several dict
inserts: `self.dict`, `wordlists`, `xt_table`) is O(N²) TIME under pxx but O(N)
under CPython — same source, so this is the pxx dict impl, not uforth's
algorithm. (CPython uforth: 1k/2k/4k defs = 0.26/0.33/0.40s, flat RSS.)

## Why it also inflates memory (see [[bug-a-runtime-variant-heap-grows-unbounded]])
Each O(N)-growing dict realloc frees a >512 B buffer that the mmap arena's
large-block FreeList does not reuse for the next-bigger request (exact-size
bins only go to 512 B), so peak RSS is O(N²) with the arena but LINEAR with the
libc heap (which coalesces/reuses). Two levers: make dict O(1) (hashed,
amortised) here; and/or improve arena large-block reuse (that ticket).

## Fix direction
Give TPyDict a real hash table with amortised-doubling growth (Track N/pylib),
so insert/lookup are O(1). This removes the dominant uforth compile-time cost
AND most of the realloc churn feeding the arena RSS blowup.
