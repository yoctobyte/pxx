#!/usr/bin/env python3
"""Every function a crtl header declares must be REACHABLE from that header.

WHY THIS EXISTS. The C preprocessor auto-pulls a crtl module by SIBLING NAME:
finishing `include/foo.h` pulls `src/foo.c`, and nothing else. A function
declared in `foo.h` but defined in `bar.c` is therefore never emitted for a
program that includes only `<foo.h>` -- and the failure is not a link error.
The prototype keeps its default soname, the ELF writer emits a DT_NEEDED nobody
asked for, and glibc (which has the same symbol) RESOLVES it. A libc-free build
silently runs against glibc, where the two agree on the name and not necessarily
on the ABI: glibc's imaxdiv returns its 16-byte struct in rax:rdx where pxx
passes a hidden destination pointer, giving a `rep movsb` from null far from any
cause.

That class has now bitten three times, and been fixed three different ways --
a bridge .c for <sys/socket.h>, `__crtl_`-prefixed renames for <math.h>, moving
the functions for <inttypes.h>. Three precedents that look nothing alike is how
the fourth one stays invisible. This is the rule they all satisfy, checked.

WHAT IT MODELS. Not "does foo.h have a foo.c" -- that is too strict, and two of
the three fixes above legitimately violate it. It walks the real closure the
preprocessor walks, from each header as a root:

    header H  -> every header H includes            (include edge)
    header H  -> src/H.c, if it exists              (sibling auto-pull)
    a pulled .c -> every header IT includes         (and so on, transitively)

A header passes when every function it declares is defined somewhere in that
closure. A function declared but defined NOWHERE in crtl is fine and ignored:
that is a PAL entry point (`__pxx_*`) or a genuinely system-provided symbol.
Only "crtl defines this, and the caller cannot reach it" is a finding.

Exit 0 = clean, 1 = findings (printed with the header, the function, and where
the definition actually lives).
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INC = os.path.join(ROOT, "lib", "crtl", "include")
SRC = os.path.join(ROOT, "lib", "crtl", "src")

# A C keyword or type word in front of `(` is never a call or a declaration we
# care about; without this, `if (x)` and `sizeof (t)` read as functions.
NOT_A_FUNCTION = {
    "if", "for", "while", "switch", "return", "sizeof", "do", "else",
    "typedef", "struct", "union", "enum", "case", "defined", "static",
    "extern", "inline", "const", "volatile", "register", "goto", "break",
    "continue", "_Static_assert", "__attribute__", "__asm__", "asm",
}


def strip_noise(text):
    """Remove comments and string/char literals, keeping newlines so that
    line-anchored patterns still work."""
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append("".join(ch if ch == "\n" else " " for ch in text[i:j]))
            i = j
        elif c == "/" and i + 1 < n and text[i + 1] == "/":
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        elif c in "\"'":
            q, j = c, i + 1
            while j < n and text[j] != q:
                j += 2 if text[j] == "\\" else 1
            j = min(j + 1, n)
            out.append("".join(ch if ch == "\n" else " " for ch in text[i:j]))
            i = j
        else:
            out.append(c)
            i += 1
    return "".join(out)


def match_paren(text, open_idx):
    """Index just past the ')' matching the '(' at open_idx, or -1."""
    depth = 0
    for i in range(open_idx, len(text)):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return i + 1
    return -1


CANDIDATE = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*\(")


def scan(text, want_definition):
    """Names followed by a parameter list that ends in '{' (a definition) or
    ';' (a declaration). Same scanner both ways so the two sides cannot drift."""
    found = set()
    clean = strip_noise(text)
    for m in CANDIDATE.finditer(clean):
        name = m.group(1)
        if name in NOT_A_FUNCTION:
            continue
        end = match_paren(clean, m.end() - 1)
        if end < 0:
            continue
        rest = clean[end:].lstrip()
        if not rest:
            continue
        if want_definition:
            if rest[0] == "{":
                found.add(name)
        else:
            if rest[0] == ";":
                found.add(name)
    return found


def includes_of(text):
    return re.findall(r'#\s*include\s*[<"]([^>"]+)[>"]', strip_noise(text))


def read(path):
    with open(path, errors="replace") as f:
        return f.read()


def main():
    if not os.path.isdir(INC) or not os.path.isdir(SRC):
        print("crtl-reachability: lib/crtl not found -- run from the repo", file=sys.stderr)
        return 2

    headers, sources = {}, {}
    for base, store in ((INC, headers), (SRC, sources)):
        for dirpath, _, names in os.walk(base):
            for nm in names:
                if nm.endswith(".h") if store is headers else nm.endswith(".c"):
                    p = os.path.join(dirpath, nm)
                    store[os.path.relpath(p, base)] = read(p)

    # name -> set of .c files defining it
    defined = {}
    for rel, text in sources.items():
        for nm in scan(text, want_definition=True):
            defined.setdefault(nm, set()).add(rel)

    def closure(root_header):
        """.c files the preprocessor ends up pulling, starting at root_header."""
        seen_h, pulled_c, queue = set(), set(), [root_header]
        while queue:
            h = queue.pop()
            if h in seen_h or h not in headers:
                continue
            seen_h.add(h)
            for inc in includes_of(headers[h]):
                queue.append(inc)
            sib = h[:-2] + ".c"
            if sib in sources and sib not in pulled_c:
                pulled_c.add(sib)
                for inc in includes_of(sources[sib]):
                    queue.append(inc)
        return pulled_c

    findings = []
    for rel in sorted(headers):
        reach = closure(rel)
        for nm in sorted(scan(headers[rel], want_definition=False)):
            homes = defined.get(nm)
            if not homes:
                continue          # PAL entry point or genuinely system-provided
            if homes & reach:
                continue
            findings.append((rel, nm, sorted(homes)))

    if not findings:
        print("crtl-reachability: OK -- %d headers, %d modules, every declared "
              "function reachable from its own header" % (len(headers), len(sources)))
        return 0

    print("crtl-reachability: %d unreachable declaration(s)\n" % len(findings))
    for rel, nm, homes in findings:
        print("  <%s> declares %s(), defined in %s" % (rel, nm, ", ".join(homes)))
    print("\nA program that includes only that header will NOT get the definition.")
    print("It will silently import the symbol from the system C library instead.")
    print("Fix by one of: move the definition to the header's sibling .c; make the")
    print("header include the header whose sibling .c defines it; or add a bridge")
    print("sibling .c that does nothing but include that header (see")
    print("lib/crtl/src/sys/socket.c for the guard-order trap that shape has).")
    return 1


if __name__ == "__main__":
    sys.exit(main())
