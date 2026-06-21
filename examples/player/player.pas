program player;

uses
  sysutils,
  platform,
  ansiterm,
  ansirender,
  image;

var
  videoPath: AnsiString;
  cols, rows: Integer;
  w, h: Integer;
  ffmpegPath: AnsiString;
  args: array of AnsiString;
  pid: Integer;
  childStdin, childStdout: Integer;
  frameSize: Integer;
  rawFrame: array of Byte;
  img: TImage;
  frameCount: Int64;
  startTime: Int64;
  frameDuration: Int64;
  paused: Boolean;
  pauseStart: Int64;
  mode: Integer;
  ch: Char;
  s: AnsiString;
  modeStr: AnsiString;
  targetTime, curTime: Int64;
  i: Integer;
  r, g, b: Byte;
  res: Integer;
  wstatus: Integer;

function ReadExactly(fd: Integer; buf: Pointer; len: Integer): Boolean;
var
  bytesRead: Integer;
  n: Int64;
begin
  bytesRead := 0;
  while bytesRead < len do
  begin
    n := PalRead(fd, Pointer(Int64(buf) + bytesRead), len - bytesRead);
    if n <= 0 then
    begin
      Result := False;
      Exit;
    end;
    bytesRead := bytesRead + Integer(n);
  end;
  Result := True;
end;

begin
  if ParamCount < 1 then
  begin
    writeln('Usage: player <video-file>');
    halt(1);
  end;

  videoPath := ParamStr(1);

  if not TerminalSize(cols, rows) then
  begin
    cols := 80;
    rows := 24;
  end;

  { Leave 2 lines for controls and info }
  w := cols;
  h := rows - 2;
  if w < 10 then w := 10;
  if h < 5 then h := 5;

  ffmpegPath := '/usr/bin/ffmpeg';

  { Spawn ffmpeg with scaling to 2w x 2h for quadrant mode }
  SetLength(args, 11);
  args[0] := '-i';
  args[1] := videoPath;
  args[2] := '-vf';
  args[3] := 'scale=' + IntToStr(2 * w) + ':' + IntToStr(2 * h);
  args[4] := '-f';
  args[5] := 'image2pipe';
  args[6] := '-pix_fmt';
  args[7] := 'rgb24';
  args[8] := '-vcodec';
  args[9] := 'rawvideo';
  args[10] := '-';

  childStdin := -1;
  childStdout := -1;

  pid := ExecutePipeline(ffmpegPath, args, childStdin, childStdout);
  if pid <= 0 then
  begin
    writeln('Failed to spawn ffmpeg. Is it installed?');
    halt(1);
  end;

  frameSize := (2 * w) * (2 * h) * 3;
  SetLength(rawFrame, frameSize);
  ImageInit(img, 2 * w, 2 * h);

  AnsiSetRawMode(True);

  { Clear screen initially }
  write(AnsiClear);

  frameCount := 0;
  startTime := PalMonotonicMillis;
  frameDuration := 33; { Default to ~30 FPS }
  paused := False;
  mode := 0; { 0: Quadrant, 1: Half-Block, 2: ASCII }

  while True do
  begin
    { Check keyboard events non-blockingly }
    ch := AnsiReadKey;
    if ch <> #0 then
    begin
      if (ch = 'q') or (ch = 'Q') or (ch = #27) then
      begin
        break;
      end
      else if ch = ' ' then
      begin
        paused := not paused;
        if paused then
          pauseStart := PalMonotonicMillis
        else
          startTime := startTime + (PalMonotonicMillis - pauseStart);
      end
      else if (ch = 'g') or (ch = 'G') then
      begin
        mode := (mode + 1) mod 3;
      end;
    end;

    if paused then
    begin
      PalYield;
      continue;
    end;

    { Read next frame }
    if not ReadExactly(childStdout, @rawFrame[0], frameSize) then
    begin
      break;
    end;

    frameCount := frameCount + 1;
    targetTime := startTime + frameCount * frameDuration;
    curTime := PalMonotonicMillis;

    { Frame dropping if behind }
    if curTime > targetTime + frameDuration then
    begin
      continue;
    end;

    { Sleep if ahead }
    if curTime < targetTime then
    begin
      while PalMonotonicMillis < targetTime do
      begin
        PalYield;
      end;
    end;

    { Populate image structure }
    for i := 0 to (2 * w * 2 * h) - 1 do
    begin
      r := rawFrame[3 * i];
      g := rawFrame[3 * i + 1];
      b := rawFrame[3 * i + 2];
      img.Pixels[i] := MakeRGBA(r, g, b, 255);
    end;

    { Render according to selected mode }
    case mode of
      0: s := RenderAnsiTrueColorQuadrant(img, w, h);
      1: s := RenderAnsiTrueColorHalfBlock(img, w, h);
      2: s := RenderAscii(img, w, h);
    end;

    case mode of
      0: modeStr := 'Quadrant (TrueColor)';
      1: modeStr := 'Half-Block (TrueColor)';
      2: modeStr := 'ASCII (Grayscale)';
    end;

    { Write frame to terminal starting from top-left }
    write(AnsiMove(1, 1) + s);

    { Write status line }
    write(AnsiMove(h + 1, 1) + AnsiReset + '[Space] Pause | [g] Toggle Quality: ' + modeStr + ' | [q] Quit | Frame: ' + IntToStr(frameCount) + #27 + '[K');
  end;

  { Restore terminal mode }
  AnsiSetRawMode(False);
  write(AnsiMove(rows, 1) + AnsiReset + #10);

  { Close pipes and wait for child }
  if childStdout <> -1 then
    PalClose(childStdout);
  if childStdin <> -1 then
    PalClose(childStdin);

  wstatus := 0;
  PalWait4(pid, @wstatus, 0, nil);

  ImageFree(img);
end.
