#!/usr/bin/env python3
"""Lint the compiler's OWN Pascal source for brace-comment hazards.

The pascal26 lexer runs with {$nestedcomments on} by default (FPC 3.2.2 parity,
lexer.inc:642). Under nesting, a LONE `{` or `}` in the prose of a `{ ... }`
comment shifts the nesting counter, so the comment closes at the wrong `}` (often
runs to EOF) — surfacing at build time as a cryptic `unexpected character` at a
bogus, past-EOF line number. String/char literals and `//` / `(* *)` comments are
inert *inside* a `{ }` comment (they are just comment text), so the scan only
tracks `{`/`}` while inside a brace comment.

De-facto convention (matches how FPC's own source is written): keep braces out of
`{ }` comments — use `(* *)` or `//` for brace-containing prose, or balance them.

Exit 1 if any ERROR (unterminated brace comment) is found. WARN-level findings
(interior braces in a `{ }` comment) do not fail by default; pass --strict to
promote them to errors.
"""
import sys, glob, argparse

def scan(text):
    """Yield (level, line, col, msg) findings for one file's text.

    Emulates the nesting lexer state machine: NORMAL / string / char / line
    comment / paren-star comment / brace comment (with a stack of open positions
    for nesting)."""
    findings = []
    i, n = 0, len(text)
    line, col = 1, 1
    brace_stack = []          # (line, col) of each open `{` while in a brace comment
    interior_braces = []      # extra `{`/`}` seen inside the current top-level brace comment
    def adv(ch):
        nonlocal line, col
        if ch == '\n':
            line += 1; col = 1
        else:
            col += 1
    while i < n:
        c = text[i]
        # ---- inside a brace comment: only { } matter ----
        if brace_stack:
            if c == '{':
                brace_stack.append((line, col))
                if len(brace_stack) > 1:
                    interior_braces.append((line, col, '{'))
                adv(c); i += 1; continue
            if c == '}':
                brace_stack.pop()
                if brace_stack:
                    interior_braces.append((line, col, '}'))
                else:
                    # top-level brace comment just closed; report interior braces
                    for (bl, bc, bch) in interior_braces:
                        findings.append(('WARN', bl, bc,
                            f"`{bch}` inside a {{ }} comment (nested-comment hazard; use (* *) or //)"))
                    interior_braces = []
                adv(c); i += 1; continue
            adv(c); i += 1; continue
        # ---- NORMAL state ----
        if c == "'":                       # Pascal string/char literal
            adv(c); i += 1
            while i < n:
                if text[i] == "'":
                    if i + 1 < n and text[i+1] == "'":   # '' escaped quote
                        adv(text[i]); i += 1; adv(text[i]); i += 1; continue
                    adv(text[i]); i += 1; break
                adv(text[i]); i += 1
            continue
        if c == '/' and i + 1 < n and text[i+1] == '/':   # // line comment
            while i < n and text[i] != '\n':
                adv(text[i]); i += 1
            continue
        if c == '(' and i + 1 < n and text[i+1] == '*':   # (* *) comment (no-nest in FPC)
            adv(c); i += 1; adv(text[i]); i += 1
            while i < n:
                if text[i] == '*' and i + 1 < n and text[i+1] == ')':
                    adv(text[i]); i += 1; adv(text[i]); i += 1; break
                adv(text[i]); i += 1
            continue
        if c == '{':                        # open a brace comment
            brace_stack.append((line, col))
            interior_braces = []
            adv(c); i += 1; continue
        adv(c); i += 1
    if brace_stack:
        bl, bc = brace_stack[0]
        findings.append(('ERROR', bl, bc,
            "unterminated { } comment (a lone brace in the prose shifted the "
            "nesting counter — this is what crashes self-host as 'unexpected character')"))
    return findings

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('paths', nargs='*',
                    help='files to lint (default: compiler/*.inc compiler/*.pas)')
    ap.add_argument('--strict', action='store_true',
                    help='promote WARN (interior braces) to errors')
    args = ap.parse_args()
    paths = args.paths or sorted(glob.glob('compiler/*.inc') + glob.glob('compiler/*.pas'))
    errors = warns = 0
    for p in paths:
        try:
            with open(p, encoding='utf-8', errors='replace') as f:
                text = f.read()
        except OSError as e:
            print(f"{p}: cannot read: {e}", file=sys.stderr); continue
        for (level, l, c, msg) in scan(text):
            if level == 'ERROR' or args.strict:
                errors += 1; tag = 'error'
            else:
                warns += 1; tag = 'warning'
            print(f"{p}:{l}:{c}: {tag}: {msg}")
    total = len(paths)
    print(f"lint_comment_braces: {total} files, {errors} error(s), {warns} warning(s)",
          file=sys.stderr)
    sys.exit(1 if errors else 0)

if __name__ == '__main__':
    main()
