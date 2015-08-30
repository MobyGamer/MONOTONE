{$I MT_DEFS.INC}

unit mt_edit;
{
Implements:
  - Tracker interface (user input and output), which itself is made up of:
    - Dispatcher (routes user input to actions)
    - Providing Editing and status displays
    - Switching between displays
}

interface

uses
  objects,
  mt_input,
  mt_glob,
  mt_song,
  mt_play,
  {$IFNDEF DEBUG}
  mt_outp,
  {$ENDIF}
  mt_scre;

{$IFDEF PROFILE}
const
  numpslots=10;
var
  pslots:array[0..numpslots-1] of longint;
{$ENDIF}

type
  noteLabelType=string[3];
  {areas of program focus:}
  areatype=(
    IntroArea, {gotzta haf a title screen!!1!}
    TrackerArea, {main editing screen}
    OrderArea, {little area on tracking screen where we edit the order list}
    HelpArea, {displays basic user help}
    StatusArea, {status screen showing the freq/vol/eff of each track, debug info}
    PianoArea {screen where user can practice notes on the keyboard}
  );
  
  PPlayer=^TPlayer;
  TPlayer=object(TObject)
    MySong:PSong; {make sure you init as a descendant, like PMTSong}
    {$IFNDEF DEBUG}
    MyOutput:POutputDevice; {make sure to init as descendant, like PPCSpeakerSimple}
    {$ENDIF}
    MyPlayer:PPlayerEngine; {make sure ot init as descendant, like PMTV1Player}
    Player:PPlayerEngine;
	
    constructor Init(device:audiochoices;numtracks:byte);
    destructor Done; virtual;
	
	Function load(filename:string): Boolean;
    Procedure WriteDumpFile(filename:string);

	private

    audioDevice:audiochoices;

    Procedure InitPlaySubsystem; {initializes the player engine+output device subsystem}
    Procedure KillPlaySubsystem; {de-inits the player engine+output device subsystem}
    Procedure DumpSongData(filename:string);
  end;

  PTracker=^TTracker;
  TTracker=object(TPlayer)
    activeArea:areatype;
    activeScreen:PScreen;
    Clipboard:LocationType; {used to copy current loc in prep for pasting}

    constructor Init(mode:videochoices;device:audiochoices;numtracks:byte);
    destructor Done; virtual;
    Procedure Intro;
    procedure Dispatcher; {main program loop}

    private

    NoteLabels:array [0..noteEnd] of noteLabelType; {label of each note}
    maxx,maxy:byte; {maximum x and y positions per physical screen}
    MyInput:PInput;
    IntroScreen,TrackerScreen,HelpScreen,StatusScreen,PianoScreen:PScreen;
    idleevents:longint; {number of idle events in the editor}
    defaultoctave:shortint;
    videoDevice:videochoices;

    {init note labels for use in the editor}
    Procedure PopulateNoteLabels;
    {prettyprinting help}
    Function CenterJustify(var s:str80):byte;
    Function RightJustify(var s:str80):byte;
    Function PromptUser(statement:str80;yesno:boolean):str80;
    Procedure LoadSongPrompt;
    Procedure SaveSongPrompt;
	Function WriteDumpPrompt:str80;
    Procedure EnterEffectPrompt;
    Procedure EnterOrderPrompt;
    Function GetString:str80;
    Procedure RepaintPatternDisplay(full:boolean); {if "full" then do static parts too}
    Procedure ChangeDefaultOctave(s:shortint); {alters default octave used in note entry}
    Procedure EnterNote(noteaction:useractions); {enters note at current songpos and moves downward}
    Procedure WriteDump;
  end;

implementation

uses
  mt_intro,
  m6845ctl,
  strings,
  {$IFDEF DEBUG}
  ztimer,
  {$ENDIF}
  support;

const
  keyfname='default.key';

{ --- support functions --- }
(*
Function HexNybble(w:word):char;
inline(
  $58/               {pop    ax}
  $3C/$0A/           {cmp    al,0A}
  $1C/$69/           {sbb    al,69}
  $2F                {das}
);
*)

const
  HexNybble:array[0..15] of char='0123456789ABCDEF';

Function TTracker.CenterJustify;
begin
  CenterJustify:=(maxx div 2)-(length(s) div 2);
end;

Function TTracker.RightJustify;
begin
  RightJustify:=maxx-length(s);
end;

{ --- TPlayer methods --- }

Constructor TPlayer.Init;
begin
  Inherited Init;
  
  {Initialize our song data -- we only support one format in this version,
  so that's why we're explicitly specifying the descendant.  Future versions
  will be able to load/save other file formats so they will need to handle
  this more gracefully...}
  MySong:=new(PMTSong,init(numtracks));

  {Now that we have song initialized, we can fire up player and output device.}
  audioDevice:=device;
  InitPlaySubsystem;
end;

Destructor TPlayer.Done;
begin
  KillPlaySubsystem;
  Dispose(Mysong,Done);

  Inherited Done;
end;

Function TPlayer.load;
begin
  load:=false;

  if MySong^.load(filename) then
  begin
    {if song load was successful, re-init the playback subsystem because
    the number of tracks may have changed!}
    KillPlaySubsystem;
    InitPlaySubsystem;
	
	load:=true;
  end;
end;

Procedure TPlayer.InitPlaySubsystem;
const
  {error strings needed for this section}
  es_OutputDeviceNotSupported:PChar=
  'Output device not yet supported; re-run and pick another one?';

begin
  {init player, passing song to it so it knows what to play}
  MyPlayer:=new(PMTV1Player,Init(MySong));
  {$IFNDEF DEBUG}
  {...then the output device, with a hook to the player}
  case audioDevice of
    PIT:begin
