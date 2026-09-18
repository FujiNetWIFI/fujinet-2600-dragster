# Porting Dragster to lockstep

What this cost to learn, written down so the next one costs less. The sibling
document is `fujinet-2600-combat/PORTING.md`, and this assumes it: everything
there about the mailbox, the arm-then-commit rule, the sequence number coming
from the cartridge and not from RAM, and the shape of delay-based lockstep is
still true and is not repeated here.

What follows is what was different, and what was wrong.

---

## 1. The model

- **The sim clock is a tick of K video frames, and it is not the frame.**
  Dragster's `FrameCnt` ($81) is Combat's `CLOCK`: it selects which car the
  logic updates, and paces the engine tone, the road scroll, the gear timer, the
  scrape and the lane drift. It moves out of `$F29A` and into `DGSHIM`, behind
  the gate, so it counts frames the simulation took and not frames the
  television drew.
- **Input** is captured at tick `T`, sent tagged for `T+d`, and applied on both
  consoles at `T+d`.
- **A stall** is a frame that runs normally with the game logic skipped.
- **Desync** is detected by a checksum riding every input record and repaired by
  a synthetic RESET, which restages the race.

`K = 4`, `d = 2`: eight frames, about 133 ms.

## 2. What is different about this game

### 2.1 The elapsed time is the game, and lockstep taxes it

Combat has no quantity like Dragster's clock. A tank that turns 133 ms late
turns 133 ms late; a dragster that launches 133 ms late has a worse time, for
ever, in the only number the game prints.

The fix is the **display lead**: draw the countdown tree from `Countdown -
DGLEAD` rather than `Countdown`, where `DGLEAD = K*d = 8`. The player reacts to
a green that is eight simulated frames early and the press lands at sim-green.

Three things about it are worth keeping:

- **The direction is down.** `Countdown` runs `$9F` to 0 and zero IS green, so
  "ahead" means subtracting. Get it backwards and the tree shows *late*, which
  looks exactly like network lag — and every synchronisation gate still passes,
  because the two consoles agree perfectly about a tree that is wrong on both.
  `make tree` and `make rig-launch` are the only gates that can fail on it.
- **Eight is the minimum latency, not the mean**, and that is the right choice.
  A press on a boundary frame lands 8 frames later; one made 1–3 frames into a
  tick is sampled at the next boundary and lands 9–11 later. A lead of 8 makes a
  perfect launch achievable and never lets a player beat the tree. A lead of 10
  would let them, and the jump-start test at `$F450` would start firing.
- **It is a cell, not a constant.** `DGLEAD` is zero unless the boot bank hands
  over networked, which is what keeps `make det` a comparison against the 1980
  ROM rather than against this port's idea of one.

**The shifts are not compensated and cannot be.** The countdown is a
deterministic function of the simulation, so it can be shown early honestly.
What the revs will do next is a function of what the player does next. Nothing
can show that early, so gear changes land `d` ticks late and a full-race time
over the network is still higher than the same driver's on one console. Say so
rather than implying otherwise.

### 2.2 A stall is free, more cheaply than in Combat

Combat had to reason about the collision latches accumulating identically across
a frozen frame. Dragster never strobes `CXCLR` and never reads a collision
register — it has no collision detection at all — and its kernel rebuilds every
TIA register it uses from RAM on every frame. N frozen frames leave exactly what
one would.

### 2.3 There are two timed windows and only one of them is usable

| site | timer | in front of it | measured worst |
|---|---|---|---|
| `$F285` overscan | `TIM64T = $21`, 2112 cyc | the audio engine | **1792 cycles** |
| `$F046` vblank | `TIM64T = $19`, 1600 cyc | the whole game logic | **448 cycles** |

Both measured by `make slack` under a real race, which matters: on an attract
screen the vertical blank reports 1152 and the tach-bar loop at `$F4D1` — 19
iterations of 31 cycles — never runs. The hook is the overscan; the vertical
blank is the reserve, and `make slack` asserts a floor on it as the early
warning for anything a later change puts in the logic chain.

