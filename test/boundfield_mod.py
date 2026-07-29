# A class defined in an imported .py MODULE, capturing a bound method off one of
# its own fields. The capture used to be gated on `CurrentUnitIdx < 0` — the
# MAIN program only — so this exact class segfaulted when imported and worked
# when pasted into the main file.
# bug-nilpy-settings-editor-segfaults-on-bound-method-field


class Widget:
    def __init__(self, tag):
        self.tag = tag

    def scroll(self, n):
        return self.tag + ":" + str(n)


class Panel:
    def __init__(self):
        self.inner = Widget("w")
        self.cb = self.inner.scroll          # capture off a FIELD
        self.own = self.describe             # capture off SELF

    def describe(self):
        return "panel"
