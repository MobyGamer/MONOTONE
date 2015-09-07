{$I MT_DEFS.INC}

unit mt_outp;
{directly manipulates the output hardware}

{
(REMINDER:  MONOTONE is not a tracker for any one specific output device,
but rather emulates a simple state machine that can be translated to any
number of output devices.)

The output object classes
translate virtual channels into actual hardware channel output.  The
abstract class supports Volume, Frequency, and Active (whether on or
off).  Future additions might include more, such as Instrument.  Actual
outputdevice descendants MUST support Frequency and Active; the rest are
OPTIONAL.  Additional information may be present in the virtual channels
to aid in processing, but it is not required.  (See mt_play for more
information about what is put into virutal channel data.)

The outputdevice object hooks the interrupt
controller so it can be called, at a bare minimum, 1/60th of a second (MONOTONE's
default player engine frequency).  On every call, it determines if it's time
 to ask the player object to
calculate the next timeslice of data; if so, it does so, then pulls the calc'd data out
of the virtual channel data structure and uses it to set the hardware
appropriately.

The first descendant to be developed is the PC speaker (single voice),
which takes an initialization argument of equalshare=true or false.  See
below for an explanation of what equalshare does.

Programming considerations:
- On altering a song's number of tracks (through loading or otherwise),
player object must be disposed of and then re-initialized.  This may
require the outputdevice object to also be disposed of and then
reinitialized to ensure that the output device does not attempt to call
the playback routine in the middle of its initialization (!).

}

interface

uses
  objects,
  mt_play;