(*      MyOutput:=new(PPCSpeakerSimple,Init(MyPlayer,true)); equalsharetru*)
      MyOutput:=new(PPCSpeakerSimple,Init(MyPlayer,false));
    end;
    YM3812:begin
      MyOutput:=new(PYM3812,Init(MyPlayer));
    end;
    SN76489:begin
      MyOutput:=new(PSN76489,Init(MyPlayer));
    end;
    else begin
      fatalerror(8,strpas(es_OutputDeviceNotSupported));
    end;
  end; {case}
  (*
  {OMasterDevice is called from interrupt handler and set to @Self on init.
  Just in case that process fails, we can do it here, although clunky:}
  OMasterDevice:=MyOutput;
  *)

  {Cross your fingers:}
  MyOutput^.hookPlayer(playerTimeSliceFreq);
  {$ENDIF}
end;

Procedure TPlayer.KillPlaySubSystem;
begin
  {stop the interrupt}
  {$IFNDEF DEBUG}
  MyOutput^.unHookPlayer;
  {$ENDIF}
  {order is important!}
  {$IFNDEF DEBUG}
  Dispose(MyOutput,Done);
  {$ENDIF}
  Dispose(MyPlayer,Done);
end;

Procedure TPlayer.DumpSongData;
begin
  MyOutput^.OpenDump(filename);

  while MyPlayer^.curAction <> pa_Stop do
  begin
    MyPlayer^.calcAllChannels;
    MyOutput^.dumpAllChannels;
  end;
  
  MyOutput^.CloseDump;
end;

Procedure TPlayer.WriteDumpFile;
var
  oldLooping:boolean;
  oldOrder:word;
  oldRow:word;
  oldTempo:word;
begin
  if filename<>'' then
  begin
    {Stop music}
	MyPlayer^.Send(pa_Stop);
    {Disable Interrupt}
	MyOutput^.unHookPlayer;
	{Save old song state}
	oldLooping:=MyPlayer^.looping;
	oldTempo  :=MyPlayer^.tickCount;
	oldOrder  :=MySong^.currentOrder;
    oldRow    :=MySong^.currentLoc.row;
	{Disable looping and start from top}
	MyPlayer^.looping:=false;
	{MySong^.currentOrder      :=0;
	MySong^.currentLoc.pattern:=MySong^.Orders[0];
    MySong^.currentLoc.row    :=0;
	MyPlayer^.tickCount:=MyPlayer^.Tempo;}
	MyPlayer^.Send(pa_playSongTop);
	{Dump all song data}
	DumpSongData(filename);
	
	{Restore old song state}
	MyPlayer^.looping         :=oldLooping;
	MyPlayer^.tickCount       :=oldTempo;
	MySong^.currentOrder      :=oldOrder;
	MySong^.currentLoc.pattern:=MySong^.Orders[oldOrder];
    MySong^.currentLoc.row    :=oldRow;
    {Enable Interrupt}
	MyOutput^.hookPlayer(playerTimeSliceFreq);
  end;
end;

{ --- TTracker methods --- }

Constructor TTracker.Init;
var
  temps:str80;
  uloop:useractions;
