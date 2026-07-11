{ SPDX-License-Identifier: Zlib }
unit esptimer;
{ ESP32 peripheral callback API, slice 1: timers
  (feature-esp-peripheral-callback-api).

  Event-style surface over ESP-IDF's esp_timer service, so app code assigns a
  callback and starts the timer without ever seeing esp_timer_create args,
  esp_intr_alloc, or `iram;`:

      var t: TEspTimer;
      procedure Tick(arg: Pointer); begin ... end;
      ...
      TimerInit(t);
      t.OnElapsed := @Tick;
      if not TimerStartPeriodicMs(t, 500) then ...;

  esp_timer dispatches callbacks from a high-priority FreeRTOS task, NOT a true
  ISR — deliberately, per the ticket: no IRAM placement, no ISR-safety
  restrictions, callbacks may print / allocate / block briefly. Keep them short
  anyway; every esp_timer callback in the system shares one dispatch task. A
  true hardware timer-group ISR variant (iram; trampoline) is a follow-up
  slice, not this unit.

  The user callback signature is `procedure(arg: Pointer);` — the same shape
  the SDK expects (esp_timer_cb_t), so the proc address is registered directly
  with the SDK and OnElapsed/UserArg are captured at Start time. IDF-only:
  resolves at IDF link time; nothing here works on bare-metal ESP. }

interface

type
  { the callback: arg is the TEspTimer.UserArg captured at Start }
  TTimerProc = procedure(arg: Pointer);

  TEspTimer = record
    Handle:    Pointer;      { esp_timer_handle_t; nil until first Start }
    OnElapsed: TTimerProc;   { assign before Start }
    UserArg:   Pointer;      { handed to OnElapsed verbatim (may be nil) }
  end;

{ Reset a timer record. Call once before first use (does not touch the SDK). }
procedure TimerInit(var t: TEspTimer);

{ Create (first time) and start the timer, firing OnElapsed every intervalMs
  milliseconds / once after delayMs. False when OnElapsed is unset, the
  interval is <= 0, or the SDK refuses (already running, out of memory). }
function TimerStartPeriodicMs(var t: TEspTimer; intervalMs: Integer): Boolean;
function TimerStartOnceMs(var t: TEspTimer; delayMs: Integer): Boolean;

{ Stop a running timer. True when it was running (ESP_OK); False when it was
  not running or never started. The handle stays valid for a re-Start. }
function TimerStop(var t: TEspTimer): Boolean;

{ Stop (if needed) and free the SDK handle. The record is re-Init'ed and may
  be reused with a fresh Start. }
procedure TimerDone(var t: TEspTimer);

implementation

{ esp_timer service (components/esp_timer). All resolve at IDF link time. }
function esp_timer_create(args: Pointer; outHandle: Pointer): Integer; external;
function esp_timer_start_periodic(handle: Pointer; periodUs: Int64): Integer; external;
function esp_timer_start_once(handle: Pointer; timeoutUs: Int64): Integer; external;
function esp_timer_stop(handle: Pointer): Integer; external;
function esp_timer_delete(handle: Pointer): Integer; external;

const
  ESP_TIMER_TASK = 0;   { dispatch method: the esp_timer task (not ISR) }

type
  { mirrors esp_timer_create_args_t (riscv32/ILP32: 4-byte pointers/ints) }
  TEspTimerCreateArgs = record
    callback:        Pointer;   { esp_timer_cb_t }
    arg:             Pointer;
    dispatch_method: Integer;   { ESP_TIMER_TASK }
    name:            Pointer;   { const char*, kept alive by the SDK's dump }
    skip_unhandled:  Byte;      { bool; trailing bytes are padding }
    pad0, pad1, pad2: Byte;
  end;

var
  { debug name esp_timer keeps a pointer to — must outlive the timer }
  TimerName: array[0..3] of Char = ('p', 'x', 'x', #0);

procedure TimerInit(var t: TEspTimer);
begin
  t.Handle := nil;
  t.OnElapsed := nil;
  t.UserArg := nil;
end;

{ Create the SDK timer for the current OnElapsed/UserArg if not created yet.
  Returns False when OnElapsed is unset or esp_timer_create fails. }
function EnsureCreated(var t: TEspTimer): Boolean;
var
  args: TEspTimerCreateArgs;
  h: Pointer;
  rc: Integer;
begin
  EnsureCreated := False;
  if not Assigned(t.OnElapsed) then Exit;
  if t.Handle <> nil then
  begin
    EnsureCreated := True;
    Exit;
  end;
  args.callback := Pointer(t.OnElapsed);
  args.arg := t.UserArg;
  args.dispatch_method := ESP_TIMER_TASK;
  args.name := @TimerName[0];
  args.skip_unhandled := 0;
  args.pad0 := 0; args.pad1 := 0; args.pad2 := 0;
  h := nil;
  rc := esp_timer_create(@args, @h);
  if rc <> 0 then Exit;
  t.Handle := h;
  EnsureCreated := True;
end;

function TimerStartPeriodicMs(var t: TEspTimer; intervalMs: Integer): Boolean;
begin
  TimerStartPeriodicMs := False;
  if intervalMs <= 0 then Exit;
  if not EnsureCreated(t) then Exit;
  TimerStartPeriodicMs := esp_timer_start_periodic(t.Handle, Int64(intervalMs) * 1000) = 0;
end;

function TimerStartOnceMs(var t: TEspTimer; delayMs: Integer): Boolean;
begin
  TimerStartOnceMs := False;
  if delayMs <= 0 then Exit;
  if not EnsureCreated(t) then Exit;
  TimerStartOnceMs := esp_timer_start_once(t.Handle, Int64(delayMs) * 1000) = 0;
end;

function TimerStop(var t: TEspTimer): Boolean;
begin
  TimerStop := False;
  if t.Handle = nil then Exit;
  TimerStop := esp_timer_stop(t.Handle) = 0;
end;

procedure TimerDone(var t: TEspTimer);
var rc: Integer;
begin
  if t.Handle <> nil then
  begin
    rc := esp_timer_stop(t.Handle);     { ok if it was not running }
    rc := esp_timer_delete(t.Handle);
  end;
  TimerInit(t);
end;

end.