type
  {TOutputDevice is an abstract object that represents an output device.
  Initializing, manipulating, and shutting down said device are
  responsibilities.  This object is used as the basis for more device-
  specific objects that actually do work and manipulate hardware.}
  POutputDevice=^TOutputDevice;
  TOutputDevice=object(TObject)
    numHardwareChannels:byte; {how many physical channels the device supports}
    callCount:longint; {number of times called; this is so the single
    system timer, if there is only one, can be peeked at by other parts
    of the system (say, for game or demo timing)}
    PHookInterval:byte; {how many ticks of the interrupt should go by
    before the player hook is called}
    PHookCount:byte; {on every player hook call, reset to 0.  On every
    interrupt, +1.  if count=interval, time to call player hook.
    !NOTE! these are defined as bytes to save time in the interrupt handler,
    but at a player calc freq of 60Hz, that means the maximum hardware
    interrupt rate is 255*60=15300Hz.  Setting an interrupt rate higher
    than that will result in chaos and destruction!}
    pHookProc:PPlayerEngine; {reminder: virtual channel data is at pHookProc^.VChannels}

    Constructor Init(playerHookProc:PPlayerEngine);
    Destructor Done; virtual;
    Procedure OpenDump(filename:string); virtual;
    Procedure CloseDump; virtual;
    Procedure hookPlayer(pfreq:word); virtual; {Hook the player proc to fire at the specified frequency}
    Procedure unHookPlayer; virtual;
    Procedure setAllChannels; virtual; {calls player hook, then sets all the channels}
    Procedure dumpAllChannels; virtual; {calls player hook, then dumps all the channels to file}

    private

    deviceIFreq:word; {What the hardware device interrupt frequency is.
    This will be 60Hz for simple devices, and something like 4000Hz
    for CPU-emulated devices}
  end;

  {The idea behind the "multichannel" simple speaker output is that it is
  an arpeggiator -- that is, it rapidly (re)sets the speaker to all N
  channels in succession.  Anyone familiar with Neil Rubenking's
  "Pianoman" program from the 1980s will immediately recognize this
  technique, although it is altered here to provide dominance for a
  single channel (see "equalShare" below).  The practical limit for
  this output device is 4 channels.}
  PPCSpeakerSimple=^TPCSpeakerSimple;
  TPCSpeakerSimple=object(TOutputDevice)
    noteIntervalTimerPeriods:TNoteIntervalType;
    {holds timer period equivalents of all the interval frequencies}

    constructor Init(playerHookProc:PPlayerEngine;equal:boolean);
    destructor Done; virtual;
    Procedure OpenDump(filename:string); virtual;
    Procedure CloseDump; virtual;
    Procedure hookPlayer(pfreq:word); virtual; {Hook the player proc to fire at the specified frequency}
    Procedure unHookPlayer; virtual;
    Procedure setAllChannels; virtual; {calls player hook, then sets all the channels}
    Procedure dumpAllChannels; virtual; {calls player hook, then dumps all the channels to file}
	Procedure updateAllChannels;
	
    private

    equalShare:boolean;
    {If equalshare=TRUE, arpeggio frequency is fixed to number of
    channels.  If FALSE, the active channel is rotated throughout the
    channels and is changed based on the following criteria:
      - if a channel is active and enabled, output is changed to that channel's freq
      - if a channel is not active, no action is taken (speaker sounds as before)
      - if ALL channels are not active (quick scan of the row necessary), all output is silenced
    Reasons to use equalshare:
      - you loved Pianoman and want to emulate it perfectly
      - you don't like arpeggio rates changing throughout the song
    Reasons to NOT use equalshare:
      - You want single-track leads to fully sound without interruption (this
        is the only way to hear a nice vibrato lead)
      - You want multichannel "leads" to stand out (if using 4 channels but
        only 1-2-3 are sounding, 3 sounds an extra tick and is more dominant)
    My advice?  Don't use equalshare.  It's too "bubbly".}
    dominantChannel:byte; {see above; rotates on every tick}
    lastFreqWritten:word;
    {variables for dumping to file}
    fhandle:file;
    freqarray:array[0..31000] of word;
    numwritten:word;
  end;

  PYM3812=^TYM3812;
  TYM3812=object(TOutputDevice)
    constructor Init(playerHookProc:PPlayerEngine);
    destructor Done; virtual;
    Procedure OpenDump(filename:string); virtual;
    Procedure CloseDump; virtual;
    Procedure hookPlayer(pfreq:word); virtual; {Hook the player proc to fire at the specified frequency}
    Procedure unHookPlayer; virtual;
    Procedure setAllChannels; virtual; {calls player hook, then sets all the channels}
	Procedure dumpAllChannels; virtual; {calls player hook, then dumps all the channels to file}

    private

    Procedure WriteAdlib(register,value:byte); {write adlib register}
    Procedure AdlibSet(chan:byte;freq:word;volume:byte); {volume is 0-15}
    Procedure AdlibStop(chan:byte);
  end;

  PSN76489=^TSN76489;
  TSN76489=object(TOutputDevice)
    constructor Init(playerHookProc:PPlayerEngine);
    destructor Done; virtual;
    Procedure OpenDump(filename:string); virtual;
    Procedure CloseDump; virtual;
    Procedure hookPlayer(pfreq:word); virtual; {Hook the player proc to fire at the specified frequency}
    Procedure unHookPlayer; virtual;
    Procedure setAllChannels; virtual; {calls player hook, then sets all the channels}
	Procedure dumpAllChannels; virtual; {calls player hook, then dumps all the channels to file}

    private

    Procedure PCjrSet(chan:byte;freq:word;volume:byte); {volume is 0-15}
    Procedure PCjrStop(chan:byte);
  end;

var
  OMasterDevice:POutputDevice;

implementation

uses
  support,
  {$IFDEF CGA_PROFILE}
  m6845ctl, {to grab color constants}
  {$ENDIF}
  TInterrupts;

{$F+}
procedure PlayHandler; Interrupt;

begin
  OMasterDevice^.SetAllChannels;

  {update master count}
  inc(OMasterDevice^.CallCount);
  {update player hook count}
  inc(OMasterDevice^.PHookCount);
  {time to calc some data?}
  if OMasterDevice^.PHookCount=OMasterDevice^.PHookInterval then begin
    OMasterDevice^.PHookProc^.calcAllChannels;
    OMasterDevice^.PHookCount:=0;
  end;

  {$IFNDEF EVILINT} {We want to be nice, and will maintain the BIOS interrupt}

  inc(PITCycles,Chan0Counter); {Keep track of how many PIT cycles have gone by}
  if longrec(PITCycles).hi <> 0 then begin {Did we roll over?  Is it time to call the 18.2Hz BIOS handler?}
    longrec(PITCycles).hi:=0; {Update our PIT cycles counter}
    asm pushf end; {simulate an interrupt by pushing flags, then CALLing handler}
    BIOSTimerHandler; {this will acknowledge the interrupt}
  end else begin
    Port[$20] := $20; {send EndOfInterrupt to the PIC to ackn. the interrupt}
  end;
  {$ELSE}
  Port[$20] := $20; {Just acknowledge the interrupt}
  {$ENDIF}
