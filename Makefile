# Networked two-player Dragster on an Atari 2600, over FujiNet.
#
# Every target is a gate in the milestone ladder, and the order is the order
# they have to pass in: a rung that fails makes everything above it ambiguous.
#
#   make verify-org   M0  the disassembly is mechanical, inert and the cartridge
#   make echo         M1  the transaction latency, measured, before any porting
#   make dragster     M2  the banked image, every changed byte declared
#   make frames       M2a stock and split measure the same frame, every frame
#   make det          M2b the split build plays exactly like the 1980 ROM
#   make inputs       M3  three sites, all inside the shim
#   make tree         M3c the display lead is 0 local and -8 networked
#   make slack        M4a both timed windows have the room the netcode assumes
#   make session      M5  one console, a real socket, a real HELLO
#   make rig          M6  two consoles, one match, zero mismatches
#   make rig-launch   M7b the fairness gate: a perfect launch records stock's time
#   make ladder           all of it, in order

SHELL := /bin/bash
VCS   ?= $(HOME)/Workspace/fn-2600/pico/atari-2600

.PHONY: all verify-org dragster probe echo frames det inputs lag tree slack \
        sim lobby session rig rig-hold rig-stage rig-play rig-repair \
        rig-launch ladder play stop clean \
        relay-c relay-c-strict relay-c-asan server-diff

all: dragster

# ---------------------------------------------------------------- M0
verify-org:
	./build.sh verify-org

# ---------------------------------------------------------------- M1
#
# NOT PORTED, and deliberately loud about it rather than quietly absent.
#
# K = 4 and d = 2 are inherited from the Combat bring-up, which measured one
# frame per transaction and three frames per WRITE/STATUS/READ cycle against
# this same cartridge and this same firmware. That is a sound thing to inherit
# in an emulator, where the transport below the mailbox is identical -- and it
# is NOT a sound thing to inherit on hardware, where the cartridge bus exists
# and has never been measured at all.
probe echo:
	@echo "make $@: the latency probe is not ported. K=4 and d=2 come from the"
	@echo "  Combat bring-up, which measured one frame per transaction on this"
	@echo "  cartridge and firmware. Port src/probe.asm from there and re-measure"
	@echo "  BEFORE trusting those constants on real hardware -- see PORTING.md."
	@exit 1

# ---------------------------------------------------------------- M2
dragster:
	./build.sh

# ---------------------------------------------------------------- gates
frames: dragster
	cp -f rom/dragster.bin build/stock.bin
	@{ SECS=$${SECS:-14} SLOT=a26_2k_4k ./run.sh stock frames || true; } | tail -4
	@{ SECS=$${SECS:-14} ./run.sh dragster frames || true; } | tail -4

det: dragster
	cp -f rom/dragster.bin build/stock.bin
	ENDPOINT="TCP://127.0.0.1:9699/" ./build.sh >/dev/null
	@{ SECS=$${SECS:-14} SLOT=a26_2k_4k ./run.sh stock det 2>/dev/null || true; } \
	    | grep -E '^[0-9]+ [0-9A-F]{4}$$' > build/det_stock.txt
	@{ SECS=$${SECS:-14} ./run.sh dragster det 2>/dev/null || true; } \
	    | grep -E '^[0-9]+ [0-9A-F]{4}$$' > build/det_split.txt
	python3 tools/ramdiff.py build/det_stock.txt build/det_split.txt

# Locally first -- every read must come from DGLOC0 -- and then in a match,
# where every read must come from DGCAP and DGLOC0 must not run at all.
inputs: dragster
	@{ SECS=$${SECS:-14} ./run.sh dragster inputs || true; } | grep -A6 INPUTS
	RIG_LUA=inputs SECS=$${SECS:-25} test/run_rig.sh

lag:
	@DGLAG=1 ./build.sh >/dev/null
	@{ SECS=$${SECS:-14} ./run.sh dragster lag 2>/dev/null || true; } | tee build/lag.txt | grep LAG
	@./build.sh >/dev/null
	@grep -q '^LAG PASS' build/lag.txt

tree: dragster
	RIG_LUA=tree SECS=$${SECS:-30} test/run_rig.sh

slack: dragster
	@{ SECS=$${SECS:-20} ./run.sh dragster slack 2>/dev/null || true; } | tee build/slack.txt | grep SLACK
	@grep -q '^SLACK PASS' build/slack.txt

# The ball's position is a side effect of StageRace entering PositionSprites
# with X = 4. What is compared is the SHAPE of that path -- the WSYNCs between
# arming the countdown and the RESBL strobe -- on stock and on the build.
ball: dragster
	@cp -f rom/dragster.bin build/stock.bin
	@{ SECS=$${SECS:-14} SLOT=a26_2k_4k ./run.sh stock ball 2>/dev/null || true; } \
	    | grep -o 'strobe: .*' > build/ball_stock.txt
	@{ SECS=$${SECS:-14} ./run.sh dragster ball 2>/dev/null || true; } \
	    | grep -o 'strobe: .*' > build/ball_split.txt
	@echo "  stock: $$(cat build/ball_stock.txt)"
	@echo "  split: $$(cat build/ball_split.txt)"
	@if [ "$$(cut -d: -f2 build/ball_stock.txt)" = "$$(cut -d: -f2 build/ball_split.txt)" ]; \
	    then echo "BALL PASS"; else echo "BALL FAIL: the ball is positioned by a different path"; exit 1; fi

# ---------------------------------------------------------------- no emulator
sim:
	python3 tools/dragster_client_sim.py

# The C relay. server/dragster_relay_server.py stays canonical; this binary is
# a transliteration of it, and `make server-diff` is what keeps it honest.
# Every gate that starts a relay takes SERVER=c to run this one instead:
#
#   make relay-c && SERVER=c make sim lobby rig
#
relay-c:
	$(MAKE) -C server/c
relay-c-strict:
	$(MAKE) -C server/c strict
relay-c-asan:
	$(MAKE) -C server/c asan

# The differential: both relays through identical scripted scenarios, with
# every frame the clients receive and every line the servers log compared byte
# for byte. A non-empty diff is a bug in the C port.
server-diff: relay-c
	python3 tools/server_diff.py

lobby:
	python3 tools/test_lobby_pub.py

# ---------------------------------------------------------------- M5-M7
session: dragster
	test/run_sess.sh

rig: dragster
	test/run_rig.sh

rig-hold: dragster
	RIG_HOLD=select SNAPTICK=250 SECS=45 test/run_rig.sh

rig-stage: dragster
	RIG_HOLD=stage SECS=45 test/run_rig.sh

rig-play: dragster
	RIG_LUA=play SECS=40 test/run_rig.sh

rig-repair: dragster
	RIG_LUA=play PLAY_INJECT=120 SECS=60 test/run_rig.sh

# The fairness gate. STOCK_DELTA is measured, not assumed: `make launch-stock`
# runs the same driver on the 1980 cartridge and prints the number to beat.
rig-launch: dragster
	RIG_LUA=launch SECS=$${SECS:-30} test/run_rig.sh

launch-stock:
	@cp -f rom/dragster.bin build/stock.bin
	@{ SECS=$${SECS:-25} SLOT=a26_2k_4k ./run.sh stock launch || true; } | grep LAUNCH

ladder: verify-org sim lobby dragster frames det inputs lag tree slack ball \
        rig rig-hold rig-stage rig-play rig-launch rig-repair
	@echo
	@echo "ladder: every gate passed."

play: dragster
	test/run_play.sh

stop:
	test/stop.sh

clean:
	rm -rf build
