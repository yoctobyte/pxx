# SPDX-License-Identifier: Zlib
"""`from tkhtmlview import HTMLScrolledText` -- a Tk widget that displays HTML.

THE SUBSET, stated plainly: this renders a document's STRUCTURE into a Text
widget's tags -- headings, paragraphs, lists, code, blockquotes, emphasis,
links -- and ignores everything else (CSS, tables, images, forms). Real
tkhtmlview is not much wider, but it is wider, and a document leaning on what
is missing here will look flat rather than wrong.

It is built on lib/pcl/tkinter's Text and Scrollbar: no HTML engine, no
images, one pass over the markup. Written for songformatter's help window,
which feeds it the output of lib/rtl/markdown.
"""

import tkinter as tk

# The entities a rendered Markdown fragment can contain. Anything else is left
# as written, which is visible rather than silently dropped.
_ENTITIES = {
    "amp": "&",
    "lt": "<",
    "gt": ">",
    "quot": '"',
    "apos": "'",
    "#39": "'",
    "nbsp": " ",
}

# The tags that open a heading style, and the style each maps to. h5/h6 share
# h4's style rather than growing two more nearly identical fonts.
_HEADINGS = {"h1": "h1", "h2": "h2", "h3": "h3", "h4": "h4", "h5": "h4", "h6": "h4"}


def _unescape(s):
    """Resolve the entity subset above; leave anything else as written."""
    out = ""
    i = 0
    while True:
        amp = s.find("&", i)
        if amp < 0:
            return out + s[i:]
        out += s[i:amp]
        semi = s.find(";", amp + 1)
        # an entity name is short; a bare `&` in prose must not swallow the rest
        # of the line looking for a `;` that belongs to something else
        if semi < 0 or semi - amp > 9:
            out += "&"
            i = amp + 1
        else:
            ent = s[amp + 1:semi]
            out += _ENTITIES[ent] if ent in _ENTITIES else "&" + ent + ";"
            i = semi + 1


def _collapse(s, keep_leading):
    """Collapse runs of whitespace, as HTML does outside <pre>.

    `keep_leading` is what makes this a DOCUMENT-level rule rather than a
    per-run one. The text between two tags arrives here in pieces, and the space
    in `<strong>bold</strong> and <em>italic</em>` is the leading character of
    its own piece -- dropped unconditionally, the words run together as
    `boldand italic`. It is dropped only at the start of a line, where HTML
    drops it too."""
    out = ""
    space = False
    for c in s:
        if c == " " or c == "\t" or c == "\n" or c == "\r":
            space = True
        else:
            if space and (out != "" or keep_leading):
                out += " "
            space = False
            out += c
    if space and (out != "" or keep_leading):
        out += " "
    return out


def _tag_name(raw):
    """The tag NAME out of `<h2 id="x">` / `</h2>` -- lowercased, without
    attributes. Answers `(name, closing)`; `closing` says which end it was."""
    closing = raw.startswith("/")
    name = ""
    for c in raw[1:] if closing else raw:
        if c in " >\t\n/":
            break
        name += c
    return name.lower(), closing


