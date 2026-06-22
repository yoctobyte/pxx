program triangle;

{$define PXX_MANAGED_STRING}

uses gtk3, controls, stdctrls, forms, extctrls, glarea, gl_c, sysutils, math;

const
  VERT_SRC = '#version 330 core'#10'layout(location=0) in vec2 aPos;'#10'layout(location=1) in vec3 aColor;'#10'uniform mat4 uRot;'#10'out vec3 vColor;'#10'void main() {'#10'  gl_Position = uRot * vec4(aPos, 0.0, 1.0);'#10'  vColor = aColor;'#10'}'#10;
  FRAG_SRC = '#version 330 core'#10'in vec3 vColor;'#10'out vec4 FragColor;'#10'void main() {'#10'  FragColor = vec4(vColor, 1.0);'#10'}'#10;

type
  TTriangleHandler = class
  private
    FGLArea: TGLArea;
    FTimer: TTimer;
    FAngleLabel: TLabel;
    FAngle: Double;
    FProg: LongWord;
    FVAO: LongWord;
    FVBO: LongWord;
    FUnifRot: Integer;
    FInitialized: Boolean;

    procedure InitGL;
    function CompileShader(shaderType: LongWord; const src: string): LongWord;
    procedure BuildRotMatrix(angle: Double; out m: array of Single);
  public
    constructor Create(AGLArea: TGLArea; ATimer: TTimer; ALabel: TLabel);
    destructor Destroy;

    procedure OnRender(Sender: TObject; W, H: Integer);
    procedure OnTimer(Sender: TObject);
  end;

function TTriangleHandler.CompileShader(shaderType: LongWord; const src: string): LongWord;
var
  sh: LongWord;
  status: Integer;
  buf: array[0..1023] of Char;
  srcPtr: Pointer;
  len, i: Integer;
  pSrc: Pointer;
begin
  sh := glCreateShader(shaderType);
  { Build NUL-terminated C string in buf }
  len := Length(src);
  if len > 1022 then len := 1022;
  for i := 1 to len do
    buf[i - 1] := src[i];
  buf[len] := #0;
  srcPtr := @buf[0];
  pSrc := @srcPtr;
  glShaderSource(sh, 1, pSrc, nil);
  glCompileShader(sh);
  glGetShaderiv(sh, GL_COMPILE_STATUS, @status);
  if status = 0 then
  begin
    glGetShaderInfoLog(sh, 1024, nil, @buf[0]);
    writeln('Shader compile error: ', buf);
  end;
  CompileShader := sh;
end;

procedure TTriangleHandler.InitGL;
var
  vs, fs: LongWord;
  status: Integer;
  buf: array[0..1023] of Char;
  { Vertex layout: x, y, r, g, b — 5 floats per vertex }
  verts: array[0..14] of Single;
begin
  vs := Self.CompileShader(GL_VERTEX_SHADER, VERT_SRC);
  fs := Self.CompileShader(GL_FRAGMENT_SHADER, FRAG_SRC);

  FProg := glCreateProgram();
  glAttachShader(FProg, vs);
  glAttachShader(FProg, fs);
  glLinkProgram(FProg);
  glGetProgramiv(FProg, GL_LINK_STATUS, @status);
  if status = 0 then
  begin
    glGetProgramInfoLog(FProg, 1024, nil, @buf[0]);
    writeln('Program link error: ', buf);
  end;
  glDeleteShader(vs);
  glDeleteShader(fs);

  FUnifRot := glGetUniformLocation(FProg, PChar('uRot'));

  { Top vertex: red }
  verts[0]  :=  0.0;  verts[1]  :=  0.7;
  verts[2]  :=  1.0;  verts[3]  :=  0.2;  verts[4]  :=  0.2;
  { Bottom-left: green }
  verts[5]  := -0.6;  verts[6]  := -0.5;
  verts[7]  :=  0.2;  verts[8]  :=  0.9;  verts[9]  :=  0.3;
  { Bottom-right: blue }
  verts[10] :=  0.6;  verts[11] := -0.5;
  verts[12] :=  0.2;  verts[13] :=  0.4;  verts[14] :=  1.0;

  glGenVertexArrays(1, @FVAO);
  glBindVertexArray(FVAO);

  glGenBuffers(1, @FVBO);
  glBindBuffer(GL_ARRAY_BUFFER, FVBO);
  glBufferData(GL_ARRAY_BUFFER, 60, @verts[0], GL_STATIC_DRAW);

  { location 0: position (2 floats, stride=5*4, offset=0) }
  glVertexAttribPointer(0, 2, GL_FLOAT, 0, 20, Pointer(0));
  glEnableVertexAttribArray(0);
  { location 1: color (3 floats, stride=5*4, offset=2*4) }
  glVertexAttribPointer(1, 3, GL_FLOAT, 0, 20, Pointer(8));
  glEnableVertexAttribArray(1);

  glBindVertexArray(0);

  FInitialized := True;
