{To alter compile-time defaults, please edit MT_DEFS.INC.  This file contains
compile-time defines like whether profiling is on, types of debugging, etc.}

{$I MT_DEFS.INC}

program monotone;
{MONOTONE | JL20080210 | may $DEITY have mercy on my soul}

uses
  mt_glob,
  mt_edit,
  mt_setup;

const
  mtVersion=20081126;

var
  mt:PTracker;
  oldma:longint;

begin
  oldma:=memavail;

  {$IFDEF DEBUG}
  new(mt,Init(generic,PIT,4));
  {$ELSE}
  new(mt,Init(askvideo,askaudio,asktrack));
  {$ENDIF}

  mt^.Intro;
  mt^.Dispatcher;
  dispose(mt,Done);

  if memavail<>oldma then begin
    writeln('Possible memory leak of ',oldma-memavail,' bytes detected :-/');
  end;
end.
