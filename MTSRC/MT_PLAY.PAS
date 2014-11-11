{$I MT_DEFS.INC}

unit mt_play;
{calculates sound data from a row of song object note data}

{
(REMINDER:  MONOTONE is not a tracker for any one specific output device,
but rather emulates a simple state machine that can be translated to any
number of output devices.)

The player object exists to process song data into data that an output
device can use to make sound.  It is responsible for interpreting data
like notes and effects and outputting volume, frequency, instrument,
etc.  It also takes commands (like setting a single note) and converts
that the same way.

The player operates by asking the song object to move to a certain
location and then retrieving an entire row of data (via a pointer
provided  by the song object) and processing it into a public data
structure of  "virtual channels".  Virtual channels have the following
characteristics:  Note frequency, note interval (player resolution of a
note interval is *not* according to the 12th root of 2, but rather 8
times that (96th root of 2) for granularity), and volume.

A note about why note interval data is put into the virtual channel
structures:  1. for the benefit of output devices that cannot deal with
frequency data but rather "prefer" note data (MIDI, etc.) and 2. for
the benefit of devices that can use such data for optimization (pre-calc
tables, etc.).

Because of the way the player accesses song data, each player instance
is hard-coded to the song format it supports. This was done
intentionally for speed reasons; song processing, while ideally as
lightweight as possible, absolutely *must* complete in less than 1/60th
of a second or the song will not play properly.  In a 12-track song, 24
calls for 12 notes of data and 12 effects is not speed-efficient.

Programming considerations:
- On altering a song's number of tracks (through loading or otherwise),
player object must be disposed of and then re-initialized.  This may
require the outputdevice object to also be disposed of and then
reinitialized to ensure that the output device does not attempt to call
the playback routine in the middle of its initialization (!).

- It may seem goofy to divide half of the player engine between the
abstract CalcAllData method and its descendants, but the decision to do that
was intentional so that we could support multiple song formats.  Not all
song formats will interpret effects parameters, for example, the same way.
Also, splitting the pattern player off gives us the opportunity to optimize
it for speed, which is one of the goals of this entire system (a way to make
music for demos).
}

interface

uses
  Objects,
  mt_glob,
  mt_song;

const
  defaultTempo=4; {default is 4/60 (1/15th sec) ticks before moving to next row}
  playerTimeSliceFreq=60; {we are supposed to be called at 60Hz no matter
  what rate the output hardware is running at!}

