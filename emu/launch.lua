-- launch.lua -- the fairness gate. Does a perfect launch still record a stock time?
--
-- This is the gate the whole port exists for. Combat has nothing like it: its
-- netplay is fair if both tanks obey the same inputs at the same tick, and that
-- is all. Dragster's netplay is fair only if the ELAPSED TIME is still the time
-- the 1980 cartridge would have recorded, because the elapsed time is the game.
--
-- Delay-based lockstep applies a press d ticks after it is made, so without the
-- display lead a perfect launch reaches the simulation eight frames late and
-- every run in the game costs about thirteen hundredths more than it should.
-- The lead shows the tree eight simulated frames early so the press lands at
-- sim-green instead.
--
-- What is measured is the LAUNCH DELTA: the number of simulated frames between
-- the countdown reaching zero and the car first moving. It isolates the launch
-- from everything after it, and it is the quantity the lead is supposed to
-- leave unchanged. The recorded time is reported beside it.
--
-- The driver plays as a person does, reacting only to what is on the screen:
-- the tree it sees is Countdown - DGLEAD, and it releases the gear lever the
-- moment that reaches green. It never reads the simulation's own countdown.
local mem
local fields = {}
local frames = 0
local greenfc, movedfc = nil, nil
local et, foul, done = nil, nil, false
local lead, netted = 0, false
local lastfc, fclap = nil, 0
local lastcd = nil
local phase, since = "stage", 0
local trace = os.getenv("LAUNCH_TRACE") == "1"
local tr = {}
local lastphase = nil
for _, port in pairs(manager.machine.ioport.ports) do
    for name, field in pairs(port.fields) do fields[name] = field end
end
local function tracep(cd, led, rpm)
    if not trace then return end
    -- only once a race is actually under way; the session takes a couple of
    -- hundred frames and filling the buffer with it tells you nothing
    if cd == 0 and phase == "stage" then return end
    if #tr >= 300 then return end
    if phase ~= lastphase or (since % 6 == 0) then
        lastphase = phase
        tr[#tr+1] = string.format("T fc=%d ph=%s cd=%02X led=%02X gear=%02X%02X rpm=%02X spd=%02X%02X msg=%02X",
            lastfc or 0, phase, cd, led,
            mem:read_u8(0x00CC), mem:read_u8(0x00CD), rpm,
            mem:read_u8(0x00C0), mem:read_u8(0x00C1), mem:read_u8(0x00D4))
    end
end

local function set(n, v) if fields[n] then fields[n]:set_value(v and 1 or 0) end end

local function simframe()
    local fc = mem:read_u8(0x0081)
    if lastfc ~= nil and fc < lastfc then fclap = fclap + 1 end
    lastfc = fc
    return fclap * 256 + fc
end

_G._ln_frame = emu.add_machine_frame_notifier(function()
    if not mem then mem = manager.machine.devices[":maincpu"].spaces["program"] end
    frames = frames + 1
    local sf = simframe()

    lead = mem:read_u8(0x00E2)
    if (mem:read_u8(0x00DA) & 0x02) ~= 0 then netted = true end

    local cd  = mem:read_u8(0x008D)          -- the SIMULATION's countdown
    local led = cd - lead                     -- what the PLAYER can see
    if led < 0 then led = 0 end

    -- sim-green, recorded from the simulation for the measurement only
    if lastcd ~= nil and lastcd ~= 0 and cd == 0 and greenfc == nil then
        greenfc = sf
    end
    lastcd = cd

    -- the car has moved
    if greenfc ~= nil and movedfc == nil and
       (mem:read_u8(0x00C0) ~= 0 or mem:read_u8(0x00C1) ~= 0) then
        movedfc = sf
    end

    -- the race is over: latch the time and whether it was fouled
    if greenfc ~= nil and not done and
       (mem:read_u8(0x00D2) ~= 0 or mem:read_u8(0x00BA) >= 0x60) then
        et = string.format("%02X.%02X", mem:read_u8(0x00B3), mem:read_u8(0x00B5))
        foul = mem:read_u8(0x00D4)
        done = true
    end

    -- ---- the driver, reacting only to what is on the screen ----
    --
    -- An explicit state machine, because Dragster's gear lever is pull-AND-
    -- RELEASE and the release IS the launch. A driver that decided whether to
    -- hold the lever from the revs alone never let go of it at green, and the
    -- car sat on the line with the engine screaming.
    local rpm = mem:read_u8(0x00A8)
    since = since + 1

    if done then
        set("P1 Left", false); set("P1 Button 1", false); set("P1 Right", false)
        return
    end

    if phase == "stage" then
        -- KEYED TO THE GAME, NOT TO THE EMULATOR'S FRAME COUNT. The session
        -- runs first and takes as long as it takes -- appkeys, a socket, a
        -- HELLO, and however long the other player takes to turn up -- so a
        -- press scheduled on emulator frame 60 is spent on the WAITING screen
        -- and the race never stages at all.
        -- Liveness measured from the SIM CLOCK, which both builds have. DGENT
        -- is the split build's and the 1980 cartridge does not have it, so a
        -- test on DGE_WARM never fires on stock and the race never stages.
        local live = sf >= 30
        if not live then since = 0 end
        set("P1 Right", live and since < 30)
        set("P1 Left", false); set("P1 Button 1", false)
        if live and since >= 30 and cd ~= 0 then phase, since = "count", 0 end

    elseif phase == "count" then
        set("P1 Right", false)
        -- The tree is still counting ON SCREEN. Pull the lever to arm the
        -- shift -- which is legal during the countdown; it is the RELEASE that
        -- fouls -- and bring the revs up short of the limit.
        set("P1 Left", led <= 0x40)
        -- A CONSERVATIVE REV THRESHOLD, because the throttle is an input and
        -- inputs take d ticks to land. Reading the revs live and letting go at
        -- $14 works on a console that answers immediately and blows the engine
        -- over a network, where the release arrives eight frames later and the
        -- needle has gone past the limit by then. A person learns to lift
        -- earlier; so does this.
        set("P1 Button 1", led <= 0x30 and rpm < 0x0A)
        if led == 0 then phase, since = "launch", 0 end

    elseif phase == "launch" then
        -- GREEN, as the PLAYER sees it: the lever goes. This is the press the
        -- whole port is arranged around.
        set("P1 Left", false)
        set("P1 Button 1", true)
        if since > 10 then phase, since = "drive", 0 end

    else  -- drive: shift up each time the revs climb, throttle off at the limit
        local shifting = (since % 16) < 6 and rpm >= 0x10
        set("P1 Left", shifting)
        set("P1 Button 1", rpm < 0x14)
    end
    tracep(cd, led, rpm)
end)

_G._ln_stop = emu.add_machine_stop_notifier(function()
    for _, l in ipairs(tr) do print(l) end
    print(string.format("LAUNCH lead=%d networked=%s green=%s moved=%s delta=%s et=%s foul=%s",
        lead, tostring(netted), tostring(greenfc), tostring(movedfc),
        (greenfc and movedfc) and tostring(movedfc - greenfc) or "?",
        tostring(et), foul and string.format("%02X", foul) or "?"))
end)
