# SPDX-License-Identifier: 0BSD
"""mimic_glob -- CPython's `glob` module: pathnames matching a shell pattern.

Reached as `import glob` (`note: glob -> mimic_glob (shim, subset)`). Plain
Python over os.listdir, which compiles to native code like any program does.

SCOPE. glob(pathname, recursive=False), iglob (a list here, not an iterator;
every caller that loops over it or sorts it gets the same thing), escape(),
has_magic(). The pattern language is fnmatch's: `*`, `?`, `[seq]`, `[!seq]`
with `a-z` ranges, and `**` when recursive=True. As in CPython, a name that
starts with `.` matches only a pattern segment that starts with `.`, results
come in directory order (CPython does not sort either), and a pattern with no
magic characters returns itself if the path exists.

DELIBERATELY ABSENT: root_dir=, dir_fd=, include_hidden= (3.10+/3.11+), and
case folding (fnmatch folds case only on Windows). Asked for by sysdash
(`/sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq`, `hwmon*`,
`temp*_label`), which is what test/lib_mimic_glob.npy checks against CPython.
"""
import os


def has_magic(s):
    for ch in s:
        if ch == "*" or ch == "?" or ch == "[":
            return True
    return False


def escape(pathname):
    out = ""
    for ch in pathname:
        if ch == "*" or ch == "?" or ch == "[":
            out = out + "[" + ch + "]"
        else:
            out = out + ch
    return out


def _class_end(pat, i):
    """Index just past the `]` closing the class that opens at pat[i], or -1
    when it never closes (then `[` is an ordinary character, as in fnmatch)."""
    j = i + 1
    if j < len(pat) and pat[j] == "!":
        j += 1
    if j < len(pat) and pat[j] == "]":
        j += 1
    while j < len(pat) and pat[j] != "]":
        j += 1
    if j >= len(pat):
        return -1
    return j + 1


def _class_has(pat, lo, hi, ch):
    """Does the class body pat[lo:hi] (no brackets, no `!`) contain ch?"""
    k = lo
    while k < hi:
        if k + 2 < hi and pat[k + 1] == "-":
            if pat[k] <= ch and ch <= pat[k + 2]:
                return True
            k += 3
        else:
            if pat[k] == ch:
                return True
            k += 1
    return False


def _match(name, pat):
    """fnmatch.fnmatchcase(name, pat): iterative, with one backtrack point for
    the most recent `*`, so a pattern costs O(len(name) * len(pat)) at worst."""
    n = 0
    p = 0
    star_p = -1
    star_n = 0
    while n < len(name):
        ok = False
        if p < len(pat):
            c = pat[p]
            if c == "*":
                star_p = p
                star_n = n
                p += 1
                continue
            if c == "?":
                ok = True
                p += 1
            elif c == "[" and _class_end(pat, p) > 0:
                end = _class_end(pat, p)
                lo = p + 1
                neg = False
                if pat[lo] == "!":
                    neg = True
                    lo += 1
                hit = _class_has(pat, lo, end - 1, name[n])
                if hit != neg:
                    ok = True
                    p = end
            elif c == name[n]:
                ok = True
                p += 1
        if ok:
            n += 1
        elif star_p >= 0:
            star_n += 1
            n = star_n
            p = star_p + 1
        else:
            return False
    while p < len(pat) and pat[p] == "*":
        p += 1
    return p == len(pat)


def _exists(path):
    return os.path.exists(path) or os.path.isdir(path)


def _list(dirname):
    try:
        return os.listdir(dirname if dirname else ".")
    except OSError:
        return []


def _match_in(dirname, pattern):
    """Names in dirname matching one pattern segment, hidden names excluded
    unless the pattern itself starts with a dot."""
    out = []
    for name in _list(dirname):
        if name[:1] == "." and pattern[:1] != ".":
            continue
        if _match(name, pattern):
            out.append(name)
    return out


def _walk(dirname, dirs_only):
    """What `**` matches under dirname, relative to it: dirname itself first
    (as ''), then each entry depth first, hidden ones skipped. A `**` in the
    middle of a pattern walks directories only; a final `**` also yields files,
    as CPython's does."""
    out = [""]
    for name in _list(dirname):
        if name[:1] == ".":
            continue
        full = os.path.join(dirname, name) if dirname else name
        if os.path.isdir(full):
            for sub in _walk(full, dirs_only):
                out.append(os.path.join(name, sub) if sub else name)
        elif not dirs_only:
            out.append(name)
    return out


def glob(pathname, recursive=False):
    dirname, basename = os.path.split(pathname)
    if not has_magic(pathname):
        if basename:
            if _exists(pathname):
                return [pathname]
        elif os.path.isdir(dirname):
            return [pathname]
        return []
    if not dirname:
        if recursive and basename == "**":
            return [p for p in _walk("", False) if p]
        return _match_in("", basename)
    if dirname != pathname and has_magic(dirname):
        dirs = [d for d in glob(dirname, recursive) if os.path.isdir(d)]
    else:
        dirs = [dirname]
    out = []
    for d in dirs:
        if not basename:
            if os.path.isdir(d):
                out.append(os.path.join(d, ""))
        elif recursive and basename == "**":
            for sub in _walk(d, False):
                out.append(os.path.join(d, sub))
        elif has_magic(basename):
            for name in _match_in(d, basename):
                out.append(os.path.join(d, name))
        else:
            full = os.path.join(d, basename)
            if _exists(full):
                out.append(full)
    return out


def iglob(pathname, recursive=False):
    return glob(pathname, recursive)