type
  playerActions=(pa_Idle,pa_Stop,pa_PlayNote,pa_PlayPattern,pa_PlaySong);

  {
  This is the data structure that holds the basis of the emulated state
  machine:  One processed track's sound information to be sent to the output
  device.  "channel" is shorthand for "virtual channel" since the player
  doesn't really know what the output device is capable of -- that's the job
  of the outputdevice object.

  Ranges:
    Frequency: 19 to 65535 (although player will only generate 27 to ~8000)
    Volume: 0 (quietest) to 63 (loudest)
    Instrument: #0 to #255
  }
  PChannel=^TChannel;
  TChannel=record {listed in descending order of likelyhood to be found on output device for faster processing}
    enabled:boolean; {If channel is enabled, it is processed and allowed to
    produce sound.  If disabled, it is skipped during processing.
    This field is meant to assist in toggling channels off/on during playback.
    Each hardware output device object may need to implement this differently
    (ie. true multichannel might have to force volume=0 for disabled channels)}
    active:boolean; {If channel is active, should be actively producing sound; if
    not active, it should not be producing sound.  Note "OFF" actions
    make active:=false; any other note action make active:=true}
    noteInterval:word; {made public so that output devices can use for optimization}
    Frequency:word; {not really valid past 20KHz for obvious reasons}
    Volume:byte; {included for future compatibility}
    Instrument:byte; {included for future compatibility}
  end;

  PPEVar=^TPEVar; {PEVar=Player Engine Variable -- housekeeping data}
  {we need to maintain housekeeping data per track for calculations}
  TPEVar=record
    note,                {note data (NOT interval)}
    effect,              {effect, 0-7}
    parm1,               {first effect parameter}
    parm2,               {if applicable, second effect parameter}
    lastNotePlayed:byte; {last note we were told to play; used for arpeggio}
    effectraw:word;      {this aids in short-circuiting effects processing}
    portaStopHz:word;    {frequency to stop at during a porta to note}
    portaDelta:byte;     {delta to be added/subbed to/from current frequency}
    vibSpeed:byte;       {the speed at which the vibrato oscillates}
    vibDepth:byte;       {the depth of the vibrato, in intervals (IBN)}
    vibIndex:byte;       {the current index into the vibrato lookup table}
  end;

  PAllChannels=^TAllChannels;
  TAllChannels=array[0..maxchannels-1] of TChannel;
  PAllVars=^TAllVars;
  TAllVars=array[0..maxchannels-1] of TPEVar;

  TNoteIntervalType=array [0..(maxNote*IBN)] of word;

  PPlayerEngine=^TplayerEngine;
  TPlayerEngine=object(TObject)
    {TPlayerEngine is responsible for actually playing the song.  This means
    processing note data each timeslice so that we have an action (setting
    a frequency or volume, stopping playback, etc.) for each channel
    of music.  It stops/(re)starts/pauses/repositions playback.
    TPlayer is responsible for turning events in the song into frequencies.}

    notesHz:TNoteIntervalType; {Interval-to-Frequency lookup table.  This is
    the key speedup, to avoid calculating the 12th root of 2 every tick.}
    numVChannels:byte; {number of virtual channels we should bother filling}
    VChannels:TAllChannels;  {virtual channel data used by the output object}
    mySong:PSong; {We are an abstract player, so we reference abstract type}
    callCount:longint; {Global number of timeslices we've processed.  This is
    a longint because if it were a 16-bit word it would wrap every 18 minutes,
    and it is our hope that people will use the tracker more than 18 minutes
    at a sitting :-) }
    tickCount:byte; {Local number of ticks we have processed}
    tempo:byte; {number of ticks to process before taking next action}
    curAction:playerActions;

    Constructor Init(theSong:PSong); {contains note data and number of tracks
    to process during each timeslice.  NumTracks is turned into numVChannels and
    initially interpreted internally as the lower of "outputdevice
    capabilities" and "number of tracks in song".  Later versions of this
    object should probably try to do something more intelligent, like
    mapping a track to an unused/non-sounding hardware channel}
    Destructor Done; virtual;
    Procedure Send(action:PlayerActions); {send the player a command}
    Procedure CalcAllChannels; virtual; {calculates all tracks in a timeslice to virtual channel data}

    private

    noteIP,patIP,songIP:boolean; {In-Progress flags for the playback routine}
    VData:TAllVars;       {virtual channel effects/vars/housekeeping}
  end;

{MONOTONE Version 1 file format specific stuff begins here -----------------}

const
  MTV1MaxParmxx=63; {maximum xx value an MTV1 file can have, 6 bits}
  MTV1MaxParmxy=7;  {maximum xy (x or y) value an MTV1 file can have, 3 bits}
  MTV1VibTableSize=32; {size of vibrato table; must be power of 2}
  MTV1VibTableDepth=IBN*(MTV1MaxParmxy+1); {+/- from 0, must be power of 2}
  {The goal is for the vibrato go to +/-(ParmXY+1) semitones from the base note.
  For example, if table is +/-64, (((table[i]) * vibDepth) div 64) will work.}

type
  PMTV1VibratoType=^TMTV1VibratoType;
  TMTV1VibratoType=array[0..MTV1VibTableSize-1] of shortint; {vibrato lookup table}

  PMTV1Player=^TMTV1Player;  {MTV1 stands for MONOTONE format version 1}
  TMTV1Player=object(TPlayerEngine)
    VibTable:TMTV1VibratoType;
    {The only thing that differentiates players from the abstract player
    is that they handle different data formats.  So, the CalcAllChannels
    procedure, and the Constructor if any init vars are different,
    are all that need to change.}
    Constructor Init(theSong:PSong);
    Procedure CalcAllChannels; virtual;
  end;

