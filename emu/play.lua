-- play.lua -- dump the simulation once per tick, so playdiff.py can name the
-- first cell that disagrees.
--
-- `make rig` proves the two consoles agree at ONE tick. This proves it at every
-- tick, and when they stop agreeing it says which byte went first -- which is
-- the difference between "there is a desync" and knowing what caused it.
--
-- Both consoles play, on deliberately DIFFERENT schedules. The asynchrony is
-- the property under test: two machines pressing the same things at the same
-- time cannot tell a working wire from a coincidence.
-- os.getenv returns "" for an env var that is SET BUT EMPTY, and tonumber("")
-- is nil, not 0 -- so `INJECT > 0` raises "attempt to compare nil with number",
-- the tap callback aborts THERE, and everything before it in the callback still
-- ran. The symptom is a harness that counts its taps, reports its phases and
-- prints not one sample: it fails exactly as vacuously as a closure over a
-- local declared below it, and for the same reason nobody notices.
-- test/run_rig.sh passes PLAY_INJECT="" to console 2 on every run.
local WINDOW  = os.getenv("PLAY_WINDOW") or ""
local INJECT  = tonumber(os.getenv("PLAY_INJECT") or "") or 0
local DRIVE   = os.getenv("RIG_DRIVE") == "1"

local mem, tap
local frames = 0
local lasttick, lap = nil, 0
local lastfc, fclap = nil, 0
local out = {}
local fields = {}
local injected = false
local taps, phases = 0, {}

for _, port in pairs(manager.machine.ioport.ports) do
    for name, field in pairs(port.fields) do fields[name] = field end
end

