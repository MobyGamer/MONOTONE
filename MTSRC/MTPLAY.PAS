{To alter compile-time defaults, please edit MT_DEFS.INC.  This file contains
compile-time defines like whether profiling is on, types of debugging, etc.}

{$I MT_DEFS.INC}

program monoplay;
{MONOTONE | JL20080210 | may $DEITY have mercy on my soul}

uses
  mt_glob,
  mt_edit,
  mt_setup,
  mt_play,
  support;

const
  mtVersion=20150223;

var
  mt:PPlayer;
  oldma:longint;

begin
  if paramcount <> 1 then
  begin
    writeln('Usage: MTPLAY <file.mon>');
	halt(1);
  end;
  
  oldma:=memavail;

  {$IFDEF DEBUG}
  new(mt,Init(PIT,4));
  {$ELSE}
  new(mt,Init(askaudio,4));
  {$ENDIF}
  
  writeln('Playing: ' + paramstr(1));
  
  if mt^.load(paramstr(1)) then
  begin
    mt^.MyPlayer^.Send(pa_playsongtop);
  
    repeat until keypressed or (mt^.MyPlayer^.curAction = pa_Stop);
  end;
  
  dispose(mt,Done);

  if memavail<>oldma then begin
    writeln('Possible memory leak of ',oldma-memavail,' bytes detected :-/');
  end;
end.
