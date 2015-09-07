unit mt_intro;
{
Small intro for the tracker
}

interface

uses
  mt_scre;

Procedure DumbIntro(scrn:PScreen);
{does something on visseg}

implementation

uses
  strings;

procedure intropic; external;
{$L intropic.obj}

const
  {random messages -- yes, I am childish.  To be displayed as such:
  MONOTONE: "mesg"}
  numrmesgs=5;
  rmesgs:array[0..numrmesgs-1] of PChar=(
  'On the leading edge of the trailing edge',
  'If it''s too old, you''re too young',
  'The true master needs but one channel',
  'PC Speakers of the world, unite!',
  'It''s hip to be square... wave'
  );

Procedure DumbIntro;
var
  screen:pointer;
  screensize:word;
  foo:pointer;

begin
  {Randomize uses dostime, which is a sucky random seed.  We could get a
  better seed from reading the timer, except that we have just reprogrammed
  the timer by this point so it is probably best to just play things safe.}
  Randomize;
  with scrn^ do begin
    hidecursor;
    clear(0);
    foo:=@intropic;
    move(foo^,screenbuf^,40*22*2);
{    moveto(0,numrows-3); print('MONOTONE:');}
    moveto(0,numrows-2); print(strpas(rmesgs[random(numrmesgs)]));
    moveto(10,numrows-1); print('Press a key to start');
    update;
  end;

(*
  asm
    {something dumb for now}
    push ds
    les di,screen
    mov bx,di
    mov dx,00ffh
    mov ax,es
    mov ds,ax
@meltall:
    mov si,bx   {put back original starting point}
    mov di,bx   {put back original starting point}
    mov cx,screensize
@meltpass:
    lodsw       {Load a byte}
    cmp al,0    {is it 0?}
    je @storeit {if so, don't lower it}
    dec ah      {lower it}
@storeit:
    stosb       {store it back}
@abort:
    loop @meltpass
    dec dx
    jnz @meltall
    pop ds
  end;
*)


end;

end.