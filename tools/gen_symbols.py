#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Generate agents/codemap/symbols.md — a concise "helicopter view" of the compiler
source so a human or agent can navigate by reading one file instead of grepping
the large .inc files.

Captures, per source file:
  - routines: function/procedure signatures (multi-line joined) + the brace/line
    doc-comment immediately above, with line numbers;
  - constants: NAME = value (in const sections), value truncated;
  - types: NAME = ... ; records list their field names; enums list members;
  - globals: NAME : type (top-level var sections).

Best-effort line scanner (Pascal is regular at the declaration level), not a full
parser — odd constructs may be missed or a routine-local var may leak in. It's a
*locating aid*: line numbers drift between regens, so verify before editing.
Re-run with `make symbols`. Stdlib only, no external deps.
"""
import glob
import os
import re
import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

FILES = sorted(glob.glob("compiler/*.inc")) + sorted(glob.glob("compiler/*.pas"))
OUT = "agents/codemap/symbols.md"

ROUTINE_RE = re.compile(r"^\s*(function|procedure)\s+([A-Za-z_][\w.]*)", re.I)
SECTION_RE = re.compile(r"^(const|type|var|begin|implementation|interface|asm)\b", re.I)
CONST_RE = re.compile(r"^\s*([A-Za-z_]\w*)\s*=\s*(.+?);")
TYPE_RE = re.compile(r"^\s*([A-Za-z_]\w*)\s*=\s*(.*)$")
VAR_RE = re.compile(r"^\s*([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s*:\s*(.+?);")


def strip_line_comment(s):
    return re.sub(r"//.*$", "", s)


def cut_signature(s):
    depth = 0
    for i, ch in enumerate(s):
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        elif ch == ";" and depth <= 0:
            return s[: i + 1]
    return s


def collapse(s):
    return re.sub(r"\s+", " ", s).strip()


def doc_above(lines, idx):
    j = idx - 1
    buf = []
    while j >= 0:
        s = lines[j].strip()
        if s == "":
            break
        if s.startswith("{") or s.startswith("//") or s.startswith("(*") or s.endswith("}"):
            buf.append(s)
            j -= 1
        else:
            break
    if not buf:
        return ""
    buf.reverse()
    txt = re.sub(r"\{|\}|\(\*|\*\)|//+", " ", " ".join(buf))
    txt = collapse(txt)
    return txt[:90] + ("…" if len(txt) > 90 else "")


def scan(path):
    lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
    n = len(lines)
    consts, types, gvars, routines = [], [], [], []
    mode = None
    block_comment = False
    after_header = False
    i = 0
    while i < n:
        raw = lines[i]
        stripped = raw.strip()

        if block_comment:
            if "}" in raw:
                block_comment = False
            i += 1
            continue
        if raw.count("{") > raw.count("}") and not stripped.startswith("{$"):
            block_comment = True

        code = strip_line_comment(raw)
        cstr = code.strip()

        m = ROUTINE_RE.match(code)
        if m:
            sig_lines = [strip_line_comment(lines[i]).rstrip()]
            j = i
            while ";" not in cut_signature(collapse(" ".join(sig_lines))) and j + 1 < n:
                j += 1
                sig_lines.append(strip_line_comment(lines[j]).rstrip())
                if j - i > 8:
                    break
            joined = collapse(" ".join(sig_lines))
            sig = cut_signature(joined)
            forward = bool(re.search(r";\s*forward\s*;?\s*$", joined, re.I))
            routines.append((i + 1, sig, doc_above(lines, i), forward))
            mode = None
            after_header = not forward
            i = j + 1
            continue

        sm = SECTION_RE.match(cstr)
        if sm:
            kw = sm.group(1).lower()
            if kw in ("const", "type", "var"):
                mode = None if after_header else kw
            else:
                mode = None
                after_header = False
            i += 1
            continue

        if mode == "const":
            cm = CONST_RE.match(code)
            if cm:
                v = collapse(cm.group(2))
                consts.append((i + 1, cm.group(1), v[:48] + ("…" if len(v) > 48 else "")))
        elif mode == "type":
            tm = TYPE_RE.match(code)
            if tm:
                name, rhs = tm.group(1), collapse(tm.group(2))
                if re.match(r"(packed\s+)?record\b", rhs, re.I) or re.search(r"\bclass\b", rhs, re.I):
                    fields, k = [], i + 1
                    while k < n and not re.match(r"^\s*end\b", lines[k]):
                        fm = VAR_RE.match(strip_line_comment(lines[k]))
                        if fm and not re.match(r"^\s*(function|procedure|case|private|public|protected|published)\b", lines[k].strip(), re.I):
                            fields += [nm.strip() for nm in fm.group(1).split(",")]
                        k += 1
                        if k - i > 300:
                            break
                    kind = "record" if "record" in rhs.lower() else "class"
                    types.append((i + 1, name, kind, fields))
                    i = k + 1
                    continue
                elif rhs.startswith("("):
                    types.append((i + 1, name, "enum", re.findall(r"[A-Za-z_]\w*", rhs)[:12]))
                else:
                    types.append((i + 1, name, "alias", rhs[:48]))
        elif mode == "var":
            vm = VAR_RE.match(code)
            if vm:
                t = collapse(vm.group(2))
                gvars.append((i + 1, collapse(vm.group(1)), t[:48] + ("…" if len(t) > 48 else "")))

        i += 1
    return consts, types, gvars, routines


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
    srclines = sum(len(open(f, errors="replace").read().split("\n")) for f in FILES)
    nroutines = 0
    body = []
    for path in FILES:
        consts, types, gvars, routines = scan(path)
        if not (consts or types or gvars or routines):
            continue
        body.append(f"\n## {path}\n")
        if consts:
            body.append("\n### Constants\n")
            body += [f"- `{nm}` = {v}  :{ln}" for ln, nm, v in consts]
        if types:
            body.append("\n### Types\n")
            for ln, nm, kind, extra in types:
                if kind in ("record", "class"):
                    body.append(f"- `{nm}` ({kind}: {', '.join(extra)})  :{ln}")
                elif kind == "enum":
                    body.append(f"- `{nm}` (enum: {', '.join(extra)})  :{ln}")
                else:
                    body.append(f"- `{nm}` = {extra}  :{ln}")
        if gvars:
            body.append("\n### Globals\n")
            body += [f"- `{nm}` : {t}  :{ln}" for ln, nm, t in gvars]
        if routines:
            body.append("\n### Routines\n")
            for ln, sig, doc, fwd in routines:
                nroutines += 1
                tail = f"  — {doc}" if doc else ""
                fw = " *(fwd)*" if fwd else ""
                body.append(f"- `{sig}`{fw}  :{ln}{tail}")

    header = (
        "# PXX code map\n\n"
        f"_Generated by `make symbols` (tools/gen_symbols.py). Stamp: {stamp}, "
        f"{srclines} source lines, {nroutines} routines._\n\n"
        "Per-file index of constants, types (with fields), globals, and routine "
        "signatures (with the doc-comment above each). **Locating aid only — verify "
        "the line before editing; line numbers drift between regens.** The `.inc` "
        "files are `{$include}`d into one unit, so symbols share a single flat "
        "namespace (a name has one definition project-wide).\n"
    )
    open(OUT, "w").write(header + "\n".join(body) + "\n")
    print(f"wrote {OUT} ({nroutines} routines)")


if __name__ == "__main__":
    main()
