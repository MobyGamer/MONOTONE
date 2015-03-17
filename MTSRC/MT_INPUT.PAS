{$I MT_DEFS.INC}

unit mt_input;
{
Responsible for interpreting user input and translating it into events that
the dispatcher can act on.  While this functionality could be built into
the editor, it is convenient to have it in broken out into it's own module
because:

- Less to compile (once done, it's done)
- Allows for future input capability expansion (editor gets "events" to act
on, as opposed to being hard-coded for keyboard input);
- Allows for standalone "keyboard config" utility (note: keyboard config
util must enforce unique keypresses, as the data structures only allow
for one keycombo->action lookup).

Caveats:

- Does not current have any provision for multi-modal input; that
responsibility is left to the mt_edit module.
- Assumes keyboard only and makes no provision for joystick or mouse input.
This is tentatively planned for future revisions of the program.

BTW, if these data structures start to look like a relational database, that's
because they are :-/ but I can't think of any other graceful way to do it
that won't badly waste memory.  Perl would be really handy right here...
}

interface

uses
  objects,
  keyb_obj,
  mt_glob;

type
  {this table will be used in the tracker}
  PKeyInputLookup=^TKeyInputLookup;
  TKeyInputLookup=record {used for "key input->action" lookup table}
    act:useractions; {the action this keypress maps to}
    scancode,flags:byte; {these two combined make up a keyboard input event}
  end;
  PKeyLookup=^TKeyLookup;
  TKeyLookup=array[userActions] of TKeyInputLookup;

  inputCategories=(
    control,  {actions that control the tracker}
    editing,  {actions used for editing the song}
    pianokey, {actions to directly enter a note from the keyboard}
    movement, {actions used for navigating the song}
    internal  {internal to the program and not choosable by users}
  );

  {this table will NOT be used in the tracker, only the keyboard config utility}
  inputLabelLookup=record {used for "action->description" lookup table}
    act:useractions;
    cat:inputCategories;
    sDes,lDes:PChar;
  end;
  inputLabels=array[userActions] of inputLabelLookup;

const
  Descriptions:inputLabels=(
    (act:goHelpScreen;    cat:control; sDes:'HelpScreen'; lDes:'Switches to a basic help screen'),
    (act:goTrackerScreen; cat:control; sDes:'TrackerScreen'; lDes:'Switches to the main tracking screen'),
    (act:goStatusScreen;  cat:control; sDes:'StatusScreen'; lDes:'Switches to a status/debugging screen'),
    (act:goPianoScreen;   cat:control; sDes:'PlayerPiano'; lDes:'Displays a player piano to test note input/output'),

    {pattern movement}
    (act:moveup;     cat:movement; sDes:'MoveUp';     lDes:'Cursor Movement'),
    (act:movedown;   cat:movement; sDes:'MoveDown';   lDes:'Cursor Movement'),
    (act:moveleft;   cat:movement; sDes:'MoveLeft';   lDes:'Cursor Movement'),
    (act:moveright;  cat:movement; sDes:'MoveRight';  lDes:'Cursor Movement'),
    (act:movetop;    cat:movement; sDes:'MoveTop';    lDes:'Moves to top of pattern'),
    (act:movebottom; cat:movement; sDes:'MoveBottom'; lDes:'Moves to bottom of pattern'),
    (act:movepgup;   cat:movement; sDes:'PageUp';     lDes:'Moves up 16 rows'),
    (act:movepgdn;   cat:movement; sDes:'PageDown';   lDes:'Moves down 16 rows'),

    {tracker movement}
    (act:nextpattern; cat:control; sDes:'NextPattern'; lDes:'Switches to the next pattern'),
    (act:prevpattern; cat:control; sDes:'PreviousPattern'; lDes:'Switches to the previous pattern'),
    (act:nextarea; cat:control; sDes:'NextArea'; lDes:'Moves to the next "window" or area on a screen'),
    (act:prevarea; cat:control; sDes:'PrevArea'; lDes:'Moves to the previous "window" or area on a screen'),

    {tracker editing}
    (act:c;       cat:pianokey; sDes:'C-3'; lDes:'Enters said note at the cursor location (lower octave)'),
    (act:csharp;  cat:pianokey; sDes:'C#3'; lDes:'Enters said note at the cursor location (lower octave)'),
    (act:d;       cat:pianokey; sDes:'D-3'; lDes:'Enters said note at the cursor location (lower octave)'),
    (act:dsharp;  cat:pianokey; sDes:'D#3'; lDes:'Enters said note at the cursor location (lower octave)'),
    (act:e;       cat:pianokey; sDes:'E-3'; lDes:'Enters said note at the cursor location (lower octave)'),
    (act:f;       cat:pianokey; sDes:'F-3'; lDes:'Enters said note at the cursor location (lower octave)'),
    (act:fsharp;  cat:pianokey; sDes:'F#3'; lDes:'Enters said note at the cursor location (lower octave)'),
    (act:g;       cat:pianokey; sDes:'G-3'; lDes:'Enters said note at the cursor location (lower octave)'),
    (act:gsharp;  cat:pianokey; sDes:'G#3'; lDes:'Enters said note at the cursor location (lower octave)'),
    (act:a;       cat:pianokey; sDes:'A-3'; lDes:'Enters said note at the cursor location (lower octave)'),
    (act:asharp;  cat:pianokey; sDes:'A#3'; lDes:'Enters said note at the cursor location (lower octave)'),
    (act:b;       cat:pianokey; sDes:'B-3'; lDes:'Enters said note at the cursor location (lower octave)'),

    (act:c2;      cat:pianokey; sDes:'C-4'; lDes:'Enters said note at the cursor location (upper octave)'),
    (act:csharp2; cat:pianokey; sDes:'C#4'; lDes:'Enters said note at the cursor location (upper octave)'),
    (act:d2;      cat:pianokey; sDes:'D-4'; lDes:'Enters said note at the cursor location (upper octave)'),
    (act:dsharp2; cat:pianokey; sDes:'D#4'; lDes:'Enters said note at the cursor location (upper octave)'),
    (act:e2;      cat:pianokey; sDes:'E-4'; lDes:'Enters said note at the cursor location (upper octave)'),
    (act:f2;      cat:pianokey; sDes:'F-4'; lDes:'Enters said note at the cursor location (upper octave)'),
    (act:fsharp2; cat:pianokey; sDes:'F#4'; lDes:'Enters said note at the cursor location (upper octave)'),
    (act:g2;      cat:pianokey; sDes:'G-4'; lDes:'Enters said note at the cursor location (upper octave)'),
    (act:gsharp2; cat:pianokey; sDes:'G#4'; lDes:'Enters said note at the cursor location (upper octave)'),
    (act:a2;      cat:pianokey; sDes:'A-4'; lDes:'Enters said note at the cursor location (upper octave)'),
    (act:asharp2; cat:pianokey; sDes:'A#4'; lDes:'Enters said note at the cursor location (upper octave)'),
    (act:b2;      cat:pianokey; sDes:'B-4'; lDes:'Enters said note at the cursor location (upper octave)'),

    (act:noteoff; cat:editing; sDes:'NoteOff'; lDes:'Enters an "OFF" mark (stops previous note from sounding)'),
    (act:erasenote; cat:editing; sDes:'EraseNote'; lDes:'Erases the note at cursor location'),
    (act:enter; cat:editing; sDes:'Enter'; lDes:'Enters a value at the cursor location'),
    (act:erase; cat:editing; sDes:'Erase'; lDes:'Erases the value at the cursor location'),
    (act:octaveup; cat:control; sDes:'OctaveUp'; lDes:'Raises the default octave'),
    (act:octavedown; cat:control; sDes:'OctaveDown'; lDes:'Lowers the default octave'),
    (act:deleterow; cat:editing; sDes:'DeleteRow'; lDes:'Deletes the row at the cursor location'),
    (act:insertrow; cat:editing; sDes:'InsertRow'; lDes:'Inserts a row at the cursor location'),
    (act:erasetrack; cat:editing; sDes:'EraseTrack'; lDes:'Erases the current track, leaving the rest alone'),
    (act:mark; cat:editing; sDes:'SetMark'; lDes:'Marks the current track/pattern'),
    (act:swaptrack; cat:editing; sDes:'SwapTrack'; lDes:'Swaps the marked track to the current track'),
    (act:pastetrack; cat:editing; sDes:'PasteTrack'; lDes:'Pastes the marked track to the current track'),
    (act:pastepattern; cat:editing; sDes:'PastePattern'; lDes:'Pastes the marked pattern to the current pattern'),
    (act:transup; cat:editing; sDes:'TransposeUp'; lDes:'Transposes entire track one note higher'),
    (act:transdown; cat:editing; sDes:'TransposeDown'; lDes:'Transposes entire track one note lower'),
    (act:transupoctave; cat:editing; sDes:'TransposeUpOctave'; lDes:'Transposes entire track one octave higher'),
    (act:transdownoctave; cat:editing; sDes:'TranposeDownOctave'; lDes:'Transposes entire track one octave lower'),
    (act:loadsong; cat:control; sDes:'LoadSong'; lDes:'Loads a song file from disk'),
    (act:savesong; cat:control; sDes:'SaveSong'; lDes:'Saves a song file to disk'),

    {playing}
    (act:playsongtop; cat:control; sDes:'PlaySongTop'; lDes:'Play entire song from the beginning'),
    (act:playsongcur; cat:control; sDes:'PlaySongCur'; lDes:'Play song from current location'),
    (act:playpattern; cat:control; sDes:'PlayPattern'; lDes:'Play entire pattern once, then stop'),
    (act:stopplaying; cat:control; sDes:'StopPlaying'; lDes:'Halts playback (ie. stops playing the song or pattern)'),

    {toggling playback channels on/off}
    (act:tc1;  cat:control; sDes:'ToggleChannel1'; lDes:'Toggles the channel on/off (ie. solo)'),
    (act:tc2;  cat:control; sDes:'ToggleChannel2'; lDes:'Toggles the channel on/off (ie. solo)'),
    (act:tc3;  cat:control; sDes:'ToggleChannel3'; lDes:'Toggles the channel on/off (ie. solo)'),
    (act:tc4;  cat:control; sDes:'ToggleChannel4'; lDes:'Toggles the channel on/off (ie. solo)'),
    (act:tc5;  cat:control; sDes:'ToggleChannel5'; lDes:'Toggles the channel on/off (ie. solo)'),
    (act:tc6;  cat:control; sDes:'ToggleChannel6'; lDes:'Toggles the channel on/off (ie. solo)'),
    (act:tc7;  cat:control; sDes:'ToggleChannel7'; lDes:'Toggles the channel on/off (ie. solo)'),
    (act:tc8;  cat:control; sDes:'ToggleChannel8'; lDes:'Toggles the channel on/off (ie. solo)'),
    (act:tc9;  cat:control; sDes:'ToggleChannel9'; lDes:'Toggles the channel on/off (ie. solo)'),
    (act:tc10; cat:control; sDes:'ToggleChannel10'; lDes:'Toggles the channel on/off (ie. solo)'),
    (act:tc11; cat:control; sDes:'ToggleChannel11'; lDes:'Toggles the channel on/off (ie. solo)'),
    (act:tc12; cat:control; sDes:'ToggleChannel12'; lDes:'Toggles the channel on/off (ie. solo)'),

    {misc}
    (act:quit; cat:control; sDes:'Quit'; lDes:'Quits the program')
  );

type
  PInput=^TInput;
  TInput=object(TObject)
    LastInputReceived:userActions;
    KB:PKeyboard; {our interface to the keyboard via the keyboard object}

    constructor Init; {pass the keyboard object we should use}
    destructor Done; virtual;
    procedure SetBinding(action:UserActions;SC,FL:byte); {binds an action to a keycombo}
    function GetBinding(action:UserActions):PKeyInputLookup; {returns keycombo for a certain action}
    function SaveState(filename:string):boolean; {|these are so the user can}
    function LoadState(filename:string):boolean; {|customize program input}
    function InputPending:boolean; {if false, take no action; if true, look
    in LastInputReceived to see what action was requested}
    function KeypressFromAction(action:useractions):str80; {returns keypress string for the specified action}

    private

    KLookupTable:PKeyLookup;
    scratchaction:TKeyInputLookup; {used for return of getBinding
    since TP won't let us return a record}
  end;

implementation

uses
  strings,
  support;

constructor TInput.Init;
var
  loop:useractions;
begin
  new(KB,init);
  {empty keyboard buffer to be safe}
  if KB^.keypressed then repeat until not KB^.keypressed;

  new(KLookupTable);
  for loop:=low(useractions) to high(useractions) do begin
    with KLookupTable^[loop] do begin
      act:=quit;
      scancode:=0;
      flags:=0;
    end;
  end;
  LastInputReceived:=goHelpScreen;
end;

destructor TInput.Done;
begin
  dispose(KLookupTable);
  dispose(KB,done);
  Inherited Done;
end;

Procedure TInput.SetBinding;
begin
  with KLookupTable^[action] do begin
    act:=action;
    scancode:=sc;
    flags:=fl;
  end;
end;

Function TInput.GetBinding;
begin
  with scratchaction do begin {set in static temporary area}
    act:=action;
    scancode:=KLookupTable^[action].scancode;
    flags:=KLookupTable^[action].flags;
  end;
  GetBinding:=@scratchaction; {return pointer to static area}
end;

function TInput.SaveState(filename:string):boolean; {|these are so the user can}
var
  f:PDosStream;
begin
  new(f,init(filename,stCreate));
  f^.write(KLookupTable^,sizeof(KLookupTable^));
  if f^.status <> stOK then fatalerror(3,'Couldn''t create or write '+filename);
  dispose(f,done);
end;

function TInput.LoadState(filename:string):boolean; {|customize program input}
var
  f:PDosStream;
begin
  new(f,init(filename,stOpenRead));
  if f^.status <> stOK
    then fatalerror(1,'Couldn''t open '+filename);
  f^.read(KLookupTable^,sizeof(KLookupTable^));
  if f^.status <> stOK
    then fatalerror(2,'Couldn''t read '+filename);
  dispose(f,done);
end;

function TInput.InputPending:boolean;
{grabs keypress.  if no keypress, nothing pending.
if keypress, scans lookup table trying to find match. if no match, nothing pending.
if match, fill LastInputReceived with match and report pending.}
var
  loop:useractions;
begin
  if KB^.keypressed then begin
    for loop:=low(useractions) to high(useractions) do
      if ((KB^.lastkeypressed.scancode=KLookupTable^[loop].scancode)
          and
          (KB^.lastkeypressed.flags=KLookupTable^[loop].flags))
        then begin
          LastInputReceived:=KLookupTable^[loop].act;
          InputPending:=true;
          exit; {leave, we found a match}
        end;
    InputPending:=false; {no matches; the user pressed an unbound keycombo}
  end else begin {no keypressed}
    InputPending:=false;
  end;
end;

function TInput.KeypressFromAction;
begin
  KeypressFromAction:=KB^.humanreadable(getbinding(action)^.scancode,getbinding(action)^.flags);
end;

end.
