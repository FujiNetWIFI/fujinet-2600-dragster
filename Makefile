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
        rig-launch ladder play stop clean

all: dragster

# ---------------------------------------------------------------- M0
verify-org:
	./build.sh verify-org

# ---------------------------------------------------------------- M1
probe:
	./build.sh probe

echo: probe
	test/run_probe.sh

# ---------------------------------------------------------------- M2
dragster:
	./build.sh

# ---------------------------------------------------------------- gates
frames: dragster
	SECS=$${SECS:-14} test/run_gate.sh frames

det: dragster
	SECS=$${SECS:-22} DET_QUIET=$${DET_QUIET:-1} test/run_gate.sh det

inputs: dragster
	SECS=$${SECS:-14} test/run_gate.sh inputs

lag:
	DGLAG=1 ./build.sh && SECS=$${SECS:-14} test/run_gate.sh lag; s=$$?; ./build.sh; exit $$s

tree: dragster
	SECS=$${SECS:-20} test/run_gate.sh tree

slack: dragster
	SECS=$${SECS:-20} test/run_gate.sh slack

ball: dragster
	SECS=$${SECS:-14} test/run_gate.sh ball

# ---------------------------------------------------------------- no emulator
sim:
	python3 tools/dragster_client_sim.py

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

rig-launch: dragster
	RIG_LUA=launch SECS=45 test/run_rig.sh

ladder: verify-org sim lobby dragster frames det inputs tree slack ball \
        rig rig-hold rig-stage rig-play rig-launch rig-repair
	@echo
	@echo "ladder: every gate passed."

play: dragster
	test/run_play.sh

stop:
	test/stop.sh

clean:
	rm -rf build