implementation

{$IFDEF CGA_PROFILE}
uses
  m6845ctl; {to grab color constants}
{$ENDIF}

function root(x,y:real):real; {find the xth root of y}
begin
  root:=exp(ln(y)/x);
end;

Constructor TPlayerEngine.Init;

var
  numnotes:word;
  interval:real;
  temphz:real;
  b:byte;

begin
  Inherited Init;

  {inherited Init should have set callcount and the rest to 0}
  mySong:=theSong;
  numVChannels:=mySong^.numTracks;

  {set up noteshz here}
  interval:=root(IBO*IBN,2);
  {first 8 indexs should never be called, but we'll set to a "safe" value
  just in case something tries to divide by it}
  notesHz[0]:=440;
  temphz:=27.5; {our virtual piano starts at A0 which is 27.5 Hz}
  notesHz[1*IBN]:=round(temphz);
  {fill in the bottom}
  for numnotes:=(1*IBN)-1 downto 1 do begin
    temphz:=temphz / interval; {divide because we're going downward}
    if temphz<19 then temphz:=19; {timer physically can't go below 18.2Hz}
    {convert result into integer frequency}
    notesHz[numnotes]:=round(temphz);
  end;
  temphz:=27.5; {our virtual piano starts at A0 which is 27.5 Hz}
  notesHz[1*IBN]:=round(temphz);
  for numnotes:=(1*IBN)+1 to (MaxNote*IBN) do begin
    {calc next fractional note interval}
    temphz:=temphz*interval;
    {convert result into integer frequency}
    notesHz[numnotes]:=round(temphz);
  end;

  {set default tempo}
  tempo:=mysong^.numtracks; {for the benefit of any single-voice arpeggiator devices}
  if tempo<defaulttempo then tempo:=defaulttempo;

  curAction:=pa_Idle; noteIP:=false; patIP:=false; songIP:=false;

  {initalize the virtual channels}
  for b:=0 to maxChannels-1 do begin
    with VChannels[b] do begin
      enabled:=true;
      active:=false;
      volume:=63; {until we support volume control, we assume the loudest}
    end;
  end;
end;

Destructor TPlayerEngine.Done;
begin
  {mystuff}
  Inherited Done;
end;

Procedure TPlayerEngine.Send;
begin
  curAction:=action;
  if action=pa_PlayNote
    then CalcAllChannels; {we have to start playing NOW before the row
    advances in the user program}
end;

Procedure TPlayerEngine.CalcAllChannels;
{
This is where commands are interpreted into virtual channel data.
This is the abstract portion, where only the simplest and most obvious
calculations are done.  The real heavy lifting (playing a pattern or
an entire song) is left to descendants of CalcAllChannels so that they
can implement those operations the most efficiently for the song format
they support.

How actions are handled:

idle: Do nothing.  When other actions are finished, they reset curaction
to idle.

Stop: Marks all virtual channels as not active.

Playnote:  Sets VChannel 0 to play a note, hold it for 4 ticks, then calls
Stop.

PlayPattern: (not implemented in abstract method) Plays current pattern
and then calls Stop.

PlaySong: (not implemented in abstract method) Plays current song by
playing patterns in the order presented in the Order list, then calls Stop.

We have to have a semaphore indicating whether
or not we're already in the handler for one reason: There is ONE place
CalcAllChannels is called outside of the handler, and that's when the
user requests to play a single note.  The note must begin playing before
the song.row advances, so we start calcing immediately.  Unfortunately,
the interrupt could fire while we're in the middle of setting up our
note to play, so the CalcAllData called by the handler has
to make sure it doesn't stomp on what is already running.  If something is
already running, the interrupt handler calcAllData aborts.
}

const
  noteduration=4;
  inHandler:boolean=false;

var
  loop:byte;
  tni:word; {temporary note interval placeholder}

begin
  if not inHandler then begin
    inHandler:=true;
    inc(callCount); {maintain global call counter}
    case curAction of

      pa_Idle:; {do nothing.  This MUST be the first switch in the CASE statement
      because other actions below it will reset to idle after processing.}

      pa_Stop:begin {stop = stop playing all sound}
        for loop:=0 to numVChannels-1 do VChannels[loop].active:=false;
        songIP:=false;
        patIP:=false;
        tickCount:=0;
        curAction:=pa_Idle;
      end;

      pa_PlayNote:begin
        if not noteIP then begin {if we're not already playing a note, start}
          noteIP:=true;
          {get current note and use it to set vchannel 0}
          tni:=mysong^.getnote * IBN;
          vChannels[0].noteInterval:=tni;
          vChannels[0].Frequency:=notesHz[tni];
          vChannels[0].active:=true;
          {start counting}
          tickCount:=0;
        end else begin
          {we're already playing; time to stop?}
          inc(tickCount);
          if tickCount>=noteDuration then begin
            noteIP:=false;
            curAction:=pa_Stop;
          end;
        end;
      end;

    end; {case}
    inHandler:=false;
  end;
end;

{MTV1 (MONOTONE file format v1) starts here----}

Constructor TMTV1Player.Init;
const
  sinPeriod=1;
var
  b:byte;
begin
  Inherited Init(theSong);

  {Initialize the vibrato table.  This is done here because different file
  formats may have different ways of interpreting vibrato; MONOTONE uses
  intervals between notes, but ProTracker uses frequency steps, so any
  file-format-specific precalcs need their own init section.}
  for b:=0 to MTV1VibTableSize-1 do begin
    VibTable[b] := round(
      MTV1VibTableDepth * Sin(b * Pi / MTV1VibTableSize * (sinPeriod*2))
    );
  end;
end;

Procedure TMTV1Player.CalcAllChannels;
{The most intensive part of playing a song is the pattern.  This is
handled here so that it can be hand-tuned to the song file format
for maximum efficiency.

Currently this is not optimized.  100% ideal would be an assembler routine
that maintains a source pointer to a row of song data and destination
pointers to vchannel and vdata.}
const
  inHandler:boolean=false;
  {these are here to handle Protracker compatibility quirks}
  ManualPatBreak:boolean=false;
  ManualPatJump:boolean=false;
  {end PT quirks}

var
  pVChan:PChannel; {operating location of channel data}

  Procedure UpdateNotesPerRow;
  {This is executed **ONCE** per row, on tick 0, and unpacks the note and
  effect data.  It also sets the virtual channel frequencies/intervals, since
  this is also done only once per row and keeping it here saves a CALL.}
  const
    {packed effect translation table}
    effDataToVisual:array[0..7] of byte=
    ($0,$1,$2,$3,$4,$b,$d,$f);
  var
    chloop:byte;
    temp:TPEVar; {For getting around excessive pointer operations in
    in-line asm.  Secondary but equally useful purpose is to have processing
    data local to the routine so that OFFSETs are generated by the compiler.}
    curCell:^word; {^word is the size of a TMTSong note/effect cell}
  begin
    tickCount:=0;
    curCell:=MySong^.GetCurRowPtr;
    {Unpack and fill housekeeping vars with note and effect data.  This
    duplicates functionality in TMTSong but that is the whole point of
    this system -- each TPlayer descendant is custom-tailored to the file
    format they support so that the player engine can run as fast as possible.}
    {$IFDEF CGA_PROFILE} asm MOV AL,tBlue; MOV DX,03D9h; OUT DX,AL; end; {$ENDIF}
    for chloop:=0 to numVChannels-1 do begin
      {curCell already pointing at our desired note/effect}
      {Unpack note and effect data from current cell}
      asm
        les di,curCell
        mov ax,es:[di]
        {unpack note}
        shr ax,1
        mov temp.note,ah
        {unpack effects}
        rcl ax,1                   {restore back to normal}
        and ah,00000001b           {ax= 0000000e eedddddd}
        {if ax = 0, we can skip the effect unpacking entirely}
        cmp ax,0
        jne @unpackeffects
        mov temp.effectraw,ax
        mov temp.effect,ah
        mov temp.parm1,al {effect 0 is 0xy so we need to fill both x and y}
        mov temp.parm2,al
        jmp @done
@unpackeffects:
        shl ax,1                   {ax= 000000ee edddddd0}
        shl ax,1                   {ax= 00000eee dddddd00}
        shr al,1                   {ax= 00000eee 0dddddd0}
        shr al,1                   {ax= 00000eee 00dddddd}
        {perform data-to-userfriendly translation}
        mov bx,offset effDataToVisual
        add bl,ah
        mov ah,[bx]
        {store "raw" data to aid in short-circuiting processing}
        mov temp.effectraw,ax
        {store translated effect}
        mov temp.effect,ah
        {assume combined data and store in parm1}
        mov temp.parm1,al
        {is effect 0 or 4? If so, "xy" effect; we need to unpack parm data}
        cmp ah,0                 {is it an effect that needs unpacking?}
        je @unpack               {if so, do it}
        cmp ah,4                 {is it an effect that needs unpacking?}
        jne @done                {if not (last comparison), we're done}
@unpack:
        mov ah,al                {ax=00111222 00111222}
        shr ah,1                 {ax=00011122 00111222}
        shr ah,1                 {ax=00001112 00111222}
        shr ah,1                 {ax=00000111 00111222}
        and al,00000111b         {ax=00000111 00000222}
        mov temp.parm1,ah
        mov temp.parm2,al
@done:
      end;
      {fill housekeeping data -- now that we have what we want, we can go
      screwing around with location data for future rows/orders.}
      {$IFDEF CGA_PROFILE} asm MOV AL,tWhite; MOV DX,03D9h; OUT DX,AL; end; {$ENDIF}
      with VData[chloop] do begin {this optimizes all but one MUL out of this block}
        note:=temp.note;
        effectraw:=temp.effectraw;
        effect:=temp.effect;
        parm1:=temp.parm1;
        parm2:=temp.parm2;
      end;
      {$IFDEF CGA_PROFILE} asm MOV AL,tBlack; MOV DX,03D9h; OUT DX,AL; end; {$ENDIF}
      inc(word(curCell),2); {move to next cell in prep for next track}
    end;
    {$IFDEF CGA_PROFILE} asm MOV AL,tGreen; MOV DX,03D9h; OUT DX,AL; end; {$ENDIF}

    {process notes}
    for chloop:=0 to numVChannels-1 do begin
      with VChannels[chloop] do begin {WITH statements force the compiler to}
        with VData[chloop] do begin   {optimize scope -- keep this in mind  }
          if note=noteEnd             {if you're porting this code and can't}
            then active:=false        {seem to find where a variable is.    }
            else if (note in validNoteRange) and (effect <> $3) {check for 3 to prevent porta data from changing frequency}
              then begin
                {set virtual channel data}
                active:=true;
                noteInterval:=note*IBN;
                Frequency:=notesHz[noteInterval];
                lastNotePlayed:=note; {housekeeping: Needed for slide-to-note}
                vibIndex:=0;          {housekeeping: If setting a new note, vibrato permuation should reset as well}
              end;
        end; {with VData}
      end; {with VChannels}
    end;

    {$IFDEF CGA_PROFILE} asm MOV AL,tRed; MOV DX,03D9h; OUT DX,AL; end; {$ENDIF}
    {handle "tick 0" effects}
    ManualPatBreak:=false; ManualPatJump:=false;
    for chloop:=0 to numVChannels-1 do begin

      {WITH statements force my compiler to optimize scope -- keep this in
      mind if you are porting this code and can't find where a variable is
      coming from!}
      with VData[chloop] do begin
      with VChannels[chloop] do begin
      with MySong^ do begin

      if effectraw<>0 then begin {short-circuit effect processing if we have nothing to do}
        case effect of
          $3:begin {3 	Tone Portamento 3xx : up/down speed}
            if note in validNoteRange then portaStophz:=notesHz[note*IBN]; {if note data <> 0, set the stop frequency}
            if parm1 <> 0 then portaDelta:=parm1; {if param <> 0, use it to set delta}
          end;
          $4:begin {4 	Vibrato 4xy : x-speed, y-depth}
            if parm1 <> 0 then vibSpeed:=parm1;
            if parm2 <> 0 then vibDepth:=parm2;
            {Protracker says to reset the vibrato index on tick 0.
            I think that's utterly moronic (the vibrato won't be uniform!)
            so we're not doing it here.  Instead, we'll do it when a new note
            is set because it makes sense to do it there.
            We advance the pointer here to keep vibrato consistent.}
            inc(vibIndex,vibSpeed); vibIndex:=vibIndex AND (MTV1VibTableSize-1);
          end;
          $b:begin {B   Position Jump Bxx : songposition}
            currentOrder:=parm1;
            currentLoc.Row:=-1; {will get inc'd later}
            if (currentOrder > numOrders) then CurrentOrder:=0;
            ManualPatJump:=true;
            {reposition pattern based on the above calcs}
            currentLoc.pattern:=Orders[currentOrder];
          end;
          $d:begin {D   Pattern Break Dxx : break position in next patt}
            currentLoc.Row:=parm1 - 1; {-1 because will be inc'd later}
            if (currentLoc.row >= maxrows) then currentLoc.Row := -1;
            if not manualPatBreak and not manualPatJump then inc(currentOrder);
            if (currentOrder > numOrders) then CurrentOrder:=0;
            ManualPatBreak:=true;
            {reposition pattern based on the above calcs, but check to make
            sure we don't jump into undefined territory}
            if (Orders[currentOrder] <> $FF) then currentLoc.pattern:=Orders[currentOrder];
          end;
          $f:begin {F   Set Speed Fxx : speed (00-1F)}
            Tempo:=parm1;
          end;
        end;
      end;

      end; {with VData[chloop]}
      end; {with VChannels[chloop]}
      end; {with MySong^}

    end;
    {$IFDEF CGA_PROFILE} asm MOV AL,tCyan; MOV DX,03D9h; OUT DX,AL; end; {$ENDIF}
  end;

  Procedure UpdateEffectsPerTick;
  {This exists **only** to process **NON-Tick-0** effects.  Tick 0
  effects are handled in UpdateNotesPerRow}
  const
    MinHz=20+MTV1MaxParmxx; {20 is lowest practical value; 31 is highest parameter value MTV1 file format can store}
    MaxHz=65535-MTV1MaxParmxx;
  var
    chloop:byte;
  begin
    {$IFDEF CGA_PROFILE} asm MOV AL,tYellow; MOV DX,03D9h; OUT DX,AL; end; {$ENDIF}
    for chloop:=0 to numVChannels-1 do begin

      {WITH statements force my compiler to optimize scope -- keep this in
      mind if you are porting this code and can't find where a variable is
      coming from!}
      with VData[chloop] do begin
      with VChannels[chloop] do begin

      {short-circuit effect processing if we have nothing}
      if effectraw<>0 then begin {ie. effect not arpeggio with parms x or y}
        case effect of
          $0:begin {0   Normal play or Arpeggio 0xy : x-first halfnote add,y-second}
            case (tickcount mod 3) of
              0:noteInterval:=(lastNotePlayed)*IBN;
              1:noteInterval:=(lastNotePlayed+parm1)*IBN;
              2:noteInterval:=(lastNotePlayed+parm2)*IBN;
            end; {case}
            Frequency:=notesHz[noteInterval];
          end;
          $1:begin {1   Slide Up 1xx : upspeed}
            if Frequency < MaxHz then inc(Frequency,parm1);
          end;
          $2:begin {2   Slide Down 2xx : downspeed}
            if Frequency > MinHz then dec(Frequency,parm1);
          end;
          $3:begin {3   Tone Portamento 3xx : up/down speed}
            if Frequency < portaStopHz then begin {are we under the target?}
              inc(Frequency,portaDelta);          {if so, slide up}
              if Frequency > portaStopHz          {did we overshoot it?}
                then Frequency := portaStopHz;    {equalize it}
            end;
            if Frequency > portaStopHz then begin {are we over the target?}
              dec(Frequency,portaDelta);          {if so, slide down}
              if Frequency < portaStopHz          {did we overshoot it?}
                then Frequency := portaStopHz;    {equalize it}
            end;
          end;
          $4:begin {4 	Vibrato 4xy : x-speed, y-depth}
            {Protracker Vibrato works by adding hz to/from the frequency.
            That doesn't scale (no pun intended) when your C-7 is 4Khz and
            +/- 16Hz is the value because it wouldn't be noticable.  Our vibrato
            uses intervals between notes instead of +-Hz.}
            Frequency:=notesHz[noteInterval+(((vibTable[vibIndex]) * vibDepth) div MTV1VibTableDepth)];
            {move index forward and wrap around if necessary}
            inc(vibIndex,vibSpeed); vibIndex:=vibIndex AND (MTV1VibTableSize-1);
          end;
        end; {case}
      end;

      end; {with}
      end; {with}

    end;
    {$IFDEF CGA_PROFILE} asm MOV AL,tWhite; MOV DX,03D9h; OUT DX,AL; end; {$ENDIF}
  end;

var
  {added for debugging, should remove someday:}
  b1,b2:byte;

begin
  {$IFDEF CGA_PROFILE} asm MOV AL,tBrown; MOV DX,03D9h; OUT DX,AL; end; {$ENDIF}
  Inherited CalcAllChannels;
  {$IFDEF CGA_PROFILE} asm MOV AL,tMagenta; MOV DX,03D9h; OUT DX,AL; end; {$ENDIF}

  if not inHandler then begin
    inHandler:=true;
    case curAction of
      pa_PlayPattern:begin
        if not patIP then begin {if not currently playing, time to start}
          patIP:=true; {set PatternPlayingInProgress flag to true}
          mysong^.currentLoc.row:=0; {move to top of pattern, bypassing the method because we know we're passing valid data}
          pVChan:=@VChannels; {point to start of virtual channel array}
          tickCount:=Tempo; {set our tick count to our current tempo}
        end;

        inc(tickCount);
        if tickCount>=Tempo then begin
          {time for a new row of song and effect data}
          tickCount:=0;
          if MySong^.CurrentLoc.Row >= maxRows then begin {end of pattern?}
            if songIP then begin {if song is in progress, handle order movement}
              inc(MySong^.CurrentOrder); {point to next pattern in order list}
              if MySong^.Orders[MySong^.CurrentOrder]=$ff {end of song!} then begin
                dec(MySong^.CurrentOrder);
                songIP:=false;
                curAction:=pa_Stop;
              end;
              MySong^.currentLoc.pattern:=MySong^.Orders[MySong^.currentOrder];
            end;
            MySong^.CurrentLoc.Row:=0;  {fix row to be valid again}
          end;
          UpdateNotesPerRow;
          inc(MySong^.currentLoc.Row);
        end else begin
          UpdateEffectsPerTick;
        end;

        {A D00 on the last pattern can send us into neverland, so let's do
        an additional check if we're at the end of the song and handle it.
        FF in the order list means End Of Song}
        if MySong^.Orders[MySong^.CurrentOrder]=$ff then begin
        {b1:=MySong^.CurrentOrder;
        b2:=MySong^.Orders[b1];
        if b2=$ff then begin}
          dec(MySong^.CurrentOrder);
          songIP:=false;
          curAction:=pa_Stop;
        end;

      end; {case pa_PlayPattern}

      pa_PlaySong:begin
        SongIP:=true; {signal "song-playing" mode for the engine}
        MySong^.currentOrder:=0;
        MySong^.currentLoc.pattern:=MySong^.Orders[0];
        MySong^.currentLoc.row:=0;
        tickCount:=Tempo;
        curAction:=pa_PlayPattern; {start playing, and don't come back here}
      end;
    end; {case}
  end;
  inHandler:=false;
  {$IFDEF CGA_PROFILE} asm MOV AL,tBlack; MOV DX,03D9h; OUT DX,AL; end; {$ENDIF}
end;

end.