end;
{IRET generated by the compiler is here; will set interrupt flag,
enabling interrupts again.}
{$F-}

Constructor TOutputDevice.Init;
begin
  Inherited Init;
  {mystuff follows}
  pHookProc:=playerHookProc; {point to our player hook}
end;

Destructor TOutputDevice.Done;
begin
  {mystuff ends}
  Inherited Done;
end;

Procedure TOutputDevice.OpenDump(filename:string);
begin
	Abstract;
end;

Procedure TOutputDevice.CloseDump;
begin
	Abstract;
end;

Procedure TOutputDevice.hookPlayer;
begin
  Abstract;
end;

Procedure TOutputDevice.unHookPlayer;
begin
  Abstract;
end;

Procedure TOutputDevice.setAllChannels;
{This loops through the virtual channel data and uses it to set the
physical hardware device.}
begin
  Abstract;
end;

Procedure TOutputDevice.dumpAllChannels;
{This loops through the virtual channel data and uses it to write the raw data to a file.}
begin
  Abstract;
end;

{-----}

const
  silent=$ffff; {65535 Hz is not only above human hearing, but faster than the speaker cone can physically move}

Constructor TPCSpeakerSimple.Init;
const
  numPhysicalChannels=4;
begin
  Inherited Init(playerHookProc);
  {my stuff}
  deviceIFreq:=60;
  equalShare:=equal;
  dominantChannel:=0;
  {adjust player to never calculate more channels than we have slots for}
  if pHookProc^.numVChannels > numPhysicalChannels
    then pHookProc^.numVChannels := numPhysicalChannels;
  OMasterDevice:=@Self;
  {Initialize PC speaker device}
  Chan2SquarewaveOn(20); {burp to let people know we initialized}
  lastFreqWritten:=$ffff;
end;

Destructor TPCSpeakerSimple.Done;
begin
  Chan2SquarewaveOFF;
  Inherited Done;
end;

Procedure TPCSpeakerSimple.OpenDump(filename:string);
begin
  {$IFDEF PITDIVS}
  assign(fhandle,filename);
  {$ELSE}
  assign(fhandle,'output.frq');
  {$ENDIF}
  rewrite(fhandle,1);
  numwritten:=0;
end;

Procedure TPCSpeakerSimple.CloseDump;
begin
  blockwrite(fhandle,freqarray,numwritten*2);
  close(fhandle);
end;

