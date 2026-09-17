-- smoke.lua -- does the banked image boot and run Dragster's frame loop?
local mem, frames = nil, 0
local seen = {}
emu.add_machine_frame_notifier(function()
    if not mem then
        mem = manager.machine.devices[":maincpu"].spaces["program"]
    end
    frames = frames + 1
    if frames % 60 == 0 then
        local ent  = mem:read_u8(0x00DA)
        local cd   = mem:read_u8(0x008D)
        local fc   = mem:read_u8(0x0081)
        local pos0 = mem:read_u8(0x00BA)
        local var  = mem:read_u8(0x0080)
        print(string.format("frame %4d  DGENT=%02X Countdown=%02X FrameCnt=%02X TrackPos=%02X GameVar=%02X",
              frames, ent, cd, fc, pos0, var))
        seen[fc] = true
    end
end)
emu.register_stop(function()
    local n = 0
    for _ in pairs(seen) do n = n + 1 end
    print(string.format("smoke: %d frames, %d distinct FrameCnt samples", frames, n))
end)