### 2.4 There was no disassembly, so the generator is the thing to trust

Combat reused a commented DASM source that had existed publicly since 1997.
Nothing equivalent exists for Dragster, so `tools/disasm.py` generates one —
which moves the thing that has to be trusted from a document to a program, and
means `make verify-org` has to prove two claims rather than one:

1. the generator's own: every instruction re-encodes to the bytes it came from,
   the reached-code set matches the declared regions, and the one biased operand
   still evaluates to the address it names;
2. that `rom/dragster.asm` is that output **plus comments and nothing else** —
   both run through `tools/strip.py` and compared;
3. and that it assembles to `rom/dragster.bin` byte for byte.

Recursive descent from `$F000` reaches every code byte and touches no data byte,
so there is nothing to seed by hand. 778 instructions, 1463 code bytes.

---

## 3. The expensive lessons

### 3.1 Dragster carries the player index in the X register for 183 bytes

**This is the one that cost the most, and it was not in the transport.**

`$F22A` does `TAX`. The next instruction to touch X is `$F2DD LDA Joy0,X`, the
restage test. Between them are the audio engine, VSYNC, the frame counter and
the attract colours, and *nothing* reloads X — the game logic proper does, at
`$F32E`, but that one read does not.

`JSR DGWAIT` at `$F285` lands exactly in the middle of that span, and the
mailbox uses X for every register it writes. So the restage test read `$AD` plus
whatever step the transport happened to be on, which is never the same step on
two consoles.

The symptom was three or four times a minute one console staging a race a single
simulated frame before the other; four ticks of checksum disagreement; the
repair pressing RESET into the wire; and the two coming back together. **It read
as a transport fault for a long time.** What found it was a per-simulated-frame
dump of both consoles with the furniture excluded, and then a probe on the write
that stages a race, which showed the two staging on different `CurPlayer`
parities.

*The rule:* **a hook inserted into someone else's frame must leave the registers
as it found them, or must restore the invariant at the place that consumes it.**
Two bytes at the gate, `LDX CurPlayer`, restore it where it is needed.
Preserving X inside `DGWAIT` instead would have cost four stack bytes, and the
stack is six.

*How to look for it in the next game:* find every register-carried value that
crosses the address you are about to hook. A disassembler can do it — walk
backwards from each indexed access to the last instruction that wrote the index.

### 3.2 Combat's §4.5, upside down

Combat's trap was a quantity sampled only on the ticks that RAN, which makes it
a function of the local stall pattern. Dragster's is the mirror image: a
quantity advanced on the frames that did NOT run.

`BoomTimer` ($D0/$D1) is the explosion sound's countdown. The logic *sets* it at
`$F3EF`, behind the gate — but it is read at `$F237` and decremented at `$F23D`,
and both are inside the audio engine, which sits at `$F226-$F284`, in front of
the hook at `$F285`. The audio runs on every frame the television draws,
including stalled ones, because a sound that stuttered whenever the transport
was late would be worse than the stall it was reporting.

So it advances once per video frame while the rest of the simulation advances
once per simulated frame, and the difference is the stall pattern.

It is safe to leave out of the checksum, and provably: `$F237`, `$F23D` and
`$F3EF` are its only three references in the cartridge, and everything it
reaches is `AUDV0`, `AUDF0` and `AUDC0`. No audio cell reaches physics. This is
Dragster's version of "B&W stays local".

*Symptom, for the next person:* 27 `CRC MISMATCH` lines in the relay log,
clustered in bursts of four or five consecutive ticks, arriving only after an
engine blew — and two consoles byte-identical before and after each burst.

### 3.3 Zero in a joystick nibble is not "nothing pressed"

