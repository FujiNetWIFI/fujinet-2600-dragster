-- rig.lua -- the match verdict: two consoles, one relay, one simulation.
--
-- Everything here is sampled at a FRAME-EXACT point in Dragster's own frame,
-- never at MAME's frame boundary, because MAME's boundary has no relationship
-- to where the program is. Dragster arms TIM64T twice a frame -- $21 for the
-- overscan and $19 for the vertical blank -- so a write tap filtered on $21 is
-- one sample per frame at a fixed instruction, in both builds and on both
-- consoles.
--
-- The snapshot is taken at a chosen simulated TICK and at a chosen phase within
-- it, so the two consoles are compared at the same instant of the SIMULATION
-- however many frames either of them spent booting or stalling.
--
-- SNAP is the simulation and nothing else. The raw console port and the peer's
-- ring slot are printed on LOCAL, which is reported and never compared: with
-- SELECT held on one console those bytes differ BECAUSE the press is working,
-- and a gate that compared them would be asserting that both players had their
-- hands in the same place.
-- os.getenv returns "" for an env var that is SET BUT EMPTY, and tonumber("")
-- is nil, not 0 -- so `INJECT > 0` raises "attempt to compare nil with number",
-- the tap callback aborts THERE, and everything before it in the callback still
-- ran. The symptom is a harness that counts its taps, reports its phases and
-- prints not one sample: it fails exactly as vacuously as a closure over a
-- local declared below it, and for the same reason nobody notices.
-- test/run_rig.sh passes PLAY_INJECT="" to console 2 on every run.
local SNAPTICK = tonumber(os.getenv("SNAPTICK") or "") or 150
local HOLD     = os.getenv("RIG_HOLD") or ""
local INJECT   = tonumber(os.getenv("PLAY_INJECT") or "") or 0
-- Set for CONSOLE 1 ONLY. A gate in which both consoles press the same things
-- at the same time cannot tell a working wire from two machines agreeing by
-- coincidence; driving one and requiring the other to follow is what proves the
-- input actually crossed.
local DRIVE    = os.getenv("RIG_DRIVE") == "1"

-- EVERY CELL A TAP CLOSES OVER IS DECLARED ABOVE EVERY TAP. Lua binds a local
-- at its statement, so a closure over one declared below sees a nil global, the
-- tap dies on its first frame, and the verdict lines fail VACUOUSLY -- they
-- print, they say nothing, and they pass.
local mem, tap
local frames, simframes = 0, 0
local snapped = nil
local locals = nil
local vars = {}
local lastvar = nil
local varwalk = {}
local fields = {}
-- the tick is eight bits and it WRAPS; a run of any length needs the lap
local lasttick, lap = nil, 0
local states = {}
local maxpos, races, lastcd = 0, 0, nil

for _, port in pairs(manager.machine.ioport.ports) do
    for name, field in pairs(port.fields) do fields[name] = field end
end

local function hex(a) return string.format("%02X", mem:read_u8(a)) end

