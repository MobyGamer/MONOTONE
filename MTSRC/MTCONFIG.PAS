program mtconfig;
{
MONOTONE keyboard configuration utility.  Performs the following:

- Loads default.key (if no filename provided on command-line)
- Prevents user from inputting keycombo already defined
- Saves default.key (if no filename provided on command-line)

This was coded in a single evening and no care was taken to make it pretty
or follow OOP standards.  You have been warned :-)
}

uses
  mt_glob,
  mt_input,
  strings,
  support;

const
  defname:string='default.key';
  helpname:string='KEYLIST.TXT';
  quitit:boolean=false;
  saveit:boolean=true;
  dupechecking:boolean=true;

var
  myinput:pinput;

Procedure printmenu;
begin
  write(#13#10#10);
  writeln('  1. Redefine Control keys (controlling the tracker)');
  writeln('  2. Redefine Editing keys (editing a pattern)');
  writeln('  3. Redefine Piano keys (keys used to enter notes from the keyboard)');
  writeln('  4. Redefine Movement keys (moving around a pattern)');
  writeln('  T. Test your defined keybindings');
  writeln('  P. Print all defined keys to the screen (with pause)');
  writeln('  W. Write all defined keys to "',helpname,'"');
  writeln('  D. Toggle DupeChecking (currently set to ',dupechecking,')');
  writeln;
  writeln('  Q. Quit, saving changes');
  writeln('ESC  Quit *without* saving changes');
  writeln;
end;

Procedure Redefine(typeof:inputcategories);
var
  loop,dupe:useractions;
  b:byte;
  temps:string;
  accepted,found:boolean;
  foundaction:useractions;
  psc,pfl:byte;

begin
  write(#13#10#10#10#10#10#10#10#10#10#10#10#10#10#10#10#10#10#10#10#10#10#10#10#10#10#10#10);
  for loop:=low(useractions) to high(useractions) do begin
    if Descriptions[loop].cat=typeof then begin
      writeln(#13#10#10'Description: '+strpas(descriptions[loop].ldes));
      write('Currently set to ');
      write(myinput^.KeypressFromAction(descriptions[loop].act));
      write(#13#10'Press the key combo you wish to use for ',strpas(Descriptions[loop].sdes),': ');
      if DupeChecking then begin
        accepted:=false;
        repeat
          repeat until myinput^.KB^.keypressed;
          psc:=myinput^.KB^.lastkeypressed.scancode;
          pfl:=myinput^.KB^.lastkeypressed.flags;
          {search for keycombo to see if already in use}
          found:=false;
          for dupe:=low(useractions) to high(useractions) do begin
            if ((psc=myinput^.getbinding(dupe)^.scancode) and (pfl=myinput^.getbinding(dupe)^.flags))
              then begin
                found:=true;
                foundaction:=dupe;
              end;
          end;
          if found then begin
            write(#13#10,myinput^.KB^.humanreadable(psc,pfl),' already in use by ');
            for dupe:=low(useractions) to high(useractions) do begin
              if Descriptions[dupe].act=foundaction
                then write(strpas(Descriptions[dupe].sDes));
            end;
            write('; please choose another: ');
          end else begin
            myinput^.setbinding(descriptions[loop].act,myinput^.KB^.lastkeypressed.scancode,myinput^.KB^.lastkeypressed.flags);
            accepted:=true;
          end;
        until accepted;
      end else begin {no duplicate checking; just add the key}
        repeat until myinput^.KB^.keypressed;
        myinput^.setbinding(descriptions[loop].act,myinput^.KB^.lastkeypressed.scancode,myinput^.KB^.lastkeypressed.flags);
      end;
      write(myinput^.KeypressFromAction(descriptions[loop].act));
    end else begin
      {not in our category, so do nothing}
    end;
  end;
end;

procedure testkeys;
var
  findit:useractions;
begin
  writeln('Press ESC to exit testing mode, or press any other key to test: ');
  while myinput^.KB^.lastkeypressed.ascii<>27 do begin
    repeat until myinput^.inputpending;
    write(myinput^.KB^.humanreadable(myinput^.KB^.lastkeypressed.scancode,myinput^.KB^.lastkeypressed.flags),' = ');
    for findit:=low(useractions) to high(useractions) do
      if descriptions[findit].act=myinput^.lastinputreceived
        then begin
          writeln(strpas(descriptions[findit].sDes));
          break;
        end;
  end;
end;

procedure printkeys;
const
  lines=25;
var
  loop:useractions;
begin
  for loop:=low(useractions) to high(useractions) do begin
    writeln(strpas(Descriptions[loop].sdes),': ',myinput^.KeypressFromAction(Descriptions[loop].act));
    if (byte(loop) mod (lines-1))=(lines-2) then begin
      write('- PAUSED -'#13);
      repeat until myinput^.KB^.keypressed;
      write('          '#13);
    end;
  end;
end;

procedure writekeys;
var
  t:text;
  loop:useractions;
  c:inputcategories;

begin
  assign(t,helpname);
  rewrite(t);

  for c:=low(inputcategories) to high(inputcategories) do begin
    write(t,#13#10);
    case c of
      control:writeln(t,'Control Keys:');
      editing:writeln(t,'Editing Keys:');
      pianokey:writeln(t,'Piano (Note) Keys:');
      movement:writeln(t,'Movement Keys:');
    end;
    write(t,'-------------'#13#10#13#10);
    for loop:=low(useractions) to high(useractions) do begin
      if descriptions[loop].cat=c then begin
        writeln(t,Descriptions[loop].sDes,': ',
                  myinput^.KeypressFromAction(Descriptions[loop].act),
                  ' (',Descriptions[loop].lDes,')');
      end;
    end;
  end;

  close(t);
end;

begin
  new(myinput,init);
  if not fileexists(defname) then begin
    myinput^.savestate(defname);
    myinput^.loadstate(defname);
  end else begin
    myinput^.loadstate(defname);
  end;

  {main loop}
  repeat
    printmenu;
    repeat until myinput^.KB^.keypressed;
    case upcase(char(myinput^.KB^.lastkeypressed.ascii)) of
      'Q':quitit:=true;
      '1':redefine(control);
      '2':redefine(editing);
      '3':redefine(pianokey);
      '4':redefine(movement);
      'T':testkeys;
      'P':printkeys;
      'W':writekeys;
      'D':dupechecking:=not dupechecking;
      #27:begin
            quitit:=true;
            saveit:=false;
          end;
    else
      begin
        quitit:=false;
      end;
    end; {case}
  until quitit;

  if saveit then myinput^.savestate(defname);
  dispose(myinput,done);
end.