begin
  Inherited Init(device,numtracks);
  {idleevents:=0; shouldn't be necessary because of inherited Init}
  PopulateNoteLabels;
  DefaultOctave:=3;

  {Initialize our input subsystem}
  new(MyInput,init);
  if not fileexists(keyfname)
    then fatalerror(1,'Keybindings file "'+keyfname+'" not found; please run MTCONFIG');
  myinput^.loadstate(keyfname);

  {fire up the screens}
  case mode of
    truecga,generic:asm
      mov ax,0001
      int 10h
    end;
  end;
  maxx:=40; maxy:=25;
  case mode of
    truecga:begin
      {m6845_WaitVertRetrace;
      m6845_SetModeTable(0); these three lines weren't consistently working; had to disable :-(
      m6845_SetMode(c_videosignal_enable);}
      IntroScreen:=new(PCGAScreen,Init($b800,maxx,maxy));
      TrackerScreen:=new(PCGAScreen,Init($b800,maxx,maxy));
      HelpScreen:=new(PCGAScreen,Init($b800,maxx,maxy));
      StatusScreen:=new(PCGAScreen,Init($b800,maxx,maxy));
      PianoScreen:=new(PCGAScreen,Init($b800,maxx,maxy));
    end;
    generic:begin
      IntroScreen:=new(PGenericScreen,Init($b800,maxx,maxy));
      TrackerScreen:=new(PGenericScreen,Init($b800,maxx,maxy));
      HelpScreen:=new(PGenericScreen,Init($b800,maxx,maxy));
      StatusScreen:=new(PGenericScreen,Init($b800,maxx,maxy));
      PianoScreen:=new(PGenericScreen,Init($b800,maxx,maxy));
    end;
  end; {case}

  {give each screen something to have on it for testing}
  IntroScreen^.Show;

  With TrackerScreen^ do begin
    SetBackC(black);
    Clear(0);
    {Print('This is the Tracker screen');}
    ShowCursor;
  end;

  {myInput MUST be initialized first or our input calls lock up the machine!}
  With HelpScreen^ do begin
    SetBackC(green);
    clear(0);
    DrawBox(0,0,HelpScreen^.numcols-1,HelpScreen^.numrows-1,thickhor,'Help Screen');
    state.cursorfollows:=false;
    temps:='Run MTCONFIG.EXE to reconfigure keys';
    moveto(centerJustify(temps),1);
    print(temps);
    temps:='Consult KEYLIST.TXT for the full list';
    moveto(centerJustify(temps),numrows-2);
    print(temps);

    moveto(1,3);

    for uloop:=low(useractions) to high(useractions) do begin
      case descriptions[uloop].act of
        goTrackerScreen,goHelpScreen,goStatusScreen,
        noteOff,eraseNote,octaveup,octavedown,
        playPattern,playSongTop,playSongCur,stopPlaying,mark,pastetrack,pastePattern,
        Enter,Erase,
        transup,transdown,
        loadsong,savesong,quit:begin
          temps:=myinput^.KeypressFromAction(Descriptions[uloop].act)+': '+strpas(Descriptions[uloop].sDes);
          print(temps);
          movedown(1);
        end;
      end;
    end;
    moveto(numcols div 2,3);
    setForeC(LightCyan);
    Print('Supported Effects:');
    movedown(1); Print('0: Arpeggio 0xy');
    movedown(1); Print('1: Slide up 1xx');
    movedown(1); Print('2: Slide down 2xx');
    movedown(1); Print('3: Slide note 3xx');
    movedown(1); Print('4: Vibrato 4xy');
    movedown(1); Print('B: Pos. Jump Bxx');
    movedown(1); Print('D: Pat. Break Dxx');
    movedown(1); Print('F: Set Speed Fxx');
  end;

  With StatusScreen^ do begin
    SetBackC(lightgray);
    setForeC(blue);
    Clear(0);
    temps:='Status Screen';
    moveto(RightJustify(temps),0);
    Print(temps);
    HideCursor;
  end;

  With PianoScreen^ do begin
    SetBackC(lightgray);
    SetForeC(black);
    Clear(0);
    Print('Player piano screen (not ready, sorry)');
  end;

  activeScreen:=IntroScreen;
end;

Destructor TTracker.Done;
{$IFDEF PROFILE}
var
  b:byte;
{$ENDIF}
begin
  Dispose(IntroScreen,Done);
  Dispose(TrackerScreen,Done);
  Dispose(HelpScreen,Done);
  Dispose(StatusScreen,Done);
  Dispose(PianoScreen,Done);

  Dispose(MyInput,Done);

  asm
    mov ax,0003
    int 10h
  end;

  {$IFDEF PROFILE}
  for b:=0 to numpslots-1 do writeln('Slot ',b,': ',pslots[b]);
  {$ENDIF}

  Inherited Done;
end;

Procedure TTracker.PopulateNoteLabels;
{populates note labels}
var
  numnotes,oct,curidx:byte;
const
  Labels:array[0..IBO-1] of string[2] = (
  'C-','C#','D-','D#','E-','F-','F#','G-','G#','A-','A#','B-'
  );
begin
  {init label lookup}
  {0 through 3 are stragglers}
  noteLabels[0]:='---'; NoteLabels[1]:='A-0'; NoteLabels[2]:='A#0'; NoteLabels[3]:='B-0';
  {4 to 15 is octave 1, 16 to 27 is octave 2, etc.}
  curidx:=4;
  for oct:=1 to numOctaves do begin
    for numnotes:=0 to IBO-1 do begin
      NoteLabels[curidx]:=labels[numnotes]+intToStr(oct);
      inc(curidx);
    end;
  end;
  NoteLabels[curidx]:='C-'+inttostr(oct+1);
  inc(curidx);
  for numnotes:=curidx to noteEnd-1 do NoteLabels[numnotes]:='???';
  NoteLabels[noteEnd]:='OFF';
  writeln('ttracker.init finished');
end;

Function TTracker.GetString;
{uses input and screen objects to emulate readln}
var
  temps:str80;
  ch:char;
begin
  temps:='';
  activescreen^.state.cursorFollows:=true;
  activeScreen^.ShowCursor;
  repeat
    activeScreen^.update;
    {wait for a keystroke}
    repeat until myinput^.kb^.keypressed;
    {add chars to string}
    ch:=chr(myinput^.kb^.lastkeypressed.ascii);
    case ch of
      #32..#127:begin
        temps:=temps+chr(myinput^.kb^.lastkeypressed.ascii);
        activeScreen^.Print(ch);
      end;
      #8:if length(temps)<>0 then begin {backspace}
        dec(byte(temps[0]));
        activescreen^.moveover(-1);
        activeScreen^.Print(' ');
        activescreen^.moveover(-1);
      end;
      #27:begin
        {ESC pressed, so pass empty string and exit}
        GetString:='';
        exit;
      end;
    end; {case}
  until (myinput^.kb^.lastkeypressed.ascii=13); {until we get ENTER}

  GetString:=temps;
end;

Function TTracker.PromptUser;
const
  wstartx:byte=5;
  wstarty:byte=12;
  wheight=3;
  wwidth:byte=30;
  wbuffer=4; {number of chars wider than title; must be even}
var
  temps:str80;
begin
  with activeScreen^ do begin
    savestate;

    setBackC(LightGray);
    setForeC(black);
    wwidth:=length(statement)+wbuffer;
    if wwidth>numcols-wbuffer then wwidth:=numcols-wbuffer;
    wstartx:=(numcols div 2)-(wwidth div 2);
    wstarty:=(numrows div 2)-(wheight div 2);
    popup(wstartx,wstarty,wstartx+wwidth-1,wstarty+wheight-1,statement);
    if yesno
      then begin
        repeat until myinput^.kb^.keypressed;
        temps:=upcase(char(MyInput^.KB^.LastKeyPressed.ascii));
      end else begin
        temps:=GetString;
      end;
    RemovePop;

    restorestate;
  end;
  PromptUser:=temps;
end;

Procedure TTracker.LoadSongPrompt;
var
  st:str80;
begin
  st:=PromptUser('Name of file to load?',false);
  if not Mysong^.load(st)
    then activeScreen^.VisibleBell
    else begin
      {if song load was successful, re-init the playback subsystem because
      the number of tracks may have changed!}
      KillPlaySubsystem;
      InitPlaySubsystem;
      Mysong^.filename:=st;
    end;
  RepaintPatternDisplay(true); {do full repaint in case number of tracks changed}
end;

Procedure TTracker.SaveSongPrompt;
var
  st:str80;
begin
  st:=PromptUser('Save to what filename?',false);
  if not MySong^.save(st)
    then activeScreen^.VisibleBell
    else MySong^.filename:=st;
end;

Function TTracker.WriteDumpPrompt: str80;
begin
  WriteDumpPrompt:=PromptUser('Write dump to what filename?',false);
end;

Procedure TTracker.EnterEffectPrompt;
var
  st:str80;
  e,p1,p2:byte;
begin
  st:=PromptUser('Enter effect (edd/exy)',false);
  if length(st)=3 then begin
    e:=HexCharToByte(st[1]);
    p1:=HexCharToByte(st[2]);
    p2:=HexCharToByte(st[3]);
    MySong^.SetEffect(e,p1,p2);
  end else ActiveScreen^.VisibleBell;
end;

Procedure TTracker.EnterOrderPrompt;
var
  st:str80;
  o:byte;
begin
  st:=PromptUser('What pattern at this pos?',false);
  if length(st)=2 then begin
    o:=(HexCharToByte(st[1]) shl 4)+HexCharToByte(st[2]);
    MySong^.Orders[MySong^.CurrentOrder]:=o;
  end else ActiveScreen^.VisibleBell;
end;

Procedure TTracker.RepaintPatternDisplay;
{
Repaints the pattern display.  Must do so without specifically asking the
song to move to a new location.  If full repaint requested, repaint
the entire screen and highlight the active area.

For the very first release of the tracker, only the first 4 tracks are
painted! Also, the tracker display will have a thickver window around
it to be nice, and this first release will bottom-left-justify the
pattern display.  Finally, this version is limited to 40 total columns.

Later versions of the tracker (that support more than 4 tracks ;-)
will have to make this routine a little more intelligent and flexible;
for example:
  Display as many tracks as the screen will allow, with cursor always visible
  support any display width
  Rewrite the code so it isn't so damn clunky and fugly
  Gather all 16 rows of pattern data before printing (new TSong method will
  be required for this)

Should look something like this:

ÕÍÍÑÍÍÍÍÍÍÍÑÍÍÍÍÍÍÍÑÍÍÍÍÍÍÍÑÍÍÍÍÍÍÍ¸
³rw³nnn edd³nnn edd³nnn edd³nnn edd³
ÃÄÄÅÄÄÄÄÄÄÄÅÄÄÄÄÄÄÄÅÄÄÄÄÄÄÄÅÄÄÄÄÄÄÄ´
³00³--- ---³--- ---³--- ---³--- ---³
³01³--- ---³--- ---³--- ---³--- ---³
...etc.
But we don't repaint static areas (top three, frame) every time unless
specifically requested.

BTW, I apologize for the assembler but I really need all the speed I can get
in this section.  Trying to edit a 4-channel song on an original PC is very
sluggish and the inner loops are much of the problem.  If the assembler
is too hard to follow, just delete it and uncomment the line(s) it was
meant to speed up.  Same goes for the profiling code...
}

const
  {colors}
  normalRowCol=(black shl 4)+green;
  currentRowCol=(lightgray shl 4)+black;
  currentCellCol=(blue shl 4)+yellow;
  activeFrameCol=(black shl 4)+White;
  passiveFrameCol=(black shl 4)+LightGray;

  PatHeight=16;
  OrdWidth=4;
  OrdHeight=16;

  headersize=3; footersize=1; extraroom=headersize+footersize;
  leftborder=1; rightborder=1; cellwidth=8;

  tempbf:byte=0;
  
  inHandler:boolean=false;

var
  {locations, sizes, etc.}
  style:boxtypes;
  starty,endy,startingx,rows,tracks,height:byte;
  loop,track,trackend,startrow,curRow,b,b1,b2,oldx:byte;
  loc:locationtype;
  curNote:pointer;
  temps:str40;
  w:word;
  strBaseP:pointer; {used to precalc location of temp string}
  sep:char; {vertical seperator for columns}
begin
  if inHandler then Exit;
  
  inHandler:=true;

  style:=thickhor;
  with TrackerScreen^ do begin
    {precalc here:}
	loc:=MySong^.CurrentLoc;
    endy:=numrows-footersize; {leave room for window border}
    height:=((numrows-extraroom) div PatHeight) * PatHeight; {so we have even multiple of rows for nrows != power of 2}
    starty:=endy-PatHeight;
    state.cursorfollows:=false; HideCursor; {turn off cursor and don't follow it}
    curRow:=MySong^.CurrentLoc.row;
	startRow:=curRow;
    if startrow<(PatHeight div 2) {lets cursor stay centered in pattern}
      then startrow:=0
      else dec(startrow,(PatHeight div 2));
    if (startrow+PatHeight)>=maxRows then startrow:=maxRows-PatHeight; {make sure we don't print past the song!}
    trackend:=MySong^.numtracks-1;
    if trackend>3 then trackend:=3; {Version 1.x is INflexible and stops at 4 tracks}

    if full then begin {full repaint requested}
      Clear(0);
      {pattern frame}
      if activeArea=TrackerArea
        then State.backfore:=activeFrameCol
        else State.backfore:=passiveFrameCol;
      DrawBox(0,starty-headersize,leftborder+2+(cellwidth*MySong^.numtracks),endy,style,'');
      moveto(0,starty-headersize+1);
      temps:=boxchars[style].ver+'rw';
      for track:=0 to trackend do temps:=temps+boxchars[style].ver+'nnn edd';
      Print(temps);
      movedown(1);
      temps:=boxchars[style].lj+boxchars[style].hor+boxchars[style].hor;
      for track:=0 to trackend do begin
        temps:=temps+boxchars[style].mj;
        for loop:=1 to cellwidth-1 do temps:=temps+boxchars[style].hor;
      end;
      temps:=temps+boxchars[style].rj;
      Print(temps);

      {order frame}
      if activeArea=OrderArea
        then State.backfore:=activeFrameCol
        else State.backfore:=passiveFrameCol;
      moveto(numcols-OrdWidth,0 +5);
      Print('Ordr');
      movedown(1);
      Print('List');
      movedown(1);
      DrawBox(State.x,State.y,numcols-1,State.y+OrdHeight+1,style,'');
    end;

    {draw pattern display}
    moveto(leftborder,starty);
    state.cursorfollows:=true;
	
	for loc.row:=startrow to (startrow+PatHeight-1) do begin
      with MySong^ do begin
        {SaveState;} oldx:=State.x;
        {two printing routines, one for normal and one for special cases, for speed reasons}
        if loc.row<>curRow then begin
          {Build and display a regular, non-highlighted row}
          state.backfore:=normalRowCol;
          strBaseP:=@temps; {I hate dealing with Self pointer ;-}
          temps:=ByteToHex(loc.row);
          sep:=boxchars[style].ver;
          for loc.track:=0 to trackend do begin
		    curNote:=GetNotePtr(loc);
            {$IFDEF PROFILE} _LZTimerOn; {$ENDIF}
            {$IFNDEF OPT8088}
            temps:=temps+sep;
            {$ELSE}
            asm
              {Append a "separator" character.  Since we're only appending a
              single character, we use more optimized code:}
              les   di,strBaseP        {es:di=string location}
              xor   ax,ax
              mov   al,es:[di]         {ax=length of string}
              inc   ax                 {increase ax by size we are appending}
              stosb                    {store it back and advance di by 1}
              dec   ax                 {subtract back to original value}
              add   di,ax              {advance di to point to end of string}
              mov   al,sep             {fill al with blank character}
              stosb                    {store blank character}
            end;
            {$ENDIF}
            {$IFDEF PROFILE} _LZTimerOff; pslots[7]:=_LZTimerCount; {$ENDIF}
            temps:=temps+notelabels[GetNoteByPtr(curNote)];
            {$IFDEF PROFILE} _LZTimerOn; {$ENDIF}
            {$IFNDEF OPT8088}
            temps:=temps+#0;
            {$ELSE}
            asm
              {Append a "blank" #0 character.  Since we're only appending a
              single character, we use more optimized code:}
              les   di,strBaseP        {es:di=string location}
              xor   ax,ax
              mov   al,es:[di]         {ax=length of string}
              inc   ax                 {increase ax by size we are appending}
              stosb                    {store it back and advance di by 1}
              dec   ax                 {subtract back to original value}
              add   di,ax              {advance di to point to end of string}
              xor   al,al              {make al=0, a nonprinting character}
              stosb                    {store blank character}
            end;
            {$ENDIF}
            {$IFDEF PROFILE} _LZTimerOff; pslots[8]:=_LZTimerCount; {$ENDIF}
            {$IFDEF PROFILE} _LZTimerOn; {$ENDIF}
            w:=GetEffectByPtr(curNote);
            {$IFDEF PROFILE} _LZTimerOff; pslots[1]:=_LZTimerCount; {$ENDIF}
            if w=0 {if effect empty, then dummy string}
              then begin
                {$IFNDEF OPT8088}
                temps:=temps+'---';
                {$ELSE}
                asm
                  {Append "---" to the string:}
                  les   di,strBaseP {es:di = string location}
                  xor   ax,ax
                  mov   al,es:[di]
                  mov   dx,ax   {hold onto original length for later}
                  add   al,3    {increase it by size we are appending}
                  stosb         {store it back; advance di}
                  add   di,dx   {advance di end of string}
                  mov   ax,'--' {fill ax with blank character}
                  stosw         {fill two blanks}
                  stosb         {fill third blank}
                end;
                {$ENDIF}
              end else begin {effect not empty; build effect string}
                {$IFNDEF OPT8088}
                {w:=GetEffectByPtr(curNote);}
                b1:=hi(w); b2:=lo(w);
                temps:=temps+hexnybble[(b1 AND $0F)]+ByteToHex(b2);
                {$ELSE}
                asm
                  les   di,strBaseP {es:di = string location}
                  xor   ax,ax
                  mov   al,es:[di]
                  mov   dx,ax
                  add   al,3    {increase it by size we are appending}
                  stosb         {store it back}
                  add   di,dx   {advance to end of string}
                  mov   bx,w    {grab effect param}
                  mov   al,bh   {Convert effect to ascii equivalent:}
                  cmp   al,10   {if x<10, set CF=1}
                  sbb   al,69h  {0-9: 96h..9Fh, A-F: A1h..A6h}
                  das           {0-9: subtr. 66h -> 30h-39h;
                                 A-F: subtr. 60h -> 41h-46h}
                  stosb         {append to string}
                  mov   al,bl   {get remaining nybbles}
                  mov   ah,al
                  shr   ah,1    {prepare ah for later conversion}
                  shr   ah,1
                  shr   ah,1
                  shr   ah,1
                  and   al,00001111b
                  cmp   al,10
                  sbb   al,69h
                  das           {first ASCII byte is in al}
                  xchg  ah,al
                  cmp   al,10
                  sbb   al,69h
                  das           {second ASCII byte is in al, first in ah}
                  stosw         {store result to destination string}
                end;
                {$ENDIF}
				
			  end;
              
		    end;
          print(temps);
        end else begin
          {uncommon highlighted row:}
          state.backfore:=currentRowCol;
          print(ByteToHex(loc.row));
          for loc.track:=0 to trackend do begin
            curNote:=GetNotePtr(loc);
            if loc.track=currentLoc.track
              then state.backfore:=currentCellCol
              else state.backfore:=currentRowCol;
            temps:=boxchars[style].ver+notelabels[GetNoteByPtr(curNote)]+' ';
            w:=GetEffectByPtr(curNote);
            if w=0 {if effect empty, then dummy string}
              then temps:=temps+'---'
              else begin {effect not empty; build effect string}
                {$IFNDEF OPT8088}
                b1:=hi(w); b2:=lo(w);
                {$ELSE}
                asm mov ax,w; mov b1,ah; mov b2,al; end;
                {$ENDIF}
                temps:=temps+hexnybble[b1]+ByteToHex(b2);
              end;
            print(temps);
          end;
        end;
        {RestoreState;} State.x:=oldx;
        {movedown(1);} inc(State.y);
      end; {with MySong^}
    end;

    {draw order display}
    state.cursorfollows:=false;
    moveto(numcols-OrdWidth+1,3 +5);
    startrow:=MySong^.CurrentOrder;
    {lets cursor stay centered in pattern}
    if startrow<(OrdHeight div 2)
      then startrow:=0
      else dec(startrow,(OrdHeight div 2));
    {make sure we don't print past the order list end!}
    if (startrow+OrdHeight)>=numOrders then startrow:=numOrders-OrdHeight;
    for loop:=startrow to (startrow+PatHeight-1) do begin
      if loop=MySong^.CurrentOrder
        then state.backfore:=currentRowCol
        else state.backfore:=normalRowCol;
      Print(ByteToHex(MySong^.Orders[loop]));
      {movedown(1);} inc(State.y);
    end;

    {update display}
    if activeArea in [TrackerArea,OrderArea] then Update;
  end;
  
  inHandler:=false;
end;

Procedure TTracker.ChangeDefaultOctave;
begin
  DefaultOctave:=DefaultOctave+s;
  if DefaultOctave<0
    then DefaultOctave:=0;
  if DefaultOctave>numOctaves
    then DefaultOctave:=numOctaves;
end;

Procedure TTracker.EnterNote;
var
  note,doct,modifier:byte;
begin
  doct:=defaultoctave*IBO; {IBO=IntervalsBetweenOctaves=12 notes in an octave}
  {there is probably a more elegant way of doing this, but optimizing this
  part is simply not necessary since it's fast enough even on 8088.  Also,
  doing it this way protects me from myself -- meaning, if I rearrange the
  order of the type, I don't have to alter this section at all.}
  case noteaction of
    c:       modifier:=4;
    csharp:  modifier:=5;
    d:       modifier:=6;
    dsharp:  modifier:=7;
    e:       modifier:=8;
    f:       modifier:=9;
    fsharp:  modifier:=10;
    g:       modifier:=11;
    gsharp:  modifier:=12;
    a:       modifier:=13;
    asharp:  modifier:=14;
    b:       modifier:=15;

    c2:      modifier:=16;
    csharp2: modifier:=17;
    d2:      modifier:=18;
    dsharp2: modifier:=19;
    e2:      modifier:=20;
    f2:      modifier:=21;
    fsharp2: modifier:=22;
    g2:      modifier:=23;
    gsharp2: modifier:=24;
    a2:      modifier:=25;
    asharp2: modifier:=26;
    b2:      modifier:=27;
  end; {case}
  note:=doct+modifier;
  MySong^.SetNote(note);
  MyPlayer^.Send(pa_playnote); {play the note as a convenience to the user}
  MySong^.MoveRow(1);
  RepaintPatternDisplay(false);
end;

Procedure TTracker.Dispatcher;
{
The Dispatcher loops endlessly until receiving a request to exit the
program.  While no input is received, the Dispatcher can do things like
update the screen, do housekeeping, etc.

There are three main CASE statements that act as handlers:  Editing,
screen repainting, and context switching.  For the editing block, no commands
are recognized if the song/pattern is currently playing.
}

  Procedure SwitchContext(a:areatype;s:PScreen);
  {uses videoDevice to determine if special effects are possible with screen^.scrofs}
  var
    loop:word;
    oldofs,newofs:word;

  begin
    if videoDevice=truecga then begin
      {smoothly slide to next screen}
      {missing -- add this!}
    end;
    activeArea:=a;
    activeScreen:=s;
    activeScreen^.Show;
  end;

{some constants to help make the code a little more understandable}
const
  linePat=0;
  lineOct=1;
  idleRefresh=$f;
  lasttick:longint=0;
var
  foos:str80;
  chloop:byte;
  trackloop,rowloop:byte;
  temploc:LocationType;
  tempshort:shortint;
  tempeffect:word;
  {$IFDEF DEBUG}
  wastetime:word;
  {$ENDIF}

begin
  repeat
    if myinput^.inputpending then begin

      {This is the "context" case statement.  See below for repainting and editing.}
      case myinput^.lastinputreceived of
        goTrackerScreen:begin
          SwitchContext(TrackerArea,TrackerScreen);
          RepaintPatternDisplay(true);
        end;
        goStatusScreen:SwitchContext(StatusArea,StatusScreen);
        goHelpScreen:SwitchContext(HelpArea,HelpScreen);
        goPianoScreen:SwitchContext(PianoArea,PianoScreen);
        loadsong:begin
          MyPlayer^.Send(pa_Stop);
          LoadSongPrompt;
          MySong^.currentLoc.track:=0;
        end;
        savesong:begin
          MyPlayer^.Send(pa_Stop);
          SaveSongPrompt;
        end;
        {once there are more than two areas, nextarea and prevarea will need to be separated}
        nextarea,prevarea:if MyPlayer^.curAction in [pa_Idle,pa_Stop] then begin {trackerarea->orderarea->(repeat)}
          if activeArea=TrackerArea
            then activeArea:=OrderArea
            else activeArea:=TrackerArea;
          SwitchContext(activeArea,TrackerScreen);
          RepaintPatternDisplay(true);
        end;
        octaveup:ChangeDefaultOctave(1);
        octavedown:ChangeDefaultOctave(-1);
        stopPlaying:begin
		  MyPlayer^.Send(pa_Stop);
		end;
        playPattern:MyPlayer^.Send(pa_playpattern);
        playSongTop:begin
		  if MySong^.Orders[0]<>$FF {to prevent launching into outer space}
          then MyPlayer^.Send(pa_playsongtop)
          else MyPlayer^.Send(pa_playpattern);
		end;
        playSongCur:
		begin
		  if MySong^.Orders[0]<>$FF {to prevent launching into outer space}
          then MyPlayer^.Send(pa_playsongcur)
          else MyPlayer^.Send(pa_playpattern);
		end;
		writeOut:begin
		  WriteDump;
		end;
        quit:begin
          {ask user if they really want to leave, for accidental presses}
          foos:=PromptUser('Are you sure? (Y/N)',true);
          if foos<>'Y'
            then myinput^.lastInputReceived:=MoveTop {if not a confirmation, stuff input with harmless action}
            else MyPlayer^.Send(pa_Stop); {otherwise stop playing in prep for existing}
        end;
        else begin
          {received input we aren't prepared for yet}
        end;
      end; {case}

      {This is the "editing" case statement.  See below for repainting.
      This was broken out to ensure we do NOT process any commands that could
      change song data while the player engine is accessing it.  It also
      helps provide a consistent presentation to the user (ie. "I'm playing
      right now; if you want something, stop me.")}

      if MyPlayer^.curAction in [pa_Idle,pa_Stop] then case myinput^.lastinputreceived of
        MoveUp:case activeArea of
          TrackerArea:MySong^.MoveRow(-1);
          OrderArea:MySong^.MoveOrder(-1);
        end;
        MoveDown:case activeArea of
          TrackerArea:MySong^.MoveRow(1);
          OrderArea:MySong^.MoveOrder(1);
        end;
        MoveLeft:MySong^.MoveTrack(-1);
        MoveRight:MySong^.MoveTrack(1);
        MoveTop:case activeArea of
          TrackerArea:MySong^.MoveToRow(0);
          OrderArea:MySong^.CurrentOrder:=0;
        end;
        MoveBottom:case activeArea of
          TrackerArea:MySong^.MoveToRow(maxRows-1);
          OrderArea:begin
            {look for the first $ff in the order list and move to it}
            for rowloop:=0 to 255 do begin
              if MySong^.Orders[rowloop]=$ff then begin
                MySong^.CurrentOrder:=rowloop;
                break;
              end;
            end;
          end;
        end;
        MovePgUp:case activeArea of
          TrackerArea:MySong^.MoveRow(-16);
          OrderArea:MySong^.MoveOrder(-16);
        end;
        MovePgDn:case activeArea of
          TrackerArea:MySong^.MoveRow(16);
          OrderArea:MySong^.MoveOrder(16);
        end;
        prevpattern:if MySong^.CurrentLoc.Pattern>0
          then MySong^.MovePattern(-1)
          else activeScreen^.visiblebell;
        nextpattern:if MySong^.CurrentLoc.Pattern<MySong^.maxPattern
          then MySong^.MovePattern(1)
          else activeScreen^.visiblebell;

        c,csharp,d,dsharp,e,f,fsharp,g,gsharp,a,asharp,b,
        c2,csharp2,d2,dsharp2,e2,f2,fsharp2,g2,gsharp2,a2,asharp2,b2:EnterNote(myinput^.LastInputReceived);
        noteoff:if MyPlayer^.curAction in [pa_Idle,pa_Stop] then begin
          MySong^.SetNote(noteEnd);
          MySong^.moverow(1);
        end;
        erasenote:if MyPlayer^.curAction in [pa_Idle,pa_Stop] then begin
          MySong^.SetNote(noteNul);
          MySong^.moverow(1);
        end;
        Enter:if MyPlayer^.curAction in [pa_Idle,pa_Stop] then begin
          case activeArea of
            TrackerArea:EnterEffectPrompt;
            OrderArea:EnterOrderPrompt;
          end;
        end;
        Erase:if MyPlayer^.curAction in [pa_Idle,pa_Stop] then begin
          case activeArea of
            TrackerArea:MySong^.SetEffect(0,0,0);
            OrderArea:MySong^.Orders[MySong^.CurrentOrder]:=$ff;
          end;
        end;

        transup,transdown,transupoctave,transdownoctave:if MyPlayer^.curAction in [pa_Idle,pa_Stop] then begin
          temploc:=MySong^.Currentloc;
          case MyInput^.LastInputReceived of
            transup        :tempshort:=   1;
            transdown      :tempshort:=  -1;
            transupoctave  :tempshort:= IBO;
            transdownoctave:tempshort:=-IBO;
          end; {case}
          for rowloop:=0 to maxRows-1 do begin
            MySong^.MoveTo(MySong^.Currentloc.pattern,MySong^.CurrentLoc.track,rowloop);
            if MySong^.GetNote in [1..noteEnd-1]
              then MySong^.SetNote(MySong^.GetNote+tempshort);
          end;
          MySong^.CurrentLoc:=temploc;
        end;

        mark:ClipBoard:=MySong^.CurrentLoc;
        pastetrack:begin
          temploc:=MySong^.CurrentLoc;
          for rowloop:=0 to maxRows-1 do begin
            MySong^.MoveTo(MySong^.CurrentLoc.pattern,MySong^.CurrentLoc.track,rowloop);
            MySong^.SetNote(MySong^.GetNoteAbsolute(clipboard.pattern,clipboard.track,rowloop));
            tempeffect:=MySong^.GetEffectAbsolute(clipboard.pattern,clipboard.track,rowloop);
            MySong^.SetEffect(hi(tempeffect), (lo(tempeffect) AND $f0) shr 4, lo(tempeffect) AND $0f);
          end;
          MySong^.CurrentLoc:=temploc;
        end;
        pastePattern:begin
          temploc:=MySong^.CurrentLoc;
          for rowloop:=0 to maxRows-1 do begin
            for trackloop:=0 to MySong^.numTracks-1 do begin
              MySong^.MoveTo(MySong^.CurrentLoc.pattern,trackloop,rowloop);
              MySong^.SetNote(MySong^.GetNoteAbsolute(clipboard.pattern,trackloop,rowloop));
              tempeffect:=MySong^.GetEffectAbsolute(clipboard.pattern,trackloop,rowloop);
              MySong^.SetEffect(hi(tempeffect), (lo(tempeffect) AND $f0) shr 4, lo(tempeffect) AND $0f);
            end;
          end;
          MySong^.CurrentLoc:=temploc;
        end;

        else begin
          {received input we aren't prepared for yet}
        end;
      end; {case}

      {This is the "repainting" case statement.  We only repaint when necessary.}
      case myinput^.lastinputreceived of
        MoveUp,MoveDown,MoveLeft,MoveRight,
        MoveTop,MoveBottom,MovePgUp,MovePgDn,
        noteoff,erasenote,
        pastepattern,
        transup,transdown,transupoctave,transdownoctave,
        nextarea,prevarea,
        pastetrack,
        Enter,
        Erase:RepaintPatternDisplay(false);
        prevpattern,nextpattern:begin
          TrackerScreen^.MoveTo(0,linePat);
          TrackerScreen^.Print('Editing Pattern: '+ByteToHex(MySong^.CurrentLoc.Pattern));
          if activearea=trackerarea then TrackerScreen^.Update;
          RepaintPatternDisplay(false);
        end;
        octaveup,octavedown:begin
          TrackerScreen^.moveTo(0,lineOct);
          TrackerScreen^.Print('Default octave: '+inttostr(DefaultOctave+1));
          if activearea=trackerarea then TrackerScreen^.Update;
        end;
        mark:ActiveScreen^.VisibleBell;
      end;{case}

    end else begin
      {no input pending, so update status and otherwise do housekeeping}
      inc(idleevents);
      {$IFDEF DEBUG}
      _LZTimerOn;
      MyPlayer^.CalcAllChannels;
      _LZTimerOff;
      {$ENDIF}
      {no need to repaint every time; we'll repaint 18.2 times a second}
      {$IFNDEF DEBUG} if (TicksSinceMidnight <> lasttick) then {$ENDIF} begin
        lasttick:=TicksSinceMidnight;
        with StatusScreen^ do begin
          state.cursorFollows:=false;
          moveto(0,0); Print('# idle user events: '+inttostr(idleevents));
          movedown(1); Print('Editing: '+MySong^.FileName+' ('+inttostr(MySong^.numTracks)+'-track song)');
          movedown(1); Print('Song data='+inttostr(MySong^.datasize)+' bytes ('+inttostr(maxavail)+ ' remain)');
          movedown(1); Print('Using '+inttostr(MySong^.numPatterns)+'/'+inttostr(MySong^.maxPattern)+' patterns');
          {$IFNDEF DEBUG}
          movedown(1); Print('# outputdevice calls: '+inttostr(myoutput^.callCount));
          {$ENDIF}
          movedown(1); Print('# playerengine calls: '+inttostr(myplayer^.callCount));
          {$IFDEF DEBUG}
          movedown(1); Print('CalcAllData took: '+inttostr(ticks2micro(_LZtimerCount))+' æsec  ');
          movedown(1); Print('CalcAllData took: '+inttostr(ticks2ms(_LZtimerCount))+' ms  ');
          {$ENDIF}
          movedown(1); foos:='Current location: '
            +'p'+ByteToHex(mysong^.CurrentLoc.Pattern)+','
            +'r'+ByteToHex(mysong^.CurrentLoc.Row)+','
            +'t'+ByteToHex(mysong^.CurrentLoc.Track)+' ';
          Print(foos);
          {channel info}
          movedown(1);
          foos:='intervals: ';
          for chloop:=0 to MyPlayer^.numVChannels-1 do
            foos:=foos+inttostr(myplayer^.vchannels[chloop].noteInterval)+'  ';
          print(foos);

          movedown(1);
          foos:='frequency: ';
          for chloop:=0 to MyPlayer^.numVChannels-1 do
            foos:=foos+inttostr(myplayer^.vchannels[chloop].frequency)+'  ';
          print(foos);

          movedown(1);
          foos:='active: ';
          for chloop:=0 to MyPlayer^.numVChannels-1 do
            foos:=foos+inttostr(byte(myplayer^.vchannels[chloop].active))+'  ';
          print(foos);

          movedown(1);
          foos:='enabled: ';
          for chloop:=0 to MyPlayer^.numVChannels-1 do
            foos:=foos+inttostr(byte(myplayer^.vchannels[chloop].enabled))+'  ';
          print(foos);

          movedown(1); print('Current order: '+inttostr(mysong^.currentorder));
          movedown(1); print('Tempo: '+inttostr(MyPlayer^.Tempo));
          movedown(1); print('rowtick: '+ByteToHex(MyPlayer^.tickCount));

          activeScreen^.Update;

          {$IFDEF DEBUG}
          if activeArea=statusarea
            then for wastetime:=0 to $fff do begin
              wastetime:=wastetime;
            end;
          {$ENDIF}

        end;
        {if we're on the tracker screen and something is playing, we should repaint}
        if (activeArea in [TrackerArea,OrderArea]) and (MyPlayer^.curAction<>pa_Idle)
          then RepaintPatternDisplay(false);
      end;
    end;

  until myinput^.lastInputReceived=quit;

  {exiting the program here, so clean up}
end;

Procedure TTracker.Intro;
begin
  IntroScreen^.Show;
  DumbIntro(IntroScreen);
  repeat until myinput^.kb^.keypressed;
  activeScreen:=HelpScreen;
  activeScreen^.Show;
end;

Procedure TTracker.WriteDump;
var
  filename:str80;
begin
  filename:=WriteDumpPrompt;
  if filename<>'' then
	WriteDumpFile(filename);
end;

end.