local function snapshot()
    local t = {}
    -- the four globals that decide what everything else MEANS
    t[#t+1] = hex(0x80)         -- GameVar
    t[#t+1] = hex(0x81)         -- FrameCnt, the sim clock
    t[#t+1] = hex(0x82)         -- the LFSR
    t[#t+1] = hex(0x8D)         -- Countdown
    t[#t+1] = hex(0xB9)         -- Attract
    -- and both cars entire, RPM through the previous gear-lever state --
    -- EXCEPT BoomTimer at $D0/$D1, which the audio engine decrements in front
    -- of the lockstep gate and is therefore a function of how much each console
    -- stalled. It is reported on LOCAL and never compared, for the same reason
    -- the raw console port is.
    for a = 0xA8, 0xCF do t[#t+1] = hex(a) end
    for a = 0xD2, 0xD7 do t[#t+1] = hex(a) end
    return table.concat(t, " ")
end

local function sample()
    simframes = simframes + 1
    local ent = mem:read_u8(0x00DA)
    local tick = mem:read_u8(0x00DD)
    if lasttick ~= nil and tick < lasttick and (lasttick - tick) > 128 then
        lap = lap + 1
    end
    lasttick = tick

    -- DID ANYTHING HAPPEN? Two consoles that both sit still agree perfectly,
    -- and a gate that only checks agreement passes a pair of machines that are
    -- agreeing about nothing. So the run reports how far either car got, how
    -- many races were staged, and how many distinct simulation states it saw.
    local p0, p1 = mem:read_u8(0x00BA), mem:read_u8(0x00BB)
    if p0 > maxpos then maxpos = p0 end
    if p1 > maxpos then maxpos = p1 end
    local cd = mem:read_u8(0x008D)
    if lastcd ~= nil and cd > lastcd and cd >= 0x90 then races = races + 1 end
    lastcd = cd
    states[string.format("%02X%02X%02X%02X%02X%02X",
        p0, p1, mem:read_u8(0x00A8), mem:read_u8(0x00A9),
        mem:read_u8(0x00B5), mem:read_u8(0x00B6))] = true

    local gv = mem:read_u8(0x0080)
    if gv ~= lastvar then
        lastvar = gv
        varwalk[#varwalk+1] = string.format("%d@t%d", gv, tick)
        vars[gv] = true
    end

    -- the same instant of the simulation on both consoles: a chosen tick, at
    -- phase 1, which is a frame that ran rather than a boundary that stalled
    if snapped == nil and tick == SNAPTICK and (ent & 0xC0) == 0x40 then
        snapped = snapshot()
        locals = string.format("swchb=%02X ring=%02X ent=%02X boom=%02X/%02X",
            mem:read_u8(0x0282) & 0xFF, mem:read_u8(0x00EA), ent,
            mem:read_u8(0x00D0), mem:read_u8(0x00D1))
    end

    if INJECT > 0 and tick == INJECT and (ent & 0xC0) == 0x40 then
        -- nudge this console's car one step down the strip: a difference the
        -- checksum must notice and the repair must remove
        mem:write_u8(0x00BA, (mem:read_u8(0x00BA) + 1) & 0xFF)
        INJECT = -1
    end
end

-- THE SUBSCRIPTION TOKENS ARE KEPT IN GLOBALS. A notifier or a tap whose token
-- is collected is silently cancelled, and the symptom is a harness that runs a
-- whole match and prints nothing at all -- no error, no output, a clean exit and
-- a verdict block with nothing to read. It cost a rig run to find.
_G._rig_frame = emu.add_machine_frame_notifier(function()
    if not mem then
        mem = manager.machine.devices[":maincpu"].spaces["program"]
        _G._rig_tap = mem:install_write_tap(0x0296, 0x0296, "rig_t64",
            function(offset, data, mask)
                if (data & 0xFF) == 0x21 then sample() end
                return data
            end)
    end
    frames = frames + 1

    -- Input is driven HERE and never from inside the tap: a set_value from
    -- inside a memory tap is silently lost, and a gate that presses nothing
    -- proves nothing.
    -- The default rig DRIVES A RACE from console 1: stage it, let the tree run
    -- down, then hold the throttle and shift up through the gears. Console 2
    -- touches nothing, so every byte of the top car's state that console 2 ends
    -- up holding got there over the wire.
    if DRIVE and HOLD == "" then
        -- THE GEAR LEVER IS THE STICK PULLED LEFT, and it is pull-and-release:
        -- pulling left sets bit 7 of Gear, releasing it increments the gear.
        -- Right stages the race, and the button is the throttle.
        local f = frames % 900
        local function lever(a) return f >= a and f < a + 8 end
        if fields["P1 Right"] then
            fields["P1 Right"]:set_value((f >= 120 and f < 150) and 1 or 0)
        end
        if fields["P1 Left"] then
            fields["P1 Left"]:set_value(
                (lever(320) or lever(380) or lever(450) or lever(530)) and 1 or 0)
        end
        if fields["P1 Button 1"] then
            fields["P1 Button 1"]:set_value((f >= 316) and 1 or 0)
        end
    end

    if HOLD == "select" then
        -- held for the middle of the run, so the variation walks on both
        if fields["Select Game"] then
            fields["Select Game"]:set_value((frames > 300 and frames < 2400) and 1 or 0)
        end
    elseif HOLD == "stage" then
        -- push the stick right in bursts: each one restages the race, which is
        -- the path through the bounded clear that would have wiped the netcode
        if fields["P1 Right"] then
            fields["P1 Right"]:set_value(((frames // 180) % 2 == 1) and 1 or 0)
        end
        if fields["P1 Button 1"] then
            fields["P1 Button 1"]:set_value(((frames // 180) % 2 == 0) and 1 or 0)
        end
    end
end)

_G._rig_stop = emu.add_machine_stop_notifier(function()
    local ent  = mem and mem:read_u8(0x00DA) or 0
    local tick = mem and mem:read_u8(0x00DD) or 0
    local err  = mem and mem:read_u8(0x00DC) or 0
    local st   = mem and mem:read_u8(0x00DE) or 0
    if snapped then
        print("SNAP " .. SNAPTICK .. ": " .. snapped)
        print("LOCAL " .. locals)
    else
        print("SNAP MISSING -- tick " .. SNAPTICK .. " was never reached at phase 1")
    end
    local n = 0
    for _ in pairs(vars) do n = n + 1 end
    print("VARWALK " .. n .. " distinct: " .. table.concat(varwalk, " "))
    local ns = 0
    for _ in pairs(states) do ns = ns + 1 end
    print(string.format("MOVED maxpos=%d races=%d states=%d", maxpos, races, ns))
    print(string.format("RIG ticks=%d tick=%d err=$%02X state=%d ent=$%02X simframes=%d",
                        lap * 256 + tick, tick, err, st, ent, simframes))
end)
