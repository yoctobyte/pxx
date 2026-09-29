---
title: tkinter
order: 56
---

# tkinter: GUI programs in Nil Python

A Nil Python program gets a desktop window with `import tkinter`, as in
CPython. PXX's `tkinter` module is `lib/pcl/tkinter.pas`. It binds the
system's Tcl/Tk 8.6 directly: each widget call becomes one Tcl command, which
is also how CPython's tkinter works underneath. Widgets are objects that take
keyword options, `command=` and `bind` take Python functions, and the
widget variables (`StringVar`, `BooleanVar`) work as in CPython.

It is a subset of tkinter, not all of it. Everything below was measured on
Linux x86-64. A name the module does not have is a compile error that names
it, never a call that silently does nothing (see [Limits](#limits)).

For a Pascal program, use the [PCL](./pcl.md) instead.

## What you need

- At run time, the Tk 8.6 library: `sudo apt install libtk8.6`. No
  development headers are needed.
- To run a GUI program without a desktop (on a server, or in a test), Xvfb:
  `sudo apt install xvfb`, then start the program with `xvfb-run -a`.

## An example

A window with an entry, a check box, a button and a label. The button's
`command` is a Python function. Instead of waiting for a person, `after()`
types a name, presses the button, ticks the box, prints what the widgets now
hold, and closes the window, so the program also runs headless.

```python
import tkinter as tk

root = tk.Tk()
root.title("tkinter hello")
name = tk.StringVar(value="")
remember = tk.BooleanVar(value=False)

entry = tk.Entry(root, textvariable=name, width=20)
entry.pack(padx=8, pady=4)
check = tk.Checkbutton(root, text="Remember me", variable=remember)
check.pack()
greeting = tk.Label(root, text="(nobody yet)")
greeting.pack(pady=4)


def greet():
    greeting.configure(text="Hello, " + name.get())


button = tk.Button(root, text="Greet", command=greet)
button.pack(pady=4)


def play():
    name.set("PXX")
    button.invoke()
    remember.set(True)
    print("entry:", entry.get())
    print("label:", greeting.cget("text"))
    print("checked:", remember.get())
    print("children:", len(root.winfo_children()))
    root.destroy()


root.after(300, play)
root.mainloop()
print("closed")
```

```sh
./pxx tk_hello.npy tk_hello
xvfb-run -a ./tk_hello
```

```text
entry: PXX
label: Hello, PXX
checked: True
children: 4
closed
```

Built with pin v451 (compiler sha256 `d9b7226769cc`) through `./pxx` and run
under `xvfb-run` on 2026-09-29. CPython 3.14.4 prints the same five lines for
the same file. Drop the `after()` line to keep the window open.

More programs are in `examples/tk/`, listed on the
[Examples page](../examples/index.md#tkinter-gui-programs-in-python).

## What works

The module has these names. Each widget takes the options listed in
`lib/pcl/tkinter.pas` as keyword arguments, in any subset.

| Area | Names |
| --- | --- |
| Windows | `Tk`, `Toplevel` (`geometry`, `transient`, `grab_set`, `grab_release`) |
| Widgets | `Frame`, `Label`, `Entry`, `Button`, `Checkbutton`, `Text`, `Canvas`, `Scrollbar`, `Menu`, `Separator`, `PanedWindow`, `Notebook`, `PhotoImage` |
| Variables | `StringVar`, `BooleanVar` (`get`, `set`, `trace_add`) |
| Layout | `pack`, `grid`, `grid_columnconfigure`, `grid_rowconfigure` |
| Every widget | `configure`/`config`, `cget`, `bind`, `after`, `after_idle`, `after_cancel`, `winfo_children`, `winfo_width`, `winfo_height`, `focus_set`, `destroy`, `update`, `mainloop`, `quit`, the clipboard calls |
| `Text` | `insert`, `delete`, `get`, `index`, `see`, `mark_set`, `tag_add`, `tag_configure`, scrolling |
| `Canvas` | `create_text`, `create_line`, `create_rectangle`, `create_oval`, `create_image`, `create_window`, `itemconfigure`, `bbox`, `delete`, scrolling |
| Dialogs | `from tkinter import messagebox`: `showinfo`, `showwarning`, `showerror`, `askyesno`, `askokcancel`, `askyesnocancel`. `from tkinter import filedialog`: `askopenfilename`, `asksaveasfilename`, `askdirectory` |
| ttk | `from tkinter import ttk`: `ttk.Frame` (with `padding=`), `ttk.Label`, `ttk.Entry`, `ttk.Button`, `ttk.Checkbutton`, `ttk.Notebook`, `ttk.PanedWindow`, `ttk.Separator`, `ttk.Scrollbar` |
| Constants | `tk.END`, `tk.BOTH`, `tk.LEFT`, `tk.RIGHT`, `tk.TOP`, `tk.BOTTOM`, `tk.HORIZONTAL`, `tk.VERTICAL`, `tk.WORD`, `tk.CENTER`, `tk.NW`, `tk.NE`, `tk.SW`, `tk.SE`, `tk.DISABLED`, `tk.NORMAL` (the same strings as CPython's); the error class `tk.TclError` |

`tkinter.font` is a shim with the font calls PXX needed, and
`from tkhtmlview import HTMLLabel, HTMLScrolledText` renders HTML into a Tk
text widget (see [Nil Python: Shims](../targets/nil-python.md#shims-standing-in-for-a-python-package)).

A command or binding can be a plain function, a bound method or a lambda. A
bound function receives an event object with tkinter's field names, such as
`event.width` for `<Configure>`, and a `yscrollcommand` function receives
Tk's two fractions as strings, as in CPython. `examples/tk/callbacks.npy`
shows each of these, and it printed its `.expected` output with v451.

## Limits

Measured with pin v451 on 2026-09-29, each with a one-line program:

- **Not in the module:** `Listbox`, `Radiobutton`, `Scale`, `Spinbox`,
  `IntVar` and `DoubleVar`, among others. `tk.Listbox(root)` stops the build
  with "no member Listbox came of the qualifier tk".
- **`from tkinter import *` does not compile** ("expected expression"). This
  is true of every module in Nil Python, not only tkinter. Import the names
  you use, or use `import tkinter as tk`.
- **`tk.X` and `tk.Y` are not there** ("no member X came of the qualifier
  tk"). Write the option as a string: `pack(fill="x")`.
- **Write `from tkinter import messagebox`,** not `import tkinter.messagebox`.
  The dotted form is refused ("no unit named tkinter_messagebox").
- **Only Linux x86-64 has been run.** Tk is a system library, so a program
  needs `libtk8.6` wherever it runs.
- **Memory:** with v451, every event delivered to a bound function leaked its
  event object, and each `winfo_children()` call leaked each child it
  returned. A program that handled 300 `<Configure>` events (the census build
  of `examples/tk/event_and_children_are_released.npy`) ended with 2,431
  allocations still live on v451, against 25 after the fix.
  Fixed after v451 (`6658668a8b`, in no pin yet).