Procedure TPCSpeakerSimple.hookPlayer;
begin
  {calc how many hardware ints should go by before we calc new row}
  PHookInterval:=deviceIFreq div pfreq;
  {if hardware rate inexplicably slower than player rate, adjust
  so that we don't crash}
  if PHookInterval=0 then inc(PHookInterval);

  {interrupt handler calls ODevice, so set it to us before starting}
  SetTimerHz(@PlayHandler, deviceIFreq); {set our interrupt handler to fire}
end;

Procedure TPCSpeakerSimple.unHookPlayer;
begin
  CleanUpTimer;
end;

Procedure TPCSpeakerSimple.updateAllChannels;
var
  b:byte;
  activeCount:byte;
begin
  {If we're here, we've got a new slice of virtual channel data to
  translate into real channel data (ie. calcAllChannels has already run).
  Use virtual channel data to set real hardware.}

  {When equalShare set, every channel is set/unset.  When unset, sound is
  only terminated if all channels are not active.}
  if phookproc^.vchannels[dominantChannel].active
    {set a "channel"}
    then begin
      lastFreqWritten:=phookproc^.vchannels[dominantChannel].frequency;
    end
    {stop sounding a "channel"}
    else begin
      if equalShare
        then begin
          lastFreqWritten:=silent;
        end
        else begin
          activeCount:=0;
          {count # of channels active}
          for b:=0 to pHookProc^.numVChannels-1 do inc(activeCount,byte(pHookProc^.VChannels[b].active));
          {if no channels are active, THEN turn off speaker}
          if activeCount=0 then begin
            lastFreqWritten:=silent;
          end;
        end;
    end;

  {rotate the "active" voice for our poor little PC speaker}
  inc(dominantChannel);
  if (dominantChannel > (phookproc^.numVChannels-1))
  or (phookproc^.tickCount=0) {This added so that new row forces retrigger.
  Retrigger is necessary because, without it, sound output takes on a "swing"
  tempo as some channels get more time and some get less}
    then dominantChannel:=0;
end;

Procedure TPCSpeakerSimple.setAllChannels;
var
  b:byte;
  activeCount:byte;
begin
  {$IFDEF CGA_PROFILE} asm MOV AL,tLightBlue; MOV DX,03D9h; OUT DX,AL; end; {$ENDIF}

  {play previous note here, to minimize jitter}
  Chan2SquarewaveChange(lastFreqWritten);

  updateAllChannels;

  {$IFDEF CGA_PROFILE} asm MOV AL,tBlack; MOV DX,03D9h; OUT DX,AL; end; {$ENDIF}
end;

Procedure TPCSpeakerSimple.dumpAllChannels;
var
  l:longint;
  w:word;
begin
  updateAllChannels;
  
  {Remember whatever was last sent to speaker}
  w:=lastFreqWritten;
  {$IFDEF PITDIVS}
  {These shannigans to work around TP bug}
  l:=PITfreq div w;
  w:=word(l);
  {$ENDIF}
  freqarray[numwritten]:=w;
  inc(numwritten);
end;

{-----}

{We're going to need some Adlib constants for this block:}
const
  AdlibIndexReg=$388; {also status register}
  AdlibDataReg=$389;
  AdlibSampleRate=49716; {I strongly suspect it is actually 3.58Mhz / 72 = 49722 but other code floating around disproves it}
  {operator offset bases: (2nd operator is always first operator + 3)}
  AdlibOpOffs:array[0..8] of byte=(
  $00,$01,$02,$08,$09,$0A,$10,$11,$12
  );
  {index registers:}
  AdlibEWC=$01;     {Test LSI / Enable waveform control}
  AdlibT1D=$02;     {Timer 1 data}
  AdlibT2D=$03;     {Timer 2 data}
  AdlibTCF=$04;     {Timer control flags}
  AdlibKSN=$08;     {Speech synthesis mode / Keyboard split note select}
  AdlibMVSBase=$20; {Amp Mod / Vibrato / EG type / Key Scaling / Multiple}
  AdlibKSLBase=$40; {Key scaling level / Operator output level}
  AdlibADRBase=$60; {Attack Rate / Decay Rate}
  AdlibSRRBase=$80; {Sustain Level / Release Rate}
  AdlibFLOBase=$A0; {Frequency (low 8 bits)}
  AdlibFHIBase=$B0; {Key On / Octave / Frequency (high 2 bits)}
  AdlibVRC=$BD;     {AM depth / Vibrato depth / Rhythm control}
  AdlibFSTBase=$C0; {Feedback strength / Connection type}
  AdlibWAVBase=$E0; {Wave Select}

type
  PSBITimbre=^TSBITimbre;
  TSBITimbre=record
	  modchar,      (* AM, VIB, SUS, KSR, MUL *)
	  carchar,
	  modscal,      (* KSL, TL *)
	  carscal,
	  modad,        (* Attack/Decay *)
	  carad,
	  modsr,        (* Sustain/Release *)
	  carsr,
	  modwave,      (* Wave Select *)
	  carwave,
    feedback:byte (* FB, Connection *(inverse of Adlib)* <- not true? *)
    {there is more after this but we aren't concerned with supporting
    the "percussion" mode of the Adlib}
  end;

Constructor TYM3812.Init;
const
  numPhysicalChannels=9;
  sbifile='pcspeakr.sbi';
var
  chan:byte;
  tempsbi:PSBITimbre;
  tempf:file;
begin
  Inherited Init(playerHookProc);
  {my stuff}
  deviceIFreq:=60;
  {adjust player to never calculate more channels than we have slots for}
  if pHookProc^.numVChannels > numPhysicalChannels
    then pHookProc^.numVChannels := numPhysicalChannels;
  OMasterDevice:=@Self;

  {initialize the hardware}
  {let's use an .SBI instrument instead of hard-coding stuff in the source}
  if not FileExists('pcspeakr.sbi') then fatalerror(1,'Could not find instrument: '+sbifile);
  assign(tempf,sbifile);
  reset(tempf,1);
  seek(tempf,4+32); {seek past the signature and comment block}
  new(tempsbi);
  blockread(tempf,tempsbi^,sizeof(tempsbi^));
  close(tempf);

  for chan:= 1 to $F5 do WriteAdlib(chan,0); {blank all registers}
  WriteAdlib(AdlibEWC,$20); {= 00100000 = waveform control enabled}
  {set the properties of each channel to the same instrument parameters}
  for chan:= 0 to numPhysicalChannels-1 do begin
    {First write is the modulator; second is the carrier.
    Carrier is always located at +3 the first.}
    WriteAdlib(AdlibMVSBase+AdlibOpOffs[chan],  tempsbi^.modchar);
    WriteAdlib(AdlibMVSBase+AdlibOpOffs[chan]+3,tempsbi^.carchar);
    WriteAdlib(AdlibKSLBase+AdlibOpOffs[chan],  tempsbi^.modscal);
    WriteAdlib(AdlibKSLBase+AdlibOpOffs[chan]+3,tempsbi^.carscal);
    WriteAdlib(AdlibADRBase+AdlibOpOffs[chan],  tempsbi^.modad);
    WriteAdlib(AdlibADRBase+AdlibOpOffs[chan]+3,tempsbi^.carad);
    WriteAdlib(AdlibSRRBase+AdlibOpOffs[chan],  tempsbi^.modsr);
    WriteAdlib(AdlibSRRBase+AdlibOpOffs[chan]+3,tempsbi^.carsr);
    WriteAdlib(AdlibWAVBase+AdlibOpOffs[chan],  tempsbi^.modwave);
    WriteAdlib(AdlibWAVBase+AdlibOpOffs[chan]+3,tempsbi^.carwave);
    WriteAdlib(AdlibFSTBase+chan,tempsbi^.feedback);
  end;
  dispose(tempsbi);
end;

Destructor TYM3812.Done;
var
  chan:byte;
begin
  {blank all registers, which effectively resets the card and stops producing output}
  for chan:= 1 to $F5 do WriteAdlib(chan,0); 
  Inherited Done;
end;

Procedure TYM3812.OpenDump(filename:string);
begin
end;

Procedure TYM3812.CloseDump;
begin
end;

Procedure TYM3812.WriteAdlib;
{Writes a value to an Adlib register.

Notes:
- The port $388 is hard-coded because the Adlib was not jumperable to a
different port, and clones honor that location.
- After writing to the register port, you must wait before sending
more data: 3.3 usec for the address, and 23 usec for the data. The most
accurate method of producing the delay is to read the register port 6 times
after writing to the register port, and read the register port 35 times
after writing to the data port.  This works because the bus speed is
constant no matter how fast the host CPU is.
}

(*
var
  loop:word;
  dummy:byte;
begin
  port[AdlibIndexReg] := register; {tell adlib which register we're selecting}
  for loop:=1 to 6 do dummy:= port[AdlibIndexReg]; {wait for adlib to settle}
  port[AdlibDataReg] := value; {send the data value}
  for loop:=1 to 35 do dummy:= port[AdlibIndexReg]; {wait for adlib to settle}
end;

8088 is so slow that the above adds more delay than necessary.  I prefer this:
*)

begin
  asm
    mov bl,value
    mov dx,AdlibIndexReg
    mov al,register
    out dx,al
    {delay}
    in al,dx; in al,dx; in al,dx; in al,dx; in al,dx; in al,dx
    inc dx
    mov al,bl
    out dx,al
    {delay}
    in al,dx; in al,dx; in al,dx; in al,dx; in al,dx; in al,dx; in al,dx;
    in al,dx; in al,dx; in al,dx; in al,dx; in al,dx; in al,dx; in al,dx;
    in al,dx; in al,dx; in al,dx; in al,dx; in al,dx; in al,dx; in al,dx;
    in al,dx; in al,dx; in al,dx; in al,dx; in al,dx; in al,dx; in al,dx;
    in al,dx; in al,dx; in al,dx; in al,dx; in al,dx; in al,dx; in al,dx
  end;
end;

Procedure TYM3812.hookPlayer;
begin
  {calc how many hardware ints should go by before we calc new row}
  PHookInterval:=deviceIFreq div pfreq;
  {if hardware rate inexplicably slower than player rate, adjust
  so that we don't crash}
  if PHookInterval=0 then inc(PHookInterval);

  {interrupt handler calls ODevice, so set it to us before starting}
  SetTimerHz(@PlayHandler, deviceIFreq); {set our interrupt handler to fire}
end;

Procedure TYM3812.unHookPlayer;
begin
  CleanUpTimer;
end;

Procedure TYM3812.AdlibSet;
const
  maxAfreq=((65535 * 2) div 21);
var
  f,period,octave:word;
  templ:longint;
begin
  {adapted from code originally written by Joe Snow}
  {this ineffecient code courtesy of TP arithmetic overflow detection bug}
  templ:=freq;
  templ:=templ * 21;
  templ:=templ div 2;
  period:=templ;
  octave:=36;
  while (period>1023) do begin
    inc(octave,4);
    period:=period shr 1;
  end;

  {set frequency}
  WriteAdlib(AdlibFLOBase+AdlibOpOffs[chan],lo(period));
  WriteAdlib(AdlibFHIBase+AdlibOpOffs[chan],octave+hi(period));
  {set volume, 2nd operator:}
  WriteAdlib(AdlibKSLBase+AdlibOpOffs[chan]+3,63-volume);
end;

procedure TYM3812.AdlibStop;
begin
  {Clear bit 5 ("key on").  Frequency also goes to 0 but that's just a side effect :-)}
  WriteAdlib(AdlibFHIBase+AdlibOpOffs[chan], 0);
end;

Procedure TYM3812.setAllChannels;
var
  chan:byte;
begin
  {$IFDEF CGA_PROFILE} asm MOV AL,tLightBlue; MOV DX,03D9h; OUT DX,AL; end; {$ENDIF}
  {If we're here, we've got a new slice of virtual channel data to
  translate into real channel data (ie. calcAllChannels has already run)}

  for chan:=0 to pHookProc^.numVChannels-1 do begin
  if phookproc^.vchannels[chan].active
    {set a "channel"}
    then AdlibSet(chan,
                  phookproc^.vchannels[chan].frequency,
                  phookproc^.vchannels[chan].volume)
    {stop sounding a "channel"}
    else AdlibStop(chan);
  end;
  {$IFDEF CGA_PROFILE} asm MOV AL,tBlack; MOV DX,03D9h; OUT DX,AL; end; {$ENDIF}
end;

Procedure TYM3812.dumpAllChannels;
begin
end;


{-----}

{We're going to need some SN (tandy/pcjr) constants for this block:}
const
  SNReg=$C0;
  SNFreq=3579540;
  SNMplxr=$61; {MC14529b sound multiplexor chip in the PCjr}

Constructor TSN76489.Init;
const
  numPhysicalChannels=3;

begin
  Inherited Init(playerHookProc);
  {my stuff}
  deviceIFreq:=60;
  {adjust player to never calculate more channels than we have slots for}
  if pHookProc^.numVChannels > numPhysicalChannels
    then pHookProc^.numVChannels := numPhysicalChannels;
  OMasterDevice:=@Self;
  {initialize the hardware}

  asm
    in  al,SNMplxr
    or  al,01100000b {set bits 6 and 5 to route SN audio through multiplexor}
    out SNMplxr,al
  end;
end;

Destructor TSN76489.Done;
var
  chan:byte;
begin
  {blank all registers, which effectively resets the card and stops producing output}
  for chan:=0 to 2 do PCjrStop(chan);
  {Reset the multiplexor}
  asm
    in  al,SNMplxr
    and al,10011100b {clear 6 and 5 to route PC speaker through multiplexor; 1 and 0 turn off timer signal}
    out SNMplxr,al
  end;
  Inherited Done;
end;

Procedure TSN76489.OpenDump(filename:string);
begin
end;

Procedure TSN76489.CloseDump;
begin
end;

Procedure TSN76489.PCjrSet;
{Sets an SN voice to full volume on and a desired frequency}
var
  period:integer;
begin
  period := SNFreq div (32*freq);
  {clamp period so that it doesn't exceed invalid ranges.  This also
  removes the need to strip out bits that would interfere with the
  OR'd command bits sent to the register}
  if period > 1023 then period:=1023;
  if period < 0 then period:=0;
{
  To set a channel, we first send frequency, then volume.
  Frequency:
  76543210 76543210
  1                 - set bit to tell chip we are selecting a register
   xx0              - set channel.  4, 2, and 0 are valid values.
      xxxx          - low 4 bits of period
           0        - clear bit to tell chip more freq. coming
            x       - unused
             xxxxxx - least sig. 6 bits of period

  Sending a word value will not work on PCjr, so send bytes individally.
  (It does work on Tandy, but we want to be nice.)

  Set attenuation (volume):

  76543210
  1                 - set bit to tell chip we are selecting a register
   xx1              - register number (valid values are 1, 3, 5, 7)
      xxxx          - 4-bit volume where 0 is full volume and 15 is silent)

}
  asm
    {this procedure could be optimized to be either smaller OR faster
    but I just want to get it working right now}
    {build MSB}
    mov al,chan
    add al,al            {voice doubled = register #}
    mov cl,4
    shl al,cl            {get voice reg in place}
    or  al,10000000b     {tell chip we are selecting a reg}
    mov dx,period        {save period val for later}
    mov bx,dx
    and bl,00001111b     {grab least sig 4 bits of period...}
    or  al,bl            {and put them in MSB}
    out SNreg,al         {output MSB}
    {build LSB}
    mov bx,dx            {restore original period val}
    shr bx,cl            {isolate upper 6 bits}
    and bl,01111111b     {clear bit 7 to indicate rest of freq}
    mov al,bl
    out SNreg,al         {send LSB}

    {set the volume}
    mov al,chan
    inc al
    add al,al
    dec al               {set voice 3 bits to 1, 3, 5, or 7}
    shl al,cl            {get voice value into place}
    or  al,10000000b     {tell chip we're selecting a reg}
    mov bl,volume
    shr bl,1
    shr bl,1             {0-63 to 0-15}
    not bl               {adjust to attenuation; register expects 0 = full, 15 = quiet}
    and bl,00001111b     {mask off junk bits}
    or  al,bl            {merge the volume into the reg select bits}
    out SNreg,al         {send volume}
  end;
end;

procedure TSN76489.PCjrStop(chan:byte);
{stop a channel by setting its volume to 15 (quiet)}
begin
  asm
    mov dx,SNreg
    mov al,chan
    mov cl,4
    inc al
    add al,al
    dec al               {set voice 3 bits to 1, 3, 5, or 7}
    shl al,cl            {get voice value into place}
    or  al,10001111b     {tell chip we're selecting a reg and set volume to 15 which = silent}
    out SNreg,al            {send volume}
  end;
  PCjrSet(chan,440,0);
end;

Procedure TSN76489.hookPlayer;
begin
  {calc how many hardware ints should go by before we calc new row}
  PHookInterval:=deviceIFreq div pfreq;
  {if hardware rate inexplicably slower than player rate, adjust
  so that we don't crash}
  if PHookInterval=0 then inc(PHookInterval);

  {interrupt handler calls ODevice, so set it to us before starting}
  SetTimerHz(@PlayHandler, deviceIFreq); {set our interrupt handler to fire}
end;

Procedure TSN76489.unHookPlayer;
begin
  CleanUpTimer;
end;

Procedure TSN76489.setAllChannels;
var
  chan:byte;
begin
  {$IFDEF CGA_PROFILE} asm MOV AL,tLightBlue; MOV DX,03D9h; OUT DX,AL; end; {$ENDIF}
  {If we're here, we've got a new slice of virtual channel data to
  translate into real channel data (ie. calcAllChannels has already run)}

  for chan:=0 to pHookProc^.numVChannels-1 do begin
  if phookproc^.vchannels[chan].active
    {set a "channel"}
    then PCjrSet(chan,
               phookproc^.vchannels[chan].frequency,
               phookproc^.vchannels[chan].volume)
    {stop sounding a "channel"}
    else PCjrStop(chan);
  end;
  {$IFDEF CGA_PROFILE} asm MOV AL,tBlack; MOV DX,03D9h; OUT DX,AL; end; {$ENDIF}
end;

Procedure TSN76489.dumpAllChannels;
begin
end;

end.