The restage clear is widened from stock's `$B9` to `$A8` in a match, so the
repair covers every checksummed cell. `$AD/$AE` — the joystick shadows — are
inside that range, and **zero in an active-low nibble is all four directions
pressed at once**, including bit 2, which is Dragster's gear lever.

Stock never sees it: its clear starts at `$B9`, and in any case `$F2C8` re-read
the port before anything looked at the cells. This port deleted that read, and
`DGMIX` writes them only on a TICK boundary — so in a match the fabricated press
stands for up to three frames. Long enough for `$F43B` to see the lever go down
and come back up, which arms a shift and then releases it, and a release while
the tree is counting is a jump start.

**Every single race began with EARLY on the screen, and `rig`, `rig-play` and
`tree` all passed while it did.** They are agreement gates, and both consoles
fabricated the same press at the same tick, so they agreed perfectly.

*The rule:* **a gate that measures agreement cannot tell you the game works.**
`make rig-launch` — which measures the race rather than the sync — is the gate
that found it, and it is the reason to have one.

### 3.4 A widened clear is a behaviour change, and `det` will say so

The fix above, applied unconditionally, put `$0F` into the shadows on a cold
start where stock leaves `$00`. That is two cells on frame three, and `make det`
failed on it immediately. The re-seed is now guarded on `DGE_NET`: not
networked, the clear never reaches the shadows and stock's behaviour is stock's
behaviour.

### 3.5 `tonumber("")` is nil, and an env var that is SET BUT EMPTY is ""

`test/run_rig.sh` passes `PLAY_INJECT=""` to console 2 on every run.
`tonumber(os.getenv("PLAY_INJECT") or "0")` returns **nil**, not 0 — the `or`
never fires, because `""` is truthy in Lua — and `INJECT > 0` then raises
"attempt to compare nil with number". The tap callback dies *there*, and
everything before it in the callback still ran.

The symptom is a harness that counts its taps, reports its phases and prints not
one sample. It fails exactly as vacuously as Combat's §4.22 closure-over-a-
local-declared-below, and for the same reason nobody notices: the gate produces
output, and the output is silence.

Write `tonumber(os.getenv("X") or "") or 0`.

### 3.6 And §4.22 itself, again

`tracep` was defined below the frame notifier that called it. 1798 `[LUA ERROR]`
lines into a file nobody was reading, once per frame, for a whole run. Declare
every function a callback calls above every callback.

### 3.7 The PC read inside a memory tap is not the instruction's

`manager.machine.devices[":maincpu"].state["PC"].value`, read from inside a read
tap, is the CPU's program counter — which has already moved on. Chasing `$13B9`
as an unpatched `SWCHB` site cost an hour; it was the PC left over from a
patched `LDA DGTRIG,X` two instructions earlier, and then, on the second look,
the boot bank's `CSLEFT` at the same address in a different bank.

Report the **address read** alongside the PC, and track which **bank** is live
from the bank hotspot rather than reading it out of the cartridge window.

### 3.8 MAME's notifier tokens are garbage-collected

`emu.add_machine_frame_notifier` and `install_write_tap` return a token. Let it
go out of scope and the subscription is silently cancelled: the harness runs a
whole match and prints nothing at all — no error, a clean exit, and a verdict
block with nothing to read. Keep them in globals, as `emu/frames.lua` does.

### 3.9 MAME exits nonzero under `-seconds_to_run`

Every Make recipe that reads its output has to say `|| true` or a successful
gate stops the build.

---

## 4. The bank split, and why it was cheap

One cross-bank reference exists in the whole of Dragster: `$F4E2 JMP FrameTop`.
Seam B is a fall-through. Both cost zero patched bytes, because every byte keeps
its cartridge address and the bank that does not own a seam has a hole exactly
there.

