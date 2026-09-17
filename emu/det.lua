-- det.lua -- per-simulated-frame state checksum, for `make det`.
--
-- The claim under test is that the banked, patched build plays EXACTLY like the
-- 1980 cartridge. So the comparison has to be of the simulation and not of the
-- furniture, and it has to be sampled at the same instant in both builds.
--
-- THE SAMPLE POINT IS A WRITE TAP, NOT THE FRAME NOTIFIER. MAME's frame
-- boundary has no relationship to where Dragster is in its own frame, so a
-- notifier lands mid-kernel at an arbitrary scanline and the sprite pointers it
-- reads are whichever lane happened to be drawn last. Dragster arms TIM64T
-- twice a frame -- $21 for the overscan at $F221 and $19 for the vertical blank
-- at $F2C1 -- so tapping that register and filtering on $21 gives one sample per
-- frame, at a fixed instruction, in both builds.
--
-- THE INDEX IS FrameCnt, WITH ITS LAP. That is Dragster's own sim clock, so two
-- builds are compared at the same simulated frame however many frames either
-- spent booting. It is also IN the checksum, which is what stops a constant
-- offset in it from reading as agreement: the indices would line up and the
-- values would not.
--
-- $D8/$D9 are excluded. They are the kernel's scratch, written after this
-- samples, and a checksum that covers a cell whose value depends on where the
-- raster was reports differences it cannot explain.
local mem, tap
local prev, lap = nil, 0
local out = {}
local quiet = os.getenv("DET_QUIET") == "1"
local fields = {}

for _, port in pairs(manager.machine.ioport.ports) do
    for name, field in pairs(port.fields) do fields[name] = field end
end

local function sample()
    -- A ROTATE-and-add, not a shift-and-add. A plain `sum*2 + byte` truncated to
    -- sixteen bits throws the early bytes off the top: the first version of this
    -- reported a constant $000C across a whole run, because only the last
    -- sixteen cells could still reach the result.
    local sum = 0
    for a = 0x80, 0xD7 do
        sum = ((sum << 1) | (sum >> 15)) & 0xFFFF
        sum = (sum + mem:read_u8(a)) & 0xFFFF
    end
    local fc = mem:read_u8(0x0081)
    if prev ~= nil and fc < prev then lap = lap + 1 end
    prev = fc
    out[#out+1] = string.format("%d %04X", lap * 256 + fc, sum)
end

local function hold()
    if fields["P1 Right"] then fields["P1 Right"]:set_value(1) end
    if fields["P1 Button 1"] then fields["P1 Button 1"]:set_value(1) end
end
hold()

emu.add_machine_frame_notifier(function()
    if not mem then
        mem = manager.machine.devices[":maincpu"].spaces["program"]
        tap = mem:install_write_tap(0x0296, 0x0296, "det_t64",
            function(offset, data, mask)
                if (data & 0xFF) == 0x21 then sample() end
                return data
            end)
    end
    -- THE INPUT NEVER TRANSITIONS. Right and the button are held from before
    -- the first instruction and never released, which is the only way two
    -- builds can be guaranteed to see the same input at the same SIMULATED
    -- frame: the two read the console at different points in the frame -- stock
    -- at $F2C8 in the vertical blank, the split build at $F285 in the overscan
    -- -- so an edge scheduled by the harness lands one frame apart in the two,
    -- and from there the cars launch a frame apart and never agree again.
    --
    -- It is not a quiet run. Right stages the race on the first frame; with the
    -- throttle held through the countdown the engine revs, redlines and blows,
    -- and the wreck sprite and the message index change with it. Held level
    -- rather than pulsed, the whole sequence is a pure function of the sim
    -- clock -- which is what the gate needs it to be.
    hold()
end)

emu.register_stop(function()
    for _, l in ipairs(out) do print(l) end
end)
