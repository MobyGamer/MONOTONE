{$I MT_DEFS.INC}

unit mt_scre;
{
Text screen output routines.

Basic concepts:

screenram = the location of visible screen RAM
screenbuf = the buffer we write to (can equal screenram);

Methods:

Show: Switches visible screen to that of the object.
Print: Writes text using current back/foreground attribute and location.
Update: Updates visible screen (not necessary in all configurations; if that
is the circumstance, then Update does nothing).  Call Update every time it
is *mandatory* that the user see the last Print; otherwise, the last Print is
not guaranteed to be visible.

Caveats:  Cannot mix and match screen object types, as it will bork the
global variable numScreens.  Pick one and stick with it.

ToDo:
  Replace SaveState and RestoreState with a real stack (ie. PushState
  and PopState)
}

interface

uses
  objects,
  mt_glob,
  m6845ctl;

const
  numScreens:byte=0; {used to keep track of whether or not external
  subsystems should be init'd or closed}

  {We're doing this here so that programs who want to use screens
  won't need to load M6845CTL just to get color defs}
  Black=tBlack;
  Blue=tBlue;
  Green=tGreen;
  Cyan=tCyan;
  Red=tRed;
  Magenta=tMagenta;
  Brown=tBrown;
  LightGray=tLightGray;
  DarkGray=tDarkGray;
  LightBlue=tLightBlue;
  LightGreen=tLightGreen;
  LightCyan=tLightCyan;
  LightRed=tLightRed;
  LightMagenta=tLightMagenta;
  Yellow=tYellow;
  White=tWhite;
  BlinkBit=128;

type
  boxtypes=(single,double,thickhor,thickver);
  boxstyle=record
    ul,ur,ll,lr,    {upper-left, upper-right, lower-left, lower-right}
    lj,mj,rj,tj,bj, {left junction, middle junction, right junction, top junction, bottom junction}
    hor,ver:char;   {horizontal and vertical}
  end;
  boxstyles=array[boxtypes] of boxstyle;

const
  BoxChars:boxstyles=(
  (ul:'Ú';ur:'¿';ll:'À';lr:'Ù';lj:'Ã';mj:'Å';rj:'´';tj:'Â';bj:'Á';hor:'Ä';ver:'³'), {single}
  (ul:'É';ur:'»';ll:'È';lr:'¼';lj:'Ì';mj:'Î';rj:'¹';tj:'Ë';bj:'Ê';hor:'Í';ver:'º'), {double}
  (ul:'Õ';ur:'¸';ll:'Ô';lr:'¾';lj:'Æ';mj:'Ø';rj:'µ';tj:'Ñ';bj:'Ï';hor:'Í';ver:'³'), {thickhor}
  (ul:'Ö';ur:'·';ll:'Ó';lr:'½';lj:'Ç';mj:'×';rj:'¶';tj:'Ò';bj:'Ð';hor:'Ä';ver:'º')  {thickver}
  );

type
  {Describes "state" of a screen that can be used for save/restore}
  ScreenState=record
    cursorsize:word;       {cursor size/shape}
    x,                     {X active location}
    y,                     {Y active location}
    backfore:byte;         {background/foreground color attribute byte}
    cursorFollows:boolean; {whether or not cursor moves after print}
    cursorVisible:boolean; {whether or not the cursor is visible or hidden}
  end;

  {"screen" object used to descend to actual screens in the tracker.
  Assumptions:
    - All descendants will use TFastWrite
    - Any hardware-specific method will be virtual and abstract}
  PScreen=^TScreen;
  TScreen=object(TObject)
    State:ScreenState;
    numcols,
    numrows:byte;         {total number of colums and rows}
    screensize,           {size in bytes of a screen buffer}
    scroffs:word;         {used for calcs and scroffs public for special effects}
    screenram,            {RAM is what is visible}
    screenbuf:pointer;    {BUF is where we write to (can equal RAM)}

    constructor Init(     {note: This assumes the video mode has already been set up!}
      screenseg:word;     {b800 or b000}
      xsize,ysize:byte    {size of our screen (typically 40,25 or 80,25)}
    );
    destructor Done; virtual;
    Procedure Clear(filler:byte); {clears the screen using the current attribute and specified filler}
    Procedure Show; virtual;    {Switches to screen or otherwise makes it visible}
    Procedure Update; virtual;  {updates visible screen (if using screen ram, this does nothing)}
    Procedure MoveTo(x,y:byte);
    Procedure MoveDown(newy:shortint); {helps when doing a lot of Prints}
    Procedure MoveOver(newx:shortint); {helps when doing a lot of Prints}
    Procedure SetBackC(b:byte); {set background color in attribute byte}
    Procedure SetForeC(f:byte); {set foreground color in attribute byte}
    Procedure AllColorsAvailable(enable:boolean); virtual; {if enabled, we have all 16 background colors}
    Procedure BlinkON;          {turns on blink bit}
    Procedure BlinkOFF;         {turns off blink bit}
    Procedure DrawBox(x1,y1,x2,y2:byte;style:boxtypes;titles:str80);
    Procedure PopUp(x1,y1,x2,y2:byte;s:str80); {saves screen, pops up a box with title and with cursor inside for a message}
    Procedure RemovePop;        {restores screen}
    Procedure Print(s:string);  {writes text at current coords with current attr}
    Procedure ReColor(x,y,size:word); {repaints colors only for len size at x,y (used for highlights)}
    Procedure ShowCursor; virtual; {make old cursor reappear, then move it to curx,cury}
    Procedure HideCursor; virtual;
    Procedure VisibleBell; virtual; {"flash" the screen or something}
    Procedure SaveState;    {preserves colors and cursor location}
    Procedure RestoreState; {these are separate from internal processes; provided for end-user purposes}

    private

    oldState,
    popState:ScreenState; {holds "state" of a window (x,y,colors, etc.)}
    popsaved:pointer;     {used for single popup}

    Procedure UpdateCursorLoc; virtual;
  end;

  PCGAScreen=^TCGAScreen;
  TCGAScreen=Object(TScreen)
  {CGA-specific descendant of TScreen.  Only uses real video memory for
  visible screens, and uses the MC6845 to change display address start
  and cursor shape.}
    vidpage:byte;
    constructor Init(screenseg:word;xsize,ysize:byte);
    destructor Done; virtual;
    Procedure Show; virtual;    {switches to screen or otherwise makes it visible}
    Procedure Update; virtual;    {switches to screen or otherwise makes it visible}
    Procedure ShowCursor; virtual;
    Procedure HideCursor; virtual;
    Procedure VisibleBell; virtual;
    Procedure AllColorsAvailable(enable:boolean); virtual; {if enabled, we have all 16 background colors}
    private
    Procedure UpdateCursorLoc; virtual;
  end;

  PGenericScreen=^TGenericScreen;
  TGenericScreen=Object(TScreen)
  {Uses system ram to build screens and repaints screen RAM when told visible.
  Uses BIOS cursor routines on page 0.  Should work with everything (VGA,
  MDA which only has one video page, etc.) except it's not very efficient.}
    constructor Init(screenseg:word;xsize,ysize:byte);
    destructor Done; virtual;
    Procedure Show; virtual;
    Procedure Update; virtual;
    Procedure ShowCursor; virtual;
    Procedure HideCursor; virtual;
    Procedure VisibleBell; virtual;
    Procedure AllColorsAvailable(enable:boolean); virtual; {if enabled, we have all 16 background colors}
    private
    Procedure UpdateCursorLoc; virtual;
  end;

implementation

uses
  Strings,
  TFastWrite,
  support;

const
  defaultcursorsize:word=0;

constructor TScreen.Init;
begin
  Inherited Init;
  screenram:=ptr(screenseg,0);
  numcols:=xsize; numrows:=ysize;
  screensize:=numcols*numrows*2;
  inc(numscreens);
  if numscreens=1 {if first screen, we have one or more subsystems to init}
    then begin
      TFastInit(numcols,numrows);
      {quickly hide then restore cursor so we have a copy of the inital cursor size}
      HideCursor;
      defaultcursorsize:=state.cursorsize;
      ShowCursor;
    end else begin {this is NOT our first screen init, so we can use this to do some housekeeping}
      State.cursorsize:=defaultcursorsize;
    end;
  {if xsize=80
    then PreventSnow:=true
    else} {PreventSnow:=false;}
  {Annoying to have random colors on first write!}
  State.backfore:=$0F;
  State.cursorFollows:=false;
  MoveTo(0,0);
end;

Destructor TScreen.Done;
begin
  Inherited Done;
end;

Procedure TScreen.Clear;
begin
  TFastClrScr(screenbuf,State.backfore,filler);
end;

Procedure TScreen.SaveState;
begin
  oldstate:=State;
end;

Procedure TScreen.RestoreState;
begin
  State:=oldstate;
end;

Procedure TScreen.Show;
begin
  Abstract;
end;

Procedure TScreen.Update;
begin
  Abstract;
end;

Procedure TScreen.UpdateCursorLoc;
begin
  Abstract;
end;

Procedure TScreen.MoveTo;
begin
  State.x:=x; State.y:=y;
  if State.cursorFollows
  and State.cursorVisible
    then UpdateCursorLoc;
end;

Procedure TScreen.MoveDown;
begin
  MoveTo(State.x,State.y+newy);
end;

Procedure TScreen.Moveover;
begin
  MoveTo(State.x+newx,State.y);
end;

Procedure TScreen.SetBackC;
begin
  State.backfore:=((b AND $0F) shl 4) + (State.backfore AND $0F);
end;

Procedure TScreen.SetForeC;
begin
  State.backfore:=(State.backfore AND $F0) + (f AND $0F);
end;

Procedure TScreen.AllColorsAvailable;
begin
  Abstract;
end;

Procedure TScreen.BlinkON;
begin
  State.backfore:=State.backfore OR BlinkBit;
end;

Procedure TScreen.BlinkOFF;
begin
  State.backfore:=State.backfore AND (NOT BlinkBit);
end;

Procedure TScreen.VisibleBell;
begin
  Abstract;
end;

Procedure TScreen.DrawBox;
var
  s:str80;
  width,height:byte;
  loop:byte;

begin;
  width:=(x2-x1)+1;
  height:=(y2-y1)+1;
  {protect against idiocy}
  if (x1>x2) or (y1>y2) or (width<3) or (height<3) or (width>numcols) or (height>numrows)
    then exit;

  {make top and print}
  fillchar(s,width+1,BoxChars[style].hor);
  s[0]:=char(width);
  s[1]:=BoxChars[style].ul;
  s[width]:=BoxChars[style].ur;
  MoveTo(x1,y1);
  Print(s);
  if titles<>'' then begin
    MoveTo(x1+((width div 2) - (length(titles) div 2)),y1);
    Print(titles);
  end;

  {make "slice" and print one or more}
  fillchar(s,width+1,#32);
  s[0]:=char(width);
  s[1]:=BoxChars[style].ver;
  s[width]:=BoxChars[style].ver;
  for loop:=y1+1 to y2-1 do begin
    MoveTo(x1,loop);
    Print(s);
  end;

  {make bottom and print}
  fillchar(s,width+1,BoxChars[style].hor);
  s[0]:=char(width);
  s[1]:=BoxChars[style].ll;
  s[width]:=BoxChars[style].lr;
  MoveTo(x1,y2);
  Print(s);
end;

Procedure TScreen.PopUp;
begin
  if maxavail<screensize
    then fatalerror(16,strpas(es_NotEnoughMemory));
  popstate:=State;
  getmem(popsaved,screensize);
  move(screenbuf^,popsaved^,screensize);
  DrawBox(x1,y1,x2,y2,double,s);
  MoveTo(x1+1,y1+1); {as a courtesy}
  Update;
end;

Procedure TScreen.RemovePop;
begin
  move(popsaved^,screenbuf^,screensize);
  State:=popstate;
  if state.cursorVisible then begin
    ShowCursor;
    UpdateCursorLoc;
  end else begin
    HideCursor;
  end;
  freemem(popsaved,screensize);
  Update;
end;

Procedure TScreen.Print;
begin
  tfastwritexy(@s,screenbuf,State.x,State.y,State.backfore);
  if State.cursorFollows
    then MoveOver(length(s));
end;

Procedure TScreen.ReColor;
begin
  {!write a tfast for this}
end;

Procedure TScreen.ShowCursor;       {turns on cursor at curx,cury}
begin
  Abstract;
end;

Procedure TScreen.HideCursor;
begin
  Abstract;
end;

{-----------}

constructor TCGAScreen.Init;
begin
  inherited init(screenseg,xsize,ysize);
  vidpage:=numscreens-1;
  {point to proper offset in screen ram}
  screenbuf:=screenram;
  scroffs:=vidpage*(numcols*numrows*2);
  inc(word(screenbuf),scroffs);
end;

destructor TCGAScreen.Done;
begin
  dec(numscreens);
  if numscreens=0 then begin
    {last one, anything need to be done/closed?}
    m6845_SetDisplayAddress(0); {go back to page 0}
  end;
  inherited Done;
end;

Procedure TCGAScreen.UpdateCursorLoc;
begin
  m6845_SetCursorLoc((scroffs+(State.y*numcols*2)+(State.x*2)) shr 1);
end;

Procedure TCGAScreen.Show;
begin
  m6845_SetDisplayAddress(scroffs shr 1);
  {div by 2 because mc6845 has resolution of a 16-bit word, not 8-bit byte}
  if State.cursorVisible
    then begin
      ShowCursor;
      UpdateCursorLoc;
    end else begin
      HideCursor;
    end;
end;

Procedure TCGAScreen.Update;
{we use visible screen ram for CGA, so we have nothing to do here}
begin;
end;

Procedure TCGAScreen.VisibleBell;
{on real CGA, we flash the border}
const
  pulsesize=10;
  pulses:array[0..pulsesize-1] of byte=(
  tRed,tLightRed,tLightGray,tYellow,tWhite,
  tYellow,tLightGray,tLightRed,tRed,tBlack
  );
var
  loop:byte;
begin
  for loop:=0 to pulsesize-1 do begin
    m6845_WaitVertRetrace;
    m6845_SetColor(pulses[loop]);
  end;
end;

Procedure TCGAScreen.ShowCursor;
begin
  {make old cursor reappear...}
  (*m6845_SetCursorSize(oldcursorsize);*) {disabled; see HideCursor}
  {...then move cursor to current coordinates}
  UpdateCursorLoc;
  State.cursorvisible:=true;
end;

Procedure TCGAScreen.HideCursor;
begin
  {make cursor disappear}
  (*oldcursorsize:=BDA_Cursor_Mode;
  m6845_SetCursorSize($1f00);*)
  {that wasn't consistent, we'll just move it to the last possible memory
  location for now to "hide" it}
  m6845_SetCursorLoc($ffff);
  State.cursorVisible:=false;
end;

Procedure TCGAScreen.AllColorsAvailable;
var
  foo:byte;
begin
  foo:=c_videosignal_enable; {must have this or we get NO DISPLAY}
  {if we have too many columns then we're in an 80-col-ish mode}
  if numcols>50 then foo:=foo+c_fast_char_clock;
  if enable then begin
    asm
      mov  dx,m6845_mode_ctl
      mov  al,foo
      out  dx,al
    end;
  end else begin
    foo:=foo+c_blinking_text;
    asm
      mov  dx,m6845_mode_ctl
      mov  al,foo
      out  dx,al
    end;
  end;
end;

{-----------}

constructor TGenericScreen.Init;
begin
  inherited init(screenseg,xsize,ysize);
  getmem(screenbuf,screensize);
end;

destructor TGenericScreen.Done;
begin
  freemem(screenbuf,screensize);
  dec(numscreens);
  if numscreens=0 then begin
    {last one, anything need to be done?}
  end;
  Inherited Done;
end;

Procedure TGenericScreen.Update;
begin
  move(screenbuf^,screenram^,screensize);
end;

{NOT part of any object since object pointer manipulation in asm is a gigantic PITA}
Procedure FlipScrnBufABits(bufp:pointer;size:word);assembler;
asm
  push ds                        {save ds}

  mov cx,size
  shr cx,1
  les di,bufp
  push es
  pop ds
  mov si,di                      {es:di = ds:si = screenbuf}
  mov bl,01111111b               {leave blink bit alone}
@doit:
  lodsw
  xor ah,bl                      {Flip all bits in the attribute byte}
  stosw
  loop @doit

  pop ds
end;

Procedure TGenericScreen.VisibleBell;
{on unknown color card, we flash the screen contents by XOR $FF the attribute bytes}
var
  b:byte;
begin
  FlipScrnBufABits(screenbuf,screensize);
  m6845_WaitVertRetrace;
  Update;
  {do it again, which will put it back to normal}
  FlipScrnBufABits(screenbuf,screensize);
  for b:=0 to 6 do m6845_WaitVertRetrace;
  Update;
end;


Procedure TGenericScreen.Show;
begin
  Update;
  if State.cursorVisible
    then begin
      ShowCursor;
      UpdateCursorLoc;
    end else begin
      HideCursor;
    end;
end;

Procedure TGenericScreen.HideCursor;
var
  w:word;

begin
  {Found an odd "bug" in IBM PC/XT ROM BIOS -- when you set cx=$2000
  to disable the cursor, then try to get cursor size, you get $2000
  back!  This is goofy because the max valid range for start/stop
  is actually $1F1F.  We are going to work around this.}
  asm
    {first get existing cursor size...}
    mov ax,0500h  {(select video page 0 to be safe)}
    int 10h
    mov ah,03h
    xor bh,bh
    int 10h
    mov w,cx {grab it}

    {...then make it disappear}
    mov ah,1
    mov cx,2000h
    int 10h
  end;
  if w=$2000 {someone has set the cursor invisible before we got here!}
    then w:=defaultcursorsize;
  State.cursorsize:=w;
  State.cursorVisible:=false;
end;

Procedure TGenericScreen.ShowCursor;
var
  w:word;
begin
  w:=State.cursorsize;
  asm
    {Make old cursor reappear...}
    mov ax,0100h
    mov cx,w
    int 10h
  end;
  {...then move cursor to current coordinates}
  State.cursorVisible:=true;
  UpdateCursorLoc;
end;

Procedure TGenericScreen.UpdateCursorLoc; assembler;
asm
  {point to our instance!}
  les di,Self
  mov ah,2
  xor bh,bh
  mov dh,es:[di].TGenericScreen.State.y
  mov dl,es:[di].TGenericScreen.State.x
  int 10h
end;

Procedure TGenericScreen.AllColorsAvailable;
begin
  {
  Do nothing, since we are claiming we are generic and we can't control
  the blink bit if we are generic CGA.  If this were EGA or VGA then we
  could do int 10h,10h...
  }
end;

end.
