{ SPDX-License-Identifier: Zlib }
unit gtk3gl;

{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ The GTK3 OpenGL backend — the sparse point of the PCL widgetset seam
  (feature-pcl-seam-seal).

  It is a unit of its own rather than part of gtk3widgets for a measured
  reason: the GL entry points come from a separate shared library, so a
  gtk3widgets that pulled them in gave EVERY PCL binary a DT_NEEDED on
  libgl_c.so and every GUI program then failed to start. Keeping the GL
  backend here means only a program that actually uses TGLArea links it.

  glarea.pas uses this unit purely to have a backend INSTALLED; it calls
  nothing here by name, only `GLBackend.*` from uwidgetset. A future non-GTK
  widgetset ships its own equivalent, and a widgetset with no GL ships none —
  `GLBackend` stays nil and TGLArea reports that honestly. }

interface

uses uwidgetset;

type
  TGtk3GLBackend = class(TGLBackend)
  public
    function CreateArea(AMajor, AMinor: Integer): Pointer; override;
    procedure MakeCurrent(AArea: Pointer); override;
    procedure QueueRender(AArea: Pointer); override;
    procedure OnRender(AArea, ACallback, AData: Pointer); override;
    procedure OnResize(AArea, ACallback, AData: Pointer); override;
  end;

implementation

uses gl_c, gtk3;

function TGtk3GLBackend.CreateArea(AMajor, AMinor: Integer): Pointer;
var w: Pointer;
begin
  w := gtk_gl_area_new();
  if w <> nil then gtk_gl_area_set_required_version(w, AMajor, AMinor);
  CreateArea := w;
end;

procedure TGtk3GLBackend.MakeCurrent(AArea: Pointer);
begin
  if AArea <> nil then gtk_gl_area_make_current(AArea);
end;

procedure TGtk3GLBackend.QueueRender(AArea: Pointer);
begin
  if AArea <> nil then gtk_gl_area_queue_render(AArea);
end;

procedure TGtk3GLBackend.OnRender(AArea, ACallback, AData: Pointer);
begin
  if AArea <> nil then SignalConnectData(AArea, 'render', ACallback, AData);
end;

procedure TGtk3GLBackend.OnResize(AArea, ACallback, AData: Pointer);
begin
  if AArea <> nil then SignalConnectData(AArea, 'resize', ACallback, AData);
end;

initialization
  GLBackend := TGtk3GLBackend.Create;
end.
