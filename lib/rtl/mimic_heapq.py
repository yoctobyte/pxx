# SPDX-License-Identifier: 0BSD
"""mimic_heapq -- CPython's `heapq` module: a list used as a binary min-heap.

Reached as `import heapq`, which the NilPy import resolver maps to this file and
announces (`note: heapq -> mimic_heapq (shim)`). Not named `heapq.py`: no file
in this tree carries an upstream package name, so the tree always says what a
thing is, and `--no-shims` can refuse the whole category by the `mimic_`
mapping rather than by a list of names. Same reasoning as [[mimic_bisect]],
which is this shim's closest sibling -- both are algorithms over a plain list.

WHY THIS ONE IS SAFE TO WRITE COMPLETE, and it is the bisect argument exactly:
`heapq` is an algorithm, not a platform surface. It touches nothing but the list
handed to it, it is fully specified by CPython's docs, and there is no backend
to be wrong about and no version drift to track. So "complete" is achievable
here and verifiable by comparing VALUES against CPython, which
test/test_nilpy_mimic_heapq.npy does.

THE HEAP LAYOUT IS PART OF THE OBSERVABLE BEHAVIOUR, NOT AN IMPLEMENTATION
DETAIL, WHICH IS WHY THE SIFT ALGORITHMS HERE MATCH CPYTHON'S RATHER THAN BEING
MERELY CORRECT. `heapq` does not promise an order for equal elements, but it
does hand you the list, and real code prints it, compares it, and persists it.
Any correct min-heap satisfies `heap[0] == min(heap)`; only CPython's own
sift-up/sift-down pair reproduces its exact array. A textbook heapify that
happens to satisfy the invariant would make every whole-list assertion in a
differential test fail for no defect -- and then the test gets weakened to
popping elements one at a time, which is the assertion that cannot see a layout
bug at all. So: same algorithms, and the test compares the whole list.

`_siftdown` and `_siftup` keep their CPython names and their leading underscore
deliberately. They are private, but they are private names that real code
reaches for (CPython's own `Lib/queue.py` does not, but third-party heap code
does), and a shim whose private helpers are spelled differently fails in a way
that reads as a missing feature rather than as a deliberate subset.

ABSENT, AND SAID OUT LOUD RATHER THAN APPROXIMATED: `merge`. It is the one
function in this module with a LAZINESS contract -- it returns an iterator over
inputs it must not exhaust -- so the cheap version (collect everything, sort,
return a list) is wrong in the one property callers use it for, on exactly the
infinite or expensive iterables it exists to serve. Nothing in any corpus here
calls it. A missing name raises at import and is found in one run; a `merge`
that silently materialises its inputs is found when something hangs.
"""


def _siftdown(heap, startpos, pos):
    """Move heap[pos] UP toward startpos until its parent is no larger."""
    newitem = heap[pos]
    while pos > startpos:
        parentpos = (pos - 1) >> 1
        parent = heap[parentpos]
        if newitem < parent:
            heap[pos] = parent
            pos = parentpos
        else:
            break
    heap[pos] = newitem


def _siftup(heap, pos):
    """Move heap[pos] DOWN to a leaf, then sift the moved item back up.

    The trailing _siftdown is not redundant and is where a hand-rolled heapify
    diverges from CPython: this descends to a LEAF unconditionally, choosing the
    smaller child, and only then restores the invariant upward. Comparing the
    item against both children on the way down instead is also a valid heap and
    produces a different array.
    """
    endpos = len(heap)
    startpos = pos
    newitem = heap[pos]
    childpos = 2 * pos + 1
    while childpos < endpos:
        rightpos = childpos + 1
        if rightpos < endpos and not heap[childpos] < heap[rightpos]:
            childpos = rightpos
        heap[pos] = heap[childpos]
        pos = childpos
        childpos = 2 * pos + 1
    heap[pos] = newitem
    _siftdown(heap, startpos, pos)


def heappush(heap, item):
    """Push item onto heap, keeping the heap invariant."""
    heap.append(item)
    _siftdown(heap, 0, len(heap) - 1)


def heappop(heap):
    """Pop and return the smallest item; the heap stays a heap."""
    lastelt = heap.pop()
    if len(heap) > 0:
        returnitem = heap[0]
        heap[0] = lastelt
        _siftup(heap, 0)
        return returnitem
    return lastelt


def heapreplace(heap, item):
    """Pop and return the smallest item, AND push item. One sift, not two.

    Note the order: this returns the old smallest even when `item` is smaller
    than it, so the result can be larger than anything left in the heap. That
    is CPython's contract and `heappushpop` is the other order.
    """
    returnitem = heap[0]
    heap[0] = item
    _siftup(heap, 0)
    return returnitem


def heappushpop(heap, item):
    """Push item, then pop and return the smallest -- the other order."""
    if len(heap) > 0 and heap[0] < item:
        item, heap[0] = heap[0], item
        _siftup(heap, 0)
    return item


def heapify(x):
    """Transform list x into a heap, in place, in linear time."""
    n = len(x)
    i = n // 2 - 1
    while i >= 0:
        _siftup(x, i)
        i = i - 1


def nsmallest(n, iterable, key=None):
    """The n smallest elements, as a list, smallest first.

    Implemented by sorting rather than by a bounded heap: the heap version wins
    only when n is far smaller than the input, and being RIGHT about ties
    matters more here than being asymptotically better. `sorted` is stable, so
    equal elements come out in input order, which is what CPython's own
    documented behaviour for this function gives.
    """
    if n <= 0:
        return []
    items = list(iterable)
    if key is None:
        items.sort()
    else:
        items.sort(key=key)
    return items[:n]


def nlargest(n, iterable, key=None):
    """The n largest elements, as a list, largest first."""
    if n <= 0:
        return []
    items = list(iterable)
    if key is None:
        items.sort()
    else:
        items.sort(key=key)
    items.reverse()
    return items[:n]