local function sample()
    local ent  = mem:read_u8(0x00DA)
    local tick = mem:read_u8(0x00DD)

    -- ONE LINE PER EXECUTED SIMULATED FRAME, indexed by FrameCnt with its lap.
    -- FrameCnt is Dragster's own sim clock and it advances only on a frame the
    -- gate let through, so it is the finest index two consoles can be compared
    -- at -- finer than the tick, which is four of these.
    local fc = mem:read_u8(0x0081)
    if fc ~= lastfc then
        if lastfc ~= nil and fc < lastfc then fclap = fclap + 1 end
        lastfc = fc
        out[#out+1] = string.format(
            "F %d ent=%02X adv=%02X cp=%02X j0=%02X j1=%02X rpm=%02X%02X cd=%02X "..
            "done=%02X%02X gear=%02X%02X pos=%02X%02X lfsr=%02X trig=%02X%02X swb=%02X "..
            "w=%02X%02X rw=%02X ring=%02X%02X%02X%02X%02X%02X%02X%02X",
            fclap * 256 + fc, ent, mem:read_u8(0x00E0), mem:read_u8(0x008F),
            mem:read_u8(0x00AD), mem:read_u8(0x00AE),
            mem:read_u8(0x00A8), mem:read_u8(0x00A9), mem:read_u8(0x008D),
            mem:read_u8(0x00D2), mem:read_u8(0x00D3),
            mem:read_u8(0x00CC), mem:read_u8(0x00CD),
            mem:read_u8(0x00BA), mem:read_u8(0x00BB), mem:read_u8(0x0082),
            mem:read_u8(0x00E5), mem:read_u8(0x00E6), mem:read_u8(0x00E4),
            mem:read_u8(0x00E7), mem:read_u8(0x00E8), mem:read_u8(0x00E9),
            mem:read_u8(0x00EA), mem:read_u8(0x00EB), mem:read_u8(0x00EC),
            mem:read_u8(0x00ED), mem:read_u8(0x00EE), mem:read_u8(0x00EF),
            mem:read_u8(0x00F0), mem:read_u8(0x00F1))
    end
    taps = taps + 1
    phases[ent & 0xC0] = (phases[ent & 0xC0] or 0) + 1
    if lasttick ~= nil and tick < lasttick and (lasttick - tick) > 128 then
        lap = lap + 1
    end
    -- once per tick, at phase 1: a frame that RAN, not a boundary that stalled
    if tick == lasttick or (ent & 0xC0) ~= 0x40 then
        lasttick = tick
        return
    end
    lasttick = tick

    if INJECT > 0 and not injected and (lap * 256 + tick) >= INJECT then
        -- nudge this console's car one step down the strip: a difference the
        -- checksum must notice and the repair must remove
        mem:write_u8(0x00BA, (mem:read_u8(0x00BA) + 1) & 0xFF)
        injected = true
    end

    local t = {}
    for a = 0x80, 0xD7 do t[#t+1] = string.format("%02X", mem:read_u8(a)) end
    out[#out+1] = string.format("S %d %d %s", lap * 256 + tick, tick, table.concat(t, ""))
    -- The netcode's own cells, on their own line so they never enter the state
    -- comparison. DGCRCV is the quantity the relay pairs and complains about;
    -- being able to see it beside the state it is supposed to summarise is the
    -- difference between "there is a mismatch" and knowing what is in it.
    out[#out+1] = string.format("C %d crcv=%02X ent=%02X err=%02X nst=%02X boom=%02X%02X",
        lap * 256 + tick, mem:read_u8(0x00DF), mem:read_u8(0x00DA),
        mem:read_u8(0x00DC), mem:read_u8(0x00DE),
        mem:read_u8(0x00D0), mem:read_u8(0x00D1))
end

_G._play_frame = emu.add_machine_frame_notifier(function()
    if not mem then
        mem = manager.machine.devices[":maincpu"].spaces["program"]
        _G._play_tap = mem:install_write_tap(0x0296, 0x0296, "play_t64",
            function(offset, data, mask)
                if (data & 0xFF) == 0x21 then sample() end
                return data
            end)
        -- WHAT DID THE CONSOLE ACTUALLY SEE? A read tap on the two joystick
        -- shadows fires at $F2DD, which is the restage test itself, and records
        -- the value the instruction got together with the player index it was
        -- indexed by. Bounded to a window so the output stays readable.
        _G._play_joy = mem:install_read_tap(0x00AD, 0x00AE, "play_joy",
            function(offset, data, mask)
                local fc = (fclap or 0) * 256 + mem:read_u8(0x0081)
                if fc >= 1140 and fc <= 1175 then
                    out[#out+1] = string.format("JOY fc=%d addr=%02X val=%02X cp=%02X rpm=%02X%02X done=%02X%02X",
                        fc, offset, data & 0xFF, mem:read_u8(0x008F),
                        mem:read_u8(0x00A8), mem:read_u8(0x00A9),
                        mem:read_u8(0x00D2), mem:read_u8(0x00D3))
                end
                return data
            end)

        -- CATCH THE RESTAGE IN THE ACT. StageRace writes $9F to Countdown and
        -- nothing else does, so this fires exactly once per staged race, at the
        -- instruction that stages it -- and records what the console could see
        -- when it made the decision.
        _G._play_stage = mem:install_write_tap(0x008D, 0x008D, "play_stage",
            function(offset, data, mask)
                if (data & 0xFF) == 0x9F then
                    out[#out+1] = string.format(
                        "STAGE fc=%d cp=%02X j0=%02X j1=%02X swb=%02X ent=%02X "..
                        "rpm=%02X%02X tick=%d",
                        (fclap or 0) * 256 + mem:read_u8(0x0081),
                        mem:read_u8(0x008F), mem:read_u8(0x00AD), mem:read_u8(0x00AE),
                        mem:read_u8(0x00E4), mem:read_u8(0x00DA),
                        mem:read_u8(0x00A8), mem:read_u8(0x00A9),
                        mem:read_u8(0x00DD))
                end
                return data
            end)
    end
    frames = frames + 1

    -- Two schedules, and they are different on purpose. Console 1 stages and
    -- races on a 900-frame cycle; console 2 on a 700-frame one, offset.
    local period = DRIVE and 900 or 700
    local f = (frames + (DRIVE and 0 or 210)) % period
    local function lever(a) return f >= a and f < a + 8 end
    local function set(n, v) if fields[n] then fields[n]:set_value(v and 1 or 0) end end
    set("P1 Right", f >= 120 and f < 150)
    set("P1 Button 1", f >= 316)
    set("P1 Left", lever(320) or lever(380) or lever(450) or lever(530))
end)

_G._play_stop = emu.add_machine_stop_notifier(function()
    local ph = {}
    for k, v in pairs(phases) do ph[#ph+1] = string.format("%02X:%d", k, v) end
    table.sort(ph)
    print(string.format("PLAYDBG taps=%d samples=%d ent=$%02X tick=%d phases=%s",
        taps, #out, mem and mem:read_u8(0x00DA) or 0,
        mem and mem:read_u8(0x00DD) or 0, table.concat(ph, " ")))
    for _, l in ipairs(out) do print(l) end
end)
