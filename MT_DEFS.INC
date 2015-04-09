(*
This include file contains compile-time definitions that control various
things you might or might not want to do when compiling MONOTONE.  To enable
an option, remove the double-brace; to disable, put it back or UNDEFINE it.
*)

{{$DEFINE DEBUG} {Enable if you need to debug TPlayer^.CalcAllData.  Will call
on each idle event instead of in the interrupt handler, allowing single-step
of the source (except the output.setallchannels method).}

{{$DEFINE OPT8088} {If OPT8088 set, 8088 assembly will be used for speed}

{$IFDEF DEBUG}
  {$DEFINE PROFILE} {Select whether or not we'll be visually profiling the code}
{$ENDIF}

{Select method of profiling}
{$IFDEF PROFILE}
  {$DEFINE CGAPROF} {profile visually using CGA MC6845 borders}
  {{$DEFINE VGAPROF} {profile visually using VGA}
{$ENDIF}

{{$DEFINE EVILINT} {"Evil" hooked interrupts don't call the original
interrupt.  Define this for a speed boost at the expense of being nice to
the rest of the machine.}

{$DEFINE PITDIVS} {if defined, diskwriter outputs PIT divisor values
instead of frequencies}