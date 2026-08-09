#!/usr/bin/env python3
"""Differential probe: lib/pcl's reportlab mimic vs REAL reportlab.

The mimic is a clean-room reimplementation over the vendored pdfgen writer, so
every metric, default and coordinate convention in it is an independent guess
that happens to look right. Validity is not agreement: a PDF can be structurally
perfect and still place text at the wrong baseline. This runs ONE script through
both implementations and compares where the glyphs actually landed.
(feature-lib-reportlab-fidelity-vs-oracle)

Comparison level is deliberate. Byte-identical PDFs are the wrong bar — both
embed timestamps and neither canonicalises object order — so this compares the
EXTRACTED TEXT plus per-word bounding boxes via `pdftotext -bbox`, which is what
"matching" means for a drawing API.

Requires the oracle:  tools/install_lib_candidates.sh reportlab
Usage:                tools/reportlab_diff.py [case.py ...]     (default: all built-in cases)
"""
import os, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORACLE = os.path.join(ROOT, "library_candidates", "reportlab", "src")
PXX = os.path.join(ROOT, "stable_linux_amd64", "default", "pinned")

# Each case is written against the mimic's documented subset. Keep them in that
# subset on purpose: this probe measures FIDELITY, not coverage — a case using
# something the mimic refuses would fail loudly and tell us nothing new.
CASES = {
    "text_fonts": '''
c.setFont("Helvetica", 12)
c.drawString(72, 720, "Hello world")
c.setFont("Helvetica", 24)
c.drawString(72, 680, "Bigger text")
c.setFont("Times-Roman", 14)
c.drawString(100, 640, "Times at 14")
c.setFont("Courier", 10)
c.drawString(150, 600, "Courier 10")
''',
    "many_fonts": '''
c.setFont("Helvetica", 11)
c.drawString(72, 720, "Helvetica")
c.setFont("Helvetica-Bold", 11)
c.drawString(72, 700, "HelveticaBold")
c.setFont("Times-Roman", 11)
c.drawString(72, 680, "TimesRoman")
c.setFont("Times-Bold", 11)
c.drawString(72, 660, "TimesBold")
c.setFont("Courier", 11)
c.drawString(72, 640, "Courier")
''',
    "positions": '''
c.setFont("Helvetica", 10)
c.drawString(0, 800, "topleft")
c.drawString(500, 800, "topright")
c.drawString(0, 10, "bottomleft")
c.drawString(250, 400, "middle")
''',
}

WORD = re.compile(r'<word xMin="([\d.]+)" yMin="([\d.]+)" '
                  r'xMax="([\d.]+)" yMax="([\d.]+)">([^<]*)</word>')


def words(pdf, tmp):
    xml = os.path.join(tmp, os.path.basename(pdf) + ".xml")
    subprocess.run(["pdftotext", "-bbox", pdf, xml], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    s = open(xml, encoding="utf-8", errors="replace").read()
    return [(m.group(5), float(m.group(1)), float(m.group(2)),
             float(m.group(3)), float(m.group(4))) for m in WORD.finditer(s)]


def run_case(name, body, tmp, tol):
    ref_pdf = os.path.join(tmp, name + "_ref.pdf")
    cand_pdf = os.path.join(tmp, name + "_cand.pdf")
    head = 'from reportlab.pdfgen import canvas\nc = canvas.Canvas("%s")\n'
    tail = 'c.showPage()\nc.save()\n'

    ref_py = os.path.join(tmp, name + "_ref.py")
    open(ref_py, "w").write(head % ref_pdf + body + tail)
    env = dict(os.environ, PYTHONPATH=ORACLE)
    subprocess.run([sys.executable, ref_py], check=True, env=env)

    cand_py = os.path.join(tmp, name + "_cand.py")
    open(cand_py, "w").write(head % cand_pdf + body + tail)
    exe = os.path.join(tmp, name + "_cand")
    r = subprocess.run([PXX, "-Fu" + os.path.join(ROOT, "lib", "pcl"), cand_py, exe],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return name, "COMPILE FAIL: " + (r.stdout + r.stderr).strip().split("\n")[-1]
    r = subprocess.run([exe], capture_output=True, text=True)
    if r.returncode != 0:
        return name, "RUN FAIL: exit %d (signal %d)" % (r.returncode, -r.returncode)

    ref, cand = words(ref_pdf, tmp), words(cand_pdf, tmp)
    if len(ref) != len(cand):
        return name, "word count %d vs %d: %r vs %r" % (
            len(ref), len(cand), [w[0] for w in ref], [w[0] for w in cand])
    worst_pos = worst_w = 0.0
    for a, b in zip(ref, cand):
        if a[0] != b[0]:
            return name, "text %r vs %r" % (a[0], b[0])
        worst_pos = max(worst_pos, abs(b[1] - a[1]), abs(b[2] - a[2]))
        worst_w = max(worst_w, abs((b[3] - b[1]) - (a[3] - a[1])))
    if worst_pos > tol or worst_w > tol:
        return name, "pos delta %.6f pt, width delta %.6f pt (tol %.6f)" % (
            worst_pos, worst_w, tol)
    return name, "ok (%d words, worst delta %.6f pt)" % (len(ref), worst_pos)


def main():
    if not os.path.isdir(ORACLE):
        print("reportlab oracle absent — run: tools/install_lib_candidates.sh reportlab")
        return 77          # distinct from pass/fail: nothing was compared
    # 1e-3 pt is ~350nm on paper: far below anything renderable, and above
    # pdftotext's own printed precision (it emits ~5 decimal places).
    tol = 1e-3
    names = sys.argv[1:] or sorted(CASES)
    bad = 0
    with tempfile.TemporaryDirectory() as tmp:
        for n in names:
            name, msg = run_case(n, CASES[n], tmp, tol)
            print("%-12s %s" % (name, msg))
            if not msg.startswith("ok"):
                bad += 1
    print("REPORTLAB DIFF: %s" % ("OK" if bad == 0 else "%d case(s) diverged" % bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
