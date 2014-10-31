unit mt_setup; {Asks the user what they want on startup}

interface

uses
  mt_glob;

type
  {Unlike mt_input, I *am* going to assume the order because there are
  many less choices and a typo or reordering of the code will be much
  easier to spot.  That, and I am feeling a bit lazy at the moment.}

  DescRec=record
    supported:boolean;
    DescString:PChar;
  end;
  videoLabels=array[videochoices] of DescRec;
  audioLabels=array[audiochoices] of DescRec;

const
  vids:VideoLabels=(
    (supported:true;DescString:'Color: True CGA  (If running on true CGA or 100% hardware compatible)'),
    (supported:true;DescString:'Color: Generic   (Compatible, but slower and uses more RAM')
  );

  auds:AudioLabels=(
    (supported:true ;DescString:'8253 PIT:         Internal PC Speaker          1-4 voices'),
    (supported:false;DescString:'CPU PIT EMU:      Internal PC Speaker            2 voices'),
    (supported:false;DescString:'CPU PIT EMU:      Internal PC Speaker            3 voices'),
    (supported:false;DescString:'CPU PIT EMU:      Internal PC Speaker            4 voices'),
    (supported:true ;DescString:'TI SN76489:       IBM PCjr / Tandy 1000 series   3 voices+noise'),
    (supported:false;DescString:'Philips SAA 1099: CMS/Game Blaster, SB 1.0      12 voices+noise'),
    (supported:false;DescString:'GI AY-3-8910:     Bank Street Music Writer card  6 voices+noise'),
    (supported:true ;DescString:'Yamaha YM3812:    Adlib, Sound Blaster, clones   9 voices'),
    (supported:false;DescString:'SN76489+8253:     Tandy 1000 series              3 voices+noise+speaker')
  );

function askvideo:videochoices;
function askaudio:audiochoices;
function asktrack:byte;

implementation

uses
  strings,
  support;

function askvideo;
var
  loop:videochoices;
begin
  writeln;
  for loop:=low(videochoices) to high(videochoices) do
    if vids[loop].supported then writeln(byte(loop),'. ',vids[loop].DescString);
  write('Your choice? ');
  loop:=videochoices(ord(readkeychar)-48);
  if loop>high(videochoices) then loop:=high(videochoices);
  askvideo:=loop;
end;

function askaudio;
var
  loop:audiochoices;
begin
  writeln;
  for loop:=low(audiochoices) to high(audiochoices) do
    if auds[loop].supported then writeln(byte(loop),'. ',auds[loop].DescString);
  write('Your choice? ');
  loop:=audiochoices(ord(readkeychar)-48);
  if loop>high(audiochoices) then loop:=high(audiochoices);
  askaudio:=loop;
end;

function asktrack;
const
  msg:PChar=
  'While you can compose with up to 12 tracks, it is a good idea when'#13#10+
  'first starting out to not exceed the capabilites of your output device.'#0;
  b:byte=0;
begin
  writeln;
  writeln(strpas(msg));
  write('How many tracks to start with? ');
  readln(b);
  if b=0 then inc(b);
  if b>maxChannels then b:=maxChannels;
  asktrack:=b;
end;

end.
