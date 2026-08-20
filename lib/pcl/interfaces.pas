{ SPDX-License-Identifier: Zlib }
unit interfaces;

{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Widgetset SELECTION — the one place that decides which backend a PCL program
  is built against (feature-pcl-widgetset-select).

  The choice is made at COMPILE time and baked into the single binary, the way
  Lazarus' `-ws` does it and the way pxx's zero-dependency, no-runtime-plugin
  identity requires. Adding a widgetset is ONE arm below plus one TWidgetSet
  subclass; nothing else in the tree changes.

  Select with a define:

      pxx -dWIDGETSET_GTK3 ...      (also the default when none is given)
      pxx -dWIDGETSET_WIN32 ...

  ---- the sparse matrix ----

  Not every (widgetset x OS) cell exists, and an unsupported one is a HARD
  COMPILE ERROR naming the reason — never a silent build that dies deep in the
  linker or, worse, at run time:

    widgetset | linux                | windows
    ----------+----------------------+---------------------------------------
    gtk3      | supported            | refused by design (30-40 MB DLL bundle)
    win32     | not applicable       | not delivered yet
    qt        | not delivered yet    | not delivered yet

  A cell becomes supported by adding its arm — the guard is a table in one
  file, not logic spread through the tree. }

interface

{ ---- default ---------------------------------------------------------------
  No selection = gtk3, which is what every existing build already gets. }
{$if not defined(WIDGETSET_GTK3) and not defined(WIDGETSET_WIN32) and not defined(WIDGETSET_QT)}
  {$define WIDGETSET_GTK3}
{$endif}

{ ---- the matrix -------------------------------------------------------------
  Each arm asserts its cell before the backend is pulled in, so the diagnostic
  names the combination and the reason rather than a missing symbol. }
{$ifdef WIDGETSET_GTK3}
  {$ifdef WINDOWS}
    {$error widgetset gtk3 is refused on windows by design: it needs a 30-40 MB GTK DLL bundle, which contradicts pxx's zero-dependency single-binary identity. Use -dWIDGETSET_WIN32.}
  {$endif}
{$endif}

{$ifdef WIDGETSET_WIN32}
  {$ifndef WINDOWS}
    {$error widgetset win32 exists only on windows. On this target use -dWIDGETSET_GTK3.}
  {$endif}
  {$error widgetset win32 is not delivered yet (see feature-pcl-win32-widgetset). Supported today: gtk3 on linux.}
{$endif}

{$ifdef WIDGETSET_QT}
  {$error widgetset qt is not delivered yet. Supported today: gtk3 on linux.}
{$endif}

{ ---- the selected backend ---------------------------------------------------
  Pulling the unit in is the whole mechanism: each widgetset unit installs
  itself into the global WidgetSet in its own initialization section. }
{$ifdef WIDGETSET_GTK3}
uses uwidgetset, gtk3widgets;
{$endif}

implementation

end.
