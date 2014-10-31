{$I MT_DEFS.INC}

unit mt_song;
{song manipulation; note input/output routines}

{
The abstract song object is used to define most of the basic methods of
most typical tracker song formats, like generic I/O routines.  It is up
to descendant objects to implement the details of specific file formats.

The song object is not event-based like MIDI.  That is not the purpose
of this exercise; if you want MIDI, use a MIDI sequencer.  The whole
point of this program is to define a low-resource song data format for
specialized applications (games, demos) where speed is critical.

One of the criteria of this particular tracker is to support a song
format that takes up very little space in memory while remaining
uncompressed and easy to process.  The data structure chosen was
slightly influenced by Amiga trackers, but was ultimately designed so
that it could be processed quickly by an 808x processor.

Programming considerations:
- Because the playback interrupt routine and the get/set routines use the
same location variables,
  "set" routines MUST be atomic and
  "get" routines MAY be atomic

Apology:  There's a lot of x86 assembler in the v1 version of the song file
format because the fields are all packed.  Moving forward, I'll write
portable code first and optimize later...
}

interface

uses
  objects,
  mt_glob;

const
  numOrders=256;

type
  LocationType=record
    Pattern:byte;
    Row:shortint; {required for player routine to 100% match protracker B and D effects}
    Track:byte;
  end;
  orderType=array[0..numOrders-1] of byte;

  commentType=string[40];

  {
  TSong is responsible for entering and manipulating the song.  Adding
  notes and effects, as well as validating the input, are methods.
  The only data a song object knows about are notes, which are modeled
  after a piano keyboard with 88 keys, with value 1=A0 and value 88=C8.

  This is an abstract object to define capabilities only; every unique
  song type will need a descendant (look at the bright side, this means
  loading .MODs, MCS, Pianoman, BASIC 3-voice, etc. might be possible someday ;-).

  Only song format planned for first release is MONOTONE format version 1,
  the definition of which follows the abstract object definition below.
  }
  PSong=^TSong;
  TSong=object(TObject)
    currentLoc:LocationType; {song object is responsible for positioning}
    currentOrder:integer; {which order we're currently playing/selected; integer because playengine can set to -1 for inc+}
    Orders:Ordertype;  {which patterns to play, in order.  FF=stop playing}
    numTracks,
    numPatterns:byte;
    dataSize:word; {size in bytes of raw song data portion}
    sizeOfPattern:word;
    (* this was turned into a constant specific for each descendant because
    it's always a power of two; we miss out on a major optimization
    by keeping it a memory variable, so >poof< it's a constant
    sizeOfNoteEvent:byte; {numbytes of one "cell"'s worth of data (note, effects, vol, instru)}
    *)
    maxPattern:byte;
    Modified:boolean; {song has been altered since last save}
    Allocated:boolean; {song data is already allocated}
    filename:str80;   {song object should own it's own filename, yes?}

    constructor Init(numTrk:byte);
    destructor done; virtual;
    Function Load(fname:string):boolean; virtual;
    Function Save(fname:string):boolean; virtual;
    Procedure SetTitle(newtitle:commenttype); virtual;
    Procedure SetComment(newtitle:commenttype); virtual;

    {song is responsible for keeping track of locations! all perform bounds checking}
    {absolute movement:}
    Procedure MoveToPattern(newpattern:byte);
    Procedure MoveToTrack(newtrack:byte);
    Procedure MoveToRow(newrow:byte);
    procedure MoveTo(newpattern,newtrack,newrow:byte);
    {relative movement:}
    Procedure MovePattern(amount:shortint);
    Procedure MoveTrack(amount:shortint);
    Procedure MoveRow(amount:shortint);
    Procedure MoveOrder(amount:shortint);

    function GetCurRowPtr:pointer; virtual; {returns pointer to data that
    represents the current row, N tracks wide, starting at track 0.
    This (and sizeOfNoteEvent) is necessary for the player object to pick up
    the start of the data to process; because song structure could
    change in the future (ie. more data than will fit into a single 64K
    segment, etc.)}

    {the get/set procedures act on the current pattern/row/track data}
    {"set" procedures perform validity checking}
    procedure SetNote(note:byte); virtual; {uses cur* vars to set}
    function  GetNote:byte; virtual; {uses cur* vars to locate}
    function  GetNoteAt(track,row:byte):byte; {uses absolute track*row of
    current pattern without disturbing current location; useful for pattern display}
    function  GetNoteAbsolute(pattern,track,row:byte):byte; {useful for pattern manipulation}
    procedure SetEffect(effect, parm1, parm2:byte); virtual;
    function  GetEffect:word; virtual; {uses cur* vars; effect=hibyte (FF00),
    data=lobyte (00FF) as 0xxx0yyy for xy effects and 00xxxxxx for xx effects}
    function  GetEffectAt(track,row:byte):word; {uses current pattern, used for pattern display}
    function  GetEffectAbsolute(pattern,track,row:byte):word; {useful for pattern manipulation}
    procedure SetVolume(vol:byte); virtual; {for future use}
    function  GetVolume:byte; virtual; {for future use}
    procedure SetInstrument(inst:byte); virtual; {for future use}
    function  GetInstrument:byte; virtual; {for future use}

    {track/row manipulation, also uses current pat/row/track data}
    procedure InsertRow(dest:LocationType); virtual;
    procedure DeleteRow(dest:LocationType); virtual;
    procedure CopyTrack(source,dest:LocationType); virtual;
    procedure SwapTrack(source,dest:LocationType); virtual;
    procedure EraseTrack(dest:LocationType); virtual;
    procedure CopyPattern(source,dest:LocationType); virtual;
  end;

  cookieType=string[8];

  {Note that the file header duplicates some song object info, but does
  NOT replace it!  It is only used for loading and saving.}
  pMTSongFileHeader=^TMTSongFileHeader;
  TMTSongFileHeader=record
    {magic cookies and headers}
    FileID:cookieType; {if != 'MONOTONE' then not an MT file!}
    Title:commentType;
    Comment:commentType;
    Version:byte;
    totalPatterns:byte;
    totalTracks:byte;
    CellSize:byte; {these three along with 64 rows per pattern tell us how much to load}
    PatternOrder:orderType; {FF = end of song so fill with FFs}
  end;

  {
  MTSong is a song object using this format:

  AH       AL
  FEDCBA98 76543210
  nnnnnnne eedddddd
  -------- --------
  nnnnnnn           =note number (0-127)
         e ee       =effect (0-7) (see below)
             111222 =effect data (0-63, or 0-7,0-7)

  Note that Intel architecture is little-endian so these bytes
  are swapped when stored on disk.

  Effects supported:
  actual | presented to user as:
  0      | 0  Normal play or Arpeggio 0xy : x-first halfnote add,y-second
  1      | 1 	Slide Up 1xx : upspeed
  2      | 2 	Slide Down 2xx : downspeed
  3      | 3 	Tone Portamento 3xx : up/down speed
  4      | 4 	Vibrato 4xy : x-speed, y-depth
  5      | B 	Position Jump Bxx : songposition
  6      | D 	Pattern Break Dxx : break position in next patt
  7      | F 	Set Speed Fxx : speed (00-1F) / tempo (20-FF)
  }

  PMTSong=^TMTSong;
  TMTSong=object(TSong)
    fileHeader:PMTSongFileHeader;
    Data:pointer;

    Constructor Init(numTrk:byte);
    Destructor Done; virtual;
    Function Load(fname:string):boolean; virtual;
    Function Save(fname:string):boolean; virtual;
    Function GetCurRowPtr:pointer; virtual; {returns pointer to current row}
    Function GetCurNotePtr:pointer; virtual; {returns pointer to current note cell}
    Procedure SetTitle(newTitle:commenttype); virtual;
    Procedure SetComment(newComment:commenttype); virtual;
    procedure SetNote(note:byte); virtual; {uses cur* vars to set}
    function  GetNote:byte; virtual; {uses cur* vars to locate}
    procedure SetEffect(effect, parm1, parm2:byte); virtual;
    function  GetEffect:word; virtual;

    private
    Procedure AllocSongData;
  end;

implementation

uses
  strings,
  support;

constructor TSong.Init;
begin
  Inherited Init;
  {put extra stuff here?}
end;

Destructor TSong.Done;
begin
  {do housecleaning here?}
  Inherited Done;
end;

Procedure TSong.SetTitle;
begin
  Abstract;
end;

Procedure TSong.SetComment;
begin
  Abstract;
end;

Function TSong.Load;
begin
  Abstract;
end;

Function TSong.Save;
begin
  Abstract;
end;

procedure TSong.MoveToPattern;
{performs bounds checking and expands numpatterns when necessary; numpatterns
is used when saving a file (only save what's been visited)}
begin
  if newPattern<maxPattern
    then CurrentLoc.Pattern:=newPattern;
  if newPattern>=numPatterns
    then numPatterns:=newPattern+1;
end;

procedure TSong.MoveToTrack;
begin
  if newTrack<numTracks
    then CurrentLoc.Track:=newTrack;
end;

procedure TSong.MoveToRow;
begin
  if newRow<maxRows
    then CurrentLoc.Row:=newRow;
end;

Procedure TSong.MovePattern;
var
  foo:integer;

begin
  foo:=CurrentLoc.Pattern + amount;
  if foo<0
    then foo:=0;
  if foo>=maxPattern
    then foo:=maxPattern;
  MoveToPattern(foo);
end;

Procedure TSong.MoveTrack;
var
  foo:shortint;

begin
  foo:=CurrentLoc.Track + amount;
  if foo<0 then foo:=numTracks-1;
  if foo>=numTracks then foo:=0;
  MoveToTrack(foo);
end;

Procedure TSong.MoveRow;
var
  foo:shortint;

begin
  foo:=CurrentLoc.Row + amount;
  if foo<0
    then foo:=0;
  if foo>=maxRows
    then foo:=maxRows-1;
  MoveToRow(foo);
end;

Procedure TSong.MoveOrder;
var
  foo:integer;

begin
  foo:=CurrentOrder + amount;
  if foo<0
    then foo:=0;
  if foo>=numOrders-1
    then foo:=numOrders-1;
  CurrentOrder:=foo;
end;

procedure TSong.MoveTo;
begin
  MoveToPattern(newPattern);
  MoveToTrack(newTrack);
  MoveToRow(newRow);
end;

function TSong.GetCurRowPtr;
begin
  Abstract;
end;

procedure TSong.SetNote;
begin
  Abstract;
end;

function TSong.GetNote;
begin
  Abstract;
end;

(* This is the basic idea, but we are going to rewrite this for speed, tuned
to the Turbo Pascal 7.0 compiler.  See immediately below for that routine.
BTW, a similar optimization is made to GetEffectAt for the same reasons.
function TSong.GetNoteAt;
var
  temploc:LocationType;
begin
  temploc:=CurrentLoc;
  MoveToTrack(track);
  MoveToRow(row);
  GetNoteAt:=GetNote;
  CurrentLoc:=temploc;
end; *)

function TSong.GetNoteAt;
var
  temptrack,temprow:shortint; {using these force the generation of moving a
  single byte, as opposed to calling a generic move() library routine}
begin
  temptrack:=CurrentLoc.track; temprow:=CurrentLoc.row;
  {we need speed here, so we're going to trust the user (eep!)}
  CurrentLoc.Track:=Track; CurrentLoc.Row:=Row;
  GetNoteAt:=GetNote;
  CurrentLoc.Track:=temptrack; CurrentLoc.Row:=temprow;
end;

function TSong.GetEffectAt;
var
  temptrack,temprow:shortint;
begin
  temptrack:=CurrentLoc.track; temprow:=CurrentLoc.row;
  {we need speed here, so we're going to trust the user (eep!)}
  CurrentLoc.Track:=Track; CurrentLoc.Row:=Row;
  GetEffectAt:=GetEffect;
  CurrentLoc.Track:=temptrack; CurrentLoc.Row:=temprow;
end;

function TSong.GetNoteAbsolute;
var
  temploc:LocationType;
begin
  temploc:=CurrentLoc;
  MoveToPattern(pattern);
  MoveToTrack(track);
  MoveToRow(row);
  GetNoteAbsolute:=GetNote;
  CurrentLoc:=temploc;
end;

function TSong.GetEffectAbsolute;
var
  temploc:LocationType;
begin
  temploc:=CurrentLoc;
  MoveToPattern(pattern);
  MoveToTrack(track);
  MoveToRow(row);
  GetEffectAbsolute:=GetEffect;
  CurrentLoc:=temploc;
end;

procedure TSong.SetEffect;
begin
  Abstract;
end;

function TSong.GetEffect;
begin
  Abstract;
end;

procedure TSong.SetVolume;
begin
  Abstract;
end;

function TSong.GetVolume;
begin
  Abstract;
end;

procedure TSong.SetInstrument;
begin
  Abstract;
end;

function TSong.GetInstrument;
begin
  Abstract;
end;

procedure TSong.InsertRow;
begin
  Abstract;
end;

procedure TSong.DeleteRow;
begin
  Abstract;
end;

procedure TSong.CopyTrack;
begin
  Abstract;
end;

procedure TSong.SwapTrack;
begin
  Abstract;
end;

procedure TSong.EraseTrack;
begin
  Abstract;
end;

procedure TSong.CopyPattern;
begin
  Abstract;
end;

{--------TMTSong V1--------}

const
  MTFileID='MONOTONE';
  MTV1SongVer=1;
  MTV1SizeOfNoteEvent=2; {fixed size of each track/row "cell" in
  an MT ver. 1 song so we can optimize some MULs out}

Procedure TMTSong.AllocSongData;
const
  safetyMargin=(80*25*2) * 2;
var
  tl:longint;
  tw:word;

begin
  sizeOfPattern:=numTracks*maxRows*MTV1sizeOfNoteEvent;
  {allocate enough ram to compose in.  This is the size of whatever is left
  (usually a 64K block on machines with 256K or more) minus header size,
  divided by number of patterns.}
  {first, see how much memory we have available, minus a reasonable amount for
  the file header and tracker usage (one 80x25 screen save plus another for safety/unknowns)}
  tl:=maxavail-(safetyMargin-sizeof(fileHeader^));
  {if we have a negative number, we don't have enough memory :-( }
  if tl<0 then fatalerror(16,strpas(es_NotEnoughMemory));
  {if we have too much :-) limit to the maximum block size allowed under our heap manager}
  if tl > (65536-16) then tl:=(65536-16);
  {determine how many patterns we can have}
  tw:=tl div sizeOfPattern;
  {check for size and limit to order threshold if necessary}
  if tw>254 then tw:=254; {last order MUST be $ff so we know when to stop playing :-) }
  maxPattern:=tw;
  dec(maxPattern); {dec by 1 because we may need a "scratch" pattern for manipulation purposes}
  DataSize:=sizeOfPattern*maxPattern;
  getmem(data,DataSize);
  fillchar(data^,datasize,0);
  Allocated:=true;
end;

Constructor TMTSong.Init;
var
  foo:word;
begin
  Inherited Init(numTrk);

  allocated:=false;
  new(fileHeader);
  fillchar(fileHeader^,sizeof(fileHeader^),0);
  {put default values into the header}
  With fileHeader^ do begin
    FileID:=MTFileID;
    Title:='';
    Comment:='';
    Version:=MTV1SongVer;
    {fill orders with FF as that is the EOS marker}
    fillchar(PatternOrder,sizeof(PatternOrder),$ff);
    totalPatterns:=1;
    totalTracks:=numTrk;
    CellSize:=2;
  end;

  {header is done so now we init on song object housekeeping}
  numTracks:=numTrk;
  numPatterns:=1;
  (* sizeOfNoteEvent:=2; {size in bytes of note+effects+etc.} now a const *)
  fillchar(Orders,sizeof(Orders),$ff);

  AllocSongData; {uses numTracks,maxRows,sizeOfNoteEvent}
end;

Destructor TMTSong.Done;
begin
  {do housecleaning here?}
  if allocated then freemem(data,DataSize);
  dispose(fileHeader);

  Inherited Done;
end;

Function TMTSong.Load;
var
  f:PDosStream;
  dsize:word;
begin
  new(f,init(fname,stOpenRead));
  f^.read(fileheader^,sizeof(fileheader^));
  if f^.status <> stOK then begin
    dispose(f);
    Load:=false;
    exit;
  end;
  {deallocate previous song data block}
  if allocated then begin
    freemem(data,datasize);
    allocated:=false;
  end;
  {allocate new block to hold song and load bulk of song data}
  numTracks:=fileHeader^.totalTracks;
  numPatterns:=fileHeader^.totalPatterns;
  Orders:=fileHeader^.PatternOrder;
  (* sizeOfNoteEvent:=fileHeader^.cellsize; now a const *)
  AllocSongData;
  {load only what is necessary from disk:}
  dsize:=numPatterns*sizeOfPattern;
  f^.read(data^,dsize);
  if f^.status <> stOK then begin
    dispose(f);
    Load:=false;
    exit;
  end;
  dispose(f,done);
  {reposition to beginning of song}
  currentLoc.Pattern:=0; currentLoc.Track:=0; currentLoc.Row:=0;
  Load:=true;
end;

Function TMTSong.Save;
var
  f:PDosStream;
  s:word;
begin
  new(f,init(fname,stCreate));
  fileHeader^.totalPatterns:=numPatterns;
  fileHeader^.totalTracks:=numTracks;
  fileHeader^.PatternOrder:=Orders;
  f^.write(fileHeader^,sizeof(fileHeader^));
  {calculate the size of data to save, to save on disk space}
  s:=sizeOfPattern*numPatterns;
  f^.write(data^,s);
  if f^.status <> stOK then begin
    dispose(f);
    Save:=false;
    exit;
  end;
  dispose(f,done);
  Save:=true;
end;

Function TMTSong.GetCurRowPtr;
var
  p:pointer;
  curloc:LocationType;
begin
  p:=data;
  asm pushf; cli end; {nothing must alter the location vars while we're calculating}
  curloc:=CurrentLoc;
  asm popf end; {we got what we want, interrupts can continue}
  {advance to correct pattern}
  inc(word(p),sizeOfPattern*curloc.Pattern);
  {advance to correct row}
  inc(word(p),(MTV1sizeOfNoteEvent*numTracks)*curloc.Row);
  GetCurRowPtr:=p;
end;

Function TMTSong.GetCurNotePtr;
var
  p:pointer;
  curLoc:locationtype;
begin
  (* {point to current row} *)
  (* p:=GetCurRowPtr; *)
  (* It's too costly to be CALLing all the time! We have inlined instead. *)
  p:=data;
  asm pushf; cli end; {nothing must alter the location vars while we're calculating}
  curLoc:=CurrentLoc;
  asm popf end; {we got what we want, interrupts can continue}
(*
  {advance to correct pattern}
  inc(word(p),sizeOfPattern*curLoc.Pattern);
  {advance to correct row}
  inc(word(p),(MTV1sizeOfNoteEvent*numTracks)*curLoc.Row);
  {advance to correct track of current row}
  inc(word(p),(MTV1sizeOfNoteEvent*curLoc.Track));
*)
(*
  inc(word(p),
    (sizeOfPattern*curLoc.Pattern)+
    ((MTV1sizeOfNoteEvent*numTracks)*curLoc.Row)+
    (MTV1sizeOfNoteEvent*curLoc.Track);
*)
  inc(word(p),
    (sizeOfPattern*curLoc.Pattern)+
    (MTV1sizeOfNoteEvent*((numTracks*curLoc.Row)+curLoc.Track))
    );
  GetCurNotePtr:=p;
end;

Procedure TMTSong.SetNote;
var
  wp:pointer;
  tn:byte;
begin
  wp:=GetCurNotePtr;
  tn:=note;
  asm
    les di,wp
    mov bx,es:[di]
    and bh,00000001b           {bx= 0000000e eedddddd (prev. note data)}
    mov ah,tn
    shl ah,1
    xor al,al                  {ax= nnnnnnn0 00000000}
    or  bx,ax                  {bx= nnnnnnne eedddddd}
    mov es:[di],bx
  end;
end;

Procedure TMTSong.SetEffect; {effect,parm1,parm2:byte}
{Validates data *before* storing, so playback routine doesn't have to check.
This slows down the tracker but speeds up playback, which is what we care about.}
const
  {some translation tables to present common interface to user when dealing
  with effects.  We only support 3-bits' worth of effects at the moment, but
  the userspace expects Protracker commands which are 4-bit.  We translate.}
  effVisualToData:array[0..15] of byte=
  ($0,$1,$2,$3,$4,$0,$0,$0,$0,$0,$0,$5,$0,$6,$0,$7);

var
  wp:pointer;
  te,tp1,tp2,tc:byte; {we copy into local temporary variables because doing
  assembler with OOP is a major pain in the ass}
begin
  wp:=GetCurNotePtr;
  (*te:=effVisualToData[effect]; {translate what user gave us into actual data format}*)
  te:=effect; {translate what user gave us below in asm}
  tp1:=parm1;
  tp2:=parm2;

  {effects with xy data are packed the same as dd data but handled differently}
  if te in [$0,$4] then begin
    {validate data if necessary}
    asm
      and tp1,00000111b  {tp1=00000xxx}
      and tp2,00000111b  {tp2=00000yyy}
    end;
    {store it in packed format}
    asm
      mov bx,offset effVisualToData
      mov al,te                  {translates the user-friendly command into}
      xlat                       {what fits into our file format}
      les di,wp                  {to put an effect, we have to grab the old cell first}
      mov bx,es:[di]             {bx= nnnnnnne ee111222}
      and bx,1111111000000000b   {bx= nnnnnnn0 00000000}
      mov ah,al                  {ax= 00000eee 00000eee}
      mov al,tp1                 {ax= 00000eee 00000111}
      shl al,1                   {ax= 00000eee 00001110}
      shl al,1                   {ax= 00000eee 00011100}
      shl al,1                   {ax= 00000eee 00111000}
      or  al,tp2                 {ax= 00000eee 00111222}
      shl al,1                   {ax= 00000eee 01112220}
      shl al,1                   {ax= 00000eee 11122200}
      shr ax,1                   {ax= 000000ee e1112220}
      shr ax,1                   {ax= 0000000e ee111222}
      or  bx,ax                  {bx= nnnnnnne ee111222}
      mov es:[di],bx
    end;
  end;

  {if dd effect, treat it as a 6-bit number.  For example, F is set tempo,
  so effect F with params 1 and 1 is really F with $11 as the data.}
  if te in [$1,$2,$3,$b,$d,$f] then begin
    {build 6-bit number out of params}
    asm
      mov ah,tp1
      mov al,tp2                {ax=????1111 ????2222}
      shl ah,1
      shl ah,1
      shl ah,1
      shl ah,1                  {ax=11110000 ????2222}
      and ax,0011000000001111b  {ax=00110000 00002222}
      or  al,ah                 {ax=00110000 00112222}
      mov tc,al
    end;
    {valid data if necessary}
    case te of
      $1:{Slide Up 1xx : upspeed};
      $2:{Slide Down 2xx : downspeed};
      $3:{Tone Portamento 3xx : up/down speed};
      $b:{Position Jump Bxx : songposition};
      $d:{Pattern Break Dxx : break to row xx in next patt};
      $f:begin {set speed Fxx}
        if tc=0 then tc:=1; {tempo of 0 is not valid so we make it 1}
      end;
    end; {case}

    {store it in packed format}
    asm
      mov bx,offset effVisualToData
      mov al,te
      xlat
      les di,wp
      mov bx,es:[di]             {bx= nnnnnnne eedddddd}
      and bx,1111111000000000b   {bx= nnnnnnn0 00000000}
      mov ah,al                  {ax= 00000eee 00000eee}
      mov al,tc                  {ax= 00000eee 00dddddd}
      shl al,1                   {ax= 00000eee 0dddddd0}
      shl al,1                   {ax= 00000eee dddddd00}
      shr ax,1                   {ax= 000000ee edddddd0}
      shr ax,1                   {ax= 0000000e eedddddd}
      or  bx,ax                  {bx= nnnnnnne eedddddd}
      mov es:[di],bx
    end;
  end;
end;

Function TMTSong.GetNote;
var
  wp:^word;
begin
  wp:=GetCurNotePtr;
  asm
    les di,wp
    mov ax,es:[di]
    shr ah,1
    mov @Result,ah
  end;
end;

Function TMTSong.GetEffect;
{returns:
  effect=hibyte (FF00)
  data=lobyte   (00FF) as:
    00xxxxxx for xx effects
    01110222 for xy effects}
const
  effDataToVisual:array[0..7] of byte=
  ($0,$1,$2,$3,$4,$b,$d,$f);
var
  wp:pointer;
  te:byte;
  td:byte;
begin
  wp:=GetCurNotePtr;
  asm
    les di,wp
    mov ax,es:[di]             {ax= nnnnnnne eedddddd}
    and ah,00000001b           {ax= 0000000e eedddddd}
    {if ax=0, then there's no effect or parms; short-circuit to the end}
    cmp ax,0
    je @deliver
    shl ax,1                   {ax= 000000ee edddddd0}
    shl ax,1                   {ax= 00000eee dddddd00}
    shr al,1                   {ax= 00000eee 0dddddd0}
    shr al,1                   {ax= 00000eee 00dddddd}
    {perform data-to-userfriendly translation}

    mov bx,offset effDataToVisual
    add bl,ah
    mov ah,[bx];

    {ah=effect, al=data}
    {is effect 0 or 4?  If so, it's an xy effect and the data portion
    needs massaging before we can deliver it to the user}
    cmp ah,0                 {is it an effect that needs massaging?}
    je @massage              {if so, do it}
    cmp ah,4                 {is it an effect that needs massaging?}
    jne @deliver             {if not (last comparison), deliver it}
  @massage:
    mov dh,ah                {save effect for later restoration}
    mov ah,al                {ax=00111222 00111222}
    shl ah,1                 {ax=01112220 00111222}
    and ax,0111000000000111b {ax=01110000 00000222}
    or  al,ah                {ax=01110000 01110222}
    mov ah,dh                {ax=00000eee 01110222}
  @deliver:
    mov @Result,ax
  end;
end;

Procedure TMTSong.SetTitle;
begin
  fileHeader^.Title:=newTitle;
end;

Procedure TMTSong.SetComment;
begin
  fileHeader^.Comment:=newComment;
end;

end.