class HTMLScrolledText(tk.Frame):
    """A Text widget with a vertical scrollbar, packed inside a frame of its
    own. Geometry calls (`pack`, `grid`) go to the FRAME, so the application's
    `html_label.pack(fill="both", expand=True)` places the whole thing."""

    def __init__(self, master, html="", width=-1, height=-1, background=""):
        super().__init__(master)

        # The render state lives on the instance: the emit helpers below are
        # methods, and every one of them touches this.
        self.style_stack = []
        self.at_line_start = True

        self.bar = tk.Scrollbar(self, orient="vertical")
        self.text = tk.Text(self, wrap="word", width=width, height=height,
                            background=background or "white")
        self.text.configure(yscrollcommand=self.bar.set)
        self.bar.config(command=self.text.yview)
        self.bar.pack(side="right", fill="y")
        self.text.pack(side="left", fill="both", expand=True)

        # The styles the renderer uses. Sizes are relative to Tk's default so
        # the document tracks the platform font rather than pinning pixels.
        self.text.tag_configure("h1", font="{TkDefaultFont 20 bold}", spacing1=12, spacing3=6)
        self.text.tag_configure("h2", font="{TkDefaultFont 16 bold}", spacing1=10, spacing3=5)
        self.text.tag_configure("h3", font="{TkDefaultFont 13 bold}", spacing1=8, spacing3=4)
        self.text.tag_configure("h4", font="{TkDefaultFont 11 bold}", spacing1=6, spacing3=3)
        self.text.tag_configure("strong", font="{TkDefaultFont 10 bold}")
        self.text.tag_configure("em", font="{TkDefaultFont 10 italic}")
        self.text.tag_configure("code", font="{TkFixedFont 10}", foreground="#7a0000",
                                background="#f2f2f2")
        self.text.tag_configure("pre", font="{TkFixedFont 10}", background="#f2f2f2",
                                lmargin1=24, lmargin2=24)
        self.text.tag_configure("li", lmargin1=16, lmargin2=32)
        self.text.tag_configure("quote", font="{TkDefaultFont 10 italic}",
                                foreground="#444444", lmargin1=24, lmargin2=24)
        self.text.tag_configure("a", foreground="#0645ad", underline=True)

        if html != "":
            self.set_html(html)

    # ---- tkhtmlview's own API ---------------------------------------------

    def fit_height(self):
        """Accepted and ignored -- it exists to size the widget to its content,
        which needs a layout pass this renderer does not do."""
        pass

    def set_html(self, html, strip=True):
        """Replace the document. `strip` is accepted and ignored: this parser
        collapses whitespace outside <pre> unconditionally, which is what strip
        asks for and the only behaviour the subset offers."""
        self.text.configure(state="normal")
        self.text.delete("1.0", "end")
        self.style_stack = []
        self.at_line_start = True
        in_pre = False
        i = 0
        while True:
            lt = html.find("<", i)
            gt = html.find(">", lt + 1) if lt >= 0 else -1
            # The text before this tag -- or, when no complete tag is left, the
            # whole remainder. An UNTERMINATED `<foo` at the end therefore
            # renders as literal text, the same call the entity table makes:
            # visible rather than silently dropped.
            chunk = html[i:lt] if gt >= 0 else html[i:]
            if chunk != "":
                if in_pre:
                    self._emit(_unescape(chunk))
                else:
                    self._emit(_unescape(_collapse(chunk, not self.at_line_start)))
            if gt < 0:
                break
            name, closing = _tag_name(html[lt + 1:gt])
            i = gt + 1

            if name in _HEADINGS:
                if closing:
                    self._pop()
                    self._newline(2)
                else:
                    if not self.at_line_start:
                        self._newline(1)
                    self._push(_HEADINGS[name])
            elif name == "p":
                if closing:
                    self._newline(2)
                elif not self.at_line_start:
                    self._newline(1)
            elif name == "strong" or name == "b":
                if closing:
                    self._pop()
                else:
                    self._push("strong")
            elif name == "em" or name == "i":
                if closing:
                    self._pop()
                else:
                    self._push("em")
            elif name == "code":
                # <code> inside <pre> is the fence's inner tag -- the <pre>
                # style is already open and doubling it would nest the
                # background
                if not in_pre:
                    if closing:
                        self._pop()
                    else:
                        self._push("code")
            elif name == "pre":
                if closing:
                    in_pre = False
                    self._pop()
                    self._newline(2)
                else:
                    if not self.at_line_start:
                        self._newline(1)
                    in_pre = True
                    self._push("pre")
            elif name == "blockquote":
                if closing:
                    self._pop()
                    self._newline(1)
                else:
                    if not self.at_line_start:
                        self._newline(1)
                    self._push("quote")
            elif name == "ul" or name == "ol":
                # a list is a block; NESTING is not modelled -- the `li` margin
                # is fixed, so an inner list sits at the same indent as its
                # parent rather than one step in
                if closing:
                    self._newline(2)
                elif not self.at_line_start:
                    self._newline(1)
            elif name == "li":
                if closing:
                    self._pop()
                    self._newline(1)
                else:
                    self._push("li")
                    self._emit("• ")
            elif name == "a":
                # the href is not followed -- there is no browser to hand it to
                # -- so the link is shown as link-coloured text, which is what
                # tkhtmlview does without a click handler
                if closing:
                    self._pop()
                else:
                    self._push("a")
            elif name == "br":
                self._newline(1)
            elif name == "hr":
                if not self.at_line_start:
                    self._newline(1)
                self._emit("─" * 32)
                self._newline(2)
            # any other tag: ignored, its TEXT still renders

        # read-only, like tkhtmlview's own widget
        self.text.configure(state="disabled")

    # ---- render helpers ----------------------------------------------------

    def _emit(self, run):
        """Insert one run of text under the styles currently open. Every open
        style is applied, so `<li><strong>x` gets both the list margin and the
        bold."""
        if run == "":
            return
        start = self.text.index("end-1c")
        self.text.insert("end", run)
        end = self.text.index("end-1c")
        for style in self.style_stack:
            self.text.tag_add(style, start, end)
        self.at_line_start = run.endswith("\n")

    def _newline(self, count):
        # collapse consecutive breaks: a paragraph after a heading gets ONE
        # blank line, not one per closing tag
        if self.at_line_start and count > 1:
            count -= 1
        for k in range(count):
            self.text.insert("end", "\n")
            self.at_line_start = True

    def _push(self, name):
        self.style_stack.append(name)

    def _pop(self):
        if len(self.style_stack) > 0:
            self.style_stack.pop()


class HTMLLabel(HTMLScrolledText):
    """The non-scrolling variant, same renderer."""
    pass
