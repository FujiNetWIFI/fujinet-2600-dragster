-- slack.lua -- how many cycles does the netcode actually have?
--
-- Dragster has TWO timed waits and they are not comparable. The overscan timer
-- at $F221 is armed with $21 -- 2112 cycles -- and only the audio engine stands
-- in front of it; the vertical blank timer at $F2C1 is armed with $19 -- 1600 --
-- and the whole game logic stands in front of THAT, including a tach-bar loop
-- that is 589 cycles on its own.
--
-- So the hook is the overscan and the vertical blank is the reserve. This
-- reports both: the first INTIM the netcode sees each frame, and the INTIM the
-- kernel's own wait sees. The second number is the early warning for anything a
-- later change puts in the logic chain -- it will shrink long before it breaks
-- anything, and this is where that shows up.
local mem
local os_hist, vb_hist = {}, {}
local os_min, vb_min = 255, 255
local frames = 0
local pending = nil
local fields = {}
for _, port in pairs(manager.machine.ioport.ports) do
    for name, field in pairs(port.fields) do fields[name] = field end
end

local function bump(t, v) t[v] = (t[v] or 0) + 1 end

_G._sl_frame = emu.add_machine_frame_notifier(function()
    if not mem then
        mem = manager.machine.devices[":maincpu"].spaces["program"]
        -- Which wait an INTIM read belongs to is decided by WHICH TIMER WAS
        -- ARMED LAST, not by the program counter: the same instruction is in
        -- both banks at different addresses and the kernel bank's copy moves
        -- with the region.
        _G._sl_arm = mem:install_write_tap(0x0296, 0x0296, "sl_arm",
            function(offset, data, mask)
                -- Arming a timer opens a window; the FIRST INTIM read after it
                -- is the slack that window really had. Every read after that is
                -- the poll loop counting down, and averaging those in reports
                -- the histogram of a countdown rather than of the budget.
                pending = (data & 0xFF)
                return data
            end)
        _G._sl_rd = mem:install_read_tap(0x0284, 0x0284, "sl_intim",
            function(offset, data, mask)
                local v = data & 0xFF
                if pending == 0x21 then
                    bump(os_hist, v)
                    if v < os_min then os_min = v end
                elseif pending == 0x19 then
                    bump(vb_hist, v)
                    if v < vb_min then vb_min = v end
                end
                pending = nil
                return data
            end)
    end
    frames = frames + 1
    -- THE WORST CASE IS A RACE, NOT AN IDLE SCREEN. The tight window is the
    -- vertical blank, and what fills it is the game logic -- the tach-bar loop
    -- at $F4D1 is nineteen iterations of thirty-one cycles on its own, and it
    -- only runs while a car is revving. Measuring an attract screen reports a
    -- budget nobody will ever have.
    local f = frames % 900
    local function set(n, v) if fields[n] then fields[n]:set_value(v and 1 or 0) end end
    local function lever(a) return f >= a and f < a + 8 end
    set("P1 Right", f >= 120 and f < 150)
    set("P1 Button 1", f >= 316)
    set("P1 Left", lever(320) or lever(380) or lever(450) or lever(530))
end)

_G._sl_stop = emu.add_machine_stop_notifier(function()
    local function top(t, n)
        local ks = {}
        for k in pairs(t) do ks[#ks + 1] = k end
        table.sort(ks, function(a, b) return t[a] > t[b] end)
        local o = {}
        for i = 1, math.min(n, #ks) do o[#o + 1] = string.format("%d:%d", ks[i], t[ks[i]]) end
        return table.concat(o, " ")
    end
    print(string.format("SLACK frames=%d", frames))
    print(string.format("SLACK overscan  worst INTIM %d (%d cycles), common %s",
                        os_min, os_min * 64, top(os_hist, 5)))
    print(string.format("SLACK vblank    worst INTIM %d (%d cycles), common %s",
                        vb_min, vb_min * 64, top(vb_hist, 5)))

    -- THE HOOK'S WINDOW must still hold a micro-step. DGGATE is 8, which
    -- guarantees 7 x 64 = 448 cycles against a worst step of about 310, and the
    -- loop re-reads INTIM before every step -- so this failing does not mean a
    -- broken frame, it means the netcode has stopped getting turns.
    local OSFLOOR = 8
    -- THE RESERVE is the early warning. Nothing steps here and nothing is meant
    -- to; what this number does is shrink, quietly, when something is added to
    -- the logic chain -- and it will shrink for a long time before a frame
    -- actually grows a scanline and `make frames` notices.
    local VBFLOOR = 3
    local fails = {}
    if os_min < OSFLOOR then
        fails[#fails+1] = string.format(
            "the overscan window fell to %d, below DGGATE (%d): the network "..
            "machine is not being stepped", os_min, OSFLOOR)
    end
    if vb_min < VBFLOOR then
        fails[#fails+1] = string.format(
            "the vertical blank fell to %d (%d cycles), below the floor of %d "..
            "(%d cycles) -- something in the logic chain got longer",
            vb_min, vb_min * 64, VBFLOOR, VBFLOOR * 64)
    end
    for _, f in ipairs(fails) do print("SLACK FAIL: " .. f) end
    print(#fails == 0 and "SLACK PASS" or "SLACK FAIL")
end)
