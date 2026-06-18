{ =====================================================================
  ESCAPE FROM THE MACHINE — main program (thin).
  All mechanism lives in the Engine unit; all content in world.dat.
  ===================================================================== }

program Adventure;

uses Engine;

var
  game: TGame;
begin
  game := TGame.Create;
  game.Player := TPlayer.Create;
  game.Player.RoomId := 'cpu_die';
  game.Player.Energy := 100;
  game.Player.Spells := [spNop];     { everyone is born knowing NOP }
  game.Seed := 2463534242;           { xorshift seed; random-lib will replace }
  game.LoadWorld('world.dat');
  game.Run;
end.
