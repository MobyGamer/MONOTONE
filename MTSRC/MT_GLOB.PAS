unit mt_glob;
{global constants and common type definitions used by other objects
throughout the system}

interface

const
  {Our note system in general, which is based off of an equal temperament
  scale where each whole note interval is based on the twelfth root of 2.}
  (*maxNote=88;  {maximum note.  notes go from 1 to 88, 0 will be equiv to nul}*)
  noteEnd=127; {stop sounding!}
  noteNul=0;   {do nothing}

  {this section describes the properties of our music system.  If you want
  to convert MONOTONE to compose for, say, a pentatonic scale, this is where
  you change things.}
  numOctaves=8; {number of octaves we support}
  firstHz=27.5; {Frequency of A0, the first note (byte value=1) of our scale}
  IBO=12; {our music system's Intervals Between Octaves.  We use typical
  system of equal temperament, which is 12 notes from octave to octave.}
  IBN=8; {This is the number of Intervals Between Notes, so we can build a
  table used for vibrato and portamento.  An IBN of 8 is approximately 12 cents.
  To find mult. factor for a table of 8 intervals between notes, use root(IBO*8,2)}
  maxNote=3+(numOctaves*IBO)+1; {the room on the bottom is for a/a#/b; on top is for tippy-top C}
  validNoteRange=[1..maxNote];

  maxChannels=12; {this will increase in the future when I add CMS support}
  maxRows=64; {number of rows per pattern}

type
  {list of actions the user can request independent of the input device used}
  {If you alter this, you MUST alter the labels for these actions in mt_input}
  userActions=(
    {screen selection - only four for now in case we want to go with 80x25}
    goTrackerScreen, {main editing screen}
    goHelpScreen, {displays basic user help}
    goStatusScreen, {status screen showing the freq/vol/eff of each track}
    goPianoScreen, {screen where user can practice notes on the keyboard}

    {pattern movement}
    moveup,movedown,moveleft,moveright,movetop,movebottom,movepgup,movepgdn,

    {tracker movement}
    nextpattern,prevpattern,nextarea,prevarea, {nextarea usually TAB and
    goes between the various areas of the screen (pattern editor, order
    editor, title, etc.)}

    {tracker editing}
    c,csharp,d,dsharp,e,f,fsharp,g,gsharp,a,asharp,b,
    c2,csharp2,d2,dsharp2,e2,f2,fsharp2,g2,gsharp2,a2,asharp2,b2,
    noteoff,erasenote,
    enter,erase,
    octaveup,octavedown,
    deleterow,insertrow,
    erasetrack,mark,swaptrack,pastetrack,pastepattern,
    transup,transdown,transupoctave,transdownoctave,
    loadsong,savesong,

    {playing}
    playsongtop,playsongcur,playpattern,stopplaying,

    {toggling playback channels on/off}
    tc1,tc2,tc3,tc4,tc5,tc6,tc7,tc8,tc9,tc10,tc11,tc12,

    {misc}
    quit,
	writeout
  );

  videochoices=(truecga,generic);
  audiochoices=(PIT,PIT2,PIT3,PIT4,SN76489,SAA_1099,AY_3_8910,YM3812,TANDYCOMBO);
  str80=string[80];
  str40=string[40];
  str12=string[12];
  str2=string[2];

{error strings needed for fatalerror across multiple units}
const
  es_NotEnoughMemory:PChar=
  'Insufficient RAM to complete operation';

implementation

end.