end;

procedure TTriangleHandler.BuildRotMatrix(angle: Double; out m: array of Single);
var c, s: Double;
begin
  c := Cos(angle);
  s := Sin(angle);
  { Column-major 4x4 rotation around Z }
  m[0]  := c;   m[1]  := s;   m[2]  := 0;  m[3]  := 0;
  m[4]  := -s;  m[5]  := c;   m[6]  := 0;  m[7]  := 0;
  m[8]  := 0;   m[9]  := 0;   m[10] := 1;  m[11] := 0;
  m[12] := 0;   m[13] := 0;   m[14] := 0;  m[15] := 1;
end;

constructor TTriangleHandler.Create(AGLArea: TGLArea; ATimer: TTimer; ALabel: TLabel);
begin
  FGLArea := AGLArea;
  FTimer := ATimer;
  FAngleLabel := ALabel;
  FAngle := 0.0;
  FInitialized := False;
end;

destructor TTriangleHandler.Destroy;
begin
  if FInitialized then
  begin
    glDeleteBuffers(1, @FVBO);
    glDeleteVertexArrays(1, @FVAO);
    glDeleteProgram(FProg);
  end;
end;

procedure TTriangleHandler.OnRender(Sender: TObject; W, H: Integer);
var
  rot: array[0..15] of Single;
begin
  if not FInitialized then
    Self.InitGL;

  glViewport(0, 0, W, H);
  glClearColor(0.08, 0.08, 0.12, 1.0);
  glClear(GL_COLOR_BUFFER_BIT);

  glUseProgram(FProg);

  Self.BuildRotMatrix(FAngle, rot);
  glUniformMatrix4fv(FUnifRot, 1, 0, @rot[0]);

  glBindVertexArray(FVAO);
  glDrawArrays(GL_TRIANGLES, 0, 3);
  glBindVertexArray(0);
end;

procedure TTriangleHandler.OnTimer(Sender: TObject);
begin
  FAngle := FAngle + 0.03;
  if FAngle > 6.2832 then FAngle := FAngle - 6.2832;
  FAngleLabel.Caption := 'Angle: ' + IntToStr(Round(FAngle * 57.2958)) + Chr(176);
  FGLArea.QueueRender;
end;

var
  Form1: TForm;
  Area: TGLArea;
  Timer: TTimer;
  AngleLabel: TLabel;
  Handler: TTriangleHandler;

begin
  Application.Initialize;

  Form1 := TForm.Create;
  Form1.Caption := 'Spinning Triangle - OpenGL 3.3';
  Form1.SetBounds(100, 100, 700, 560);

  Area := TGLArea.Create;
  Area.Parent := Form1;
  Area.SetBounds(10, 10, 640, 480);

  AngleLabel := TLabel.Create;
  AngleLabel.Parent := Form1;
  AngleLabel.Caption := 'Angle: 0';
  AngleLabel.SetBounds(660, 10, 120, 30);

  Timer := TTimer.Create;
  Timer.Interval := 16;
  Timer.Enabled := False;

  Handler := TTriangleHandler.Create(Area, Timer, AngleLabel);

  Area.OnRender := @Handler.OnRender;
  Timer.OnTimer := @Handler.OnTimer;

  Timer.Enabled := True;

  Application.MainForm := Form1;
  Application.Run;

  Handler.Destroy;
end.