What makes that true is that a region's bank is a **set**. Combat had one
`EXPORT` of addresses and no shared code — and could not have had any, because a
bank switch is a jump and nothing returns through one. Dragster has four shared
regions, one of them code: `StageRace` (game bank) `JMP`s into the *middle* of
`PositionSprites` at `$F4E9` and returns through its `RTS` to `StageRace`'s own
caller, so those 72 bytes are duplicated into both banks rather than switched
to. `check_patch.py` compares a shared region in **every** bank that owns it.

*Worth checking early in the next port:* compute the cross-bank reference set
before writing any code. Twenty lines of Python over the disassembly, and it
tells you whether the split you have in mind is cheap or ruinous.

## 5. The ball, which looks like a hazard and is not

`RESBL` is never written by name in Dragster. `StageRace` ends `TAX` with
`A = $04` and enters `PositionSprites` at `$F4E9`, skipping its `LDX #$00` — so
`STA $20,X` and `STA $10,X` land on `HMBL`/`RESBL`, anchored by the `STA WSYNC`
at `$F511`, and `CPX #$02 / BCC` falls straight out with X = 5.

Every path into a race goes through `StageRace`, so it is deterministic and
there is no cold-start hazard to design around. `make ball` keeps a cheap guard
on the shape of that path anyway, because the mechanism is invisible in the
source.

## 6. checkrom, and why a data-region filter is not enough here

Combat filtered `checkrom.py`'s findings by declared data region: both of its
findings were inside tables. Dragster's sim clock lives at `$81` and its sprite
pointers at `$90`, so `LDA $81`, `INC $81`, `AND $81` and `STA $0091,Y` put the
banned opcode *values* all over the **code** — eight of the nine in the image
are operand bytes inside instructions, and a region filter drops one and fails
the build on the other eight.

The filter is an **instruction-boundary map** taken from the assembler's own
listings: a `DB`/`DW` line contributes no boundaries, any other emitting line
contributes one at its first address, and a finding is fatal only if its address
is a boundary *and* the byte there really is the opcode reported. Mechanically
complete, and it covers the injected netcode for free.

## 7. Status

| gate | result |
|---|---|
| `verify-org` | 778 instructions, 1463 code bytes; round trip OK; regions agree; 2048 bytes identical to the dump |
| `dragster` | 8192 bytes; checkrom clean; the clear proved bounded; 2126 bytes compared, 89 changed, **all declared** |
| `frames` | 262 lines on stock and on the split build, every frame, through two bank switches |
| `det` | **742 simulated frames identical to the 1980 cartridge** |
| `inputs` | locally, 4 sites all inside `DGLOC0`; in a match, all inside `DGCAP` plus `DGMIX`'s deliberate B&W read, and `DGLOC0` never runs |
| `lag` | shadows change 0.07 times a second against a stick wiggled ten times a second |
| `tree` | lead 0 local, 8 networked; beeps at `$98 $88 $78 …`, stock's values plus the lead |
| `slack` | overscan 1792 cycles worst, vertical blank 448 — under a real race |
| `ball` | 2 WSYNCs from the stage to the `RESBL` strobe, on stock and on the build |
| `sim` | 22 protocol conformance checks |
| `lobby` | 10 registration checks against a mock |
| `rig` | 798/801 ticks, byte-identical at the snapshot tick, 0 mismatches; both consoles report the same races, the same maxpos and the same 718 states |
| `rig-hold` | SELECT held on one console walks the variation identically on both, tick for tick |
| `rig-stage` | 237 restages each, 0 mismatches — the bounded clear holds |
| `rig-play` | 541 ticks in common, **zero divergence at any tick**, both driving asynchronously |
| `rig-launch` | no foul; both consoles record the **same time**; launch 7 frames after green against stock's 5, where with no lead it would be 13 |
| `rig-repair` | injected at tick 257, diverged 4 ticks, recovered in 0.3 s, last 120 ticks byte-identical |

Never run on hardware. Every number here is MAME plus a real `fujinet-pc`
speaking BoIP to a real socket; what is missing is the cartridge bus.
