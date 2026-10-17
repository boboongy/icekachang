#!/bin/sh
# Rebuild models/textures in Blender, reimport in Godot, save screenshots of both views.
# Usage: sh tools/rebuild.sh   (from the project root)
set -e
BLENDER="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
GODOT=/c/Godot/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe
# --preview also writes Blender layout renders of each camera view to build/preview_*.png
"$BLENDER" -b --factory-startup --python tools/blender/build_stall.py -- --preview 2>&1 | grep -E "BUILD_OK|Error|Traceback" || true
# placeholder music and sounds (assets/audio/*.wav); only with AUDIO=1, the files rarely change
if [ "$AUDIO" = "1" ]; then
  /c/Users/bobo/AppData/Local/Programs/Python/Python312/python.exe tools/audio/make_sounds.py
fi
# pixel font (assets/fonts/pixel*.fnt/png), own 5x7 glyphs painted by script
/c/Users/bobo/AppData/Local/Programs/Python/Python312/python.exe tools/font/make_font.py
"$GODOT" --headless --path . --import > build/import_log.txt 2>&1 || true
grep -iE "error" build/import_log.txt || true
# headless making-view self-test (no window)
"$GODOT" --headless --path . -- --selftest 2>&1 | grep -E "FAIL|SELFTEST|SCRIPT ERROR" || true
# headless customers end-to-end test (orders, pay, queue, patience)
"$GODOT" --headless --path . -- --custtest 2>&1 | grep -E "FAIL|SELFTEST|CUSTTEST|SCRIPT ERROR" || true
# headless day loop, shop and save test: two runs on a test save (restart restores it)
"$GODOT" --headless --path . -- --daytest --savefile user://save_test.json --fresh 2>&1 | grep -E "FAIL|SELFTEST|SCRIPT ERROR" || true
"$GODOT" --headless --path . -- --daycheck --savefile user://save_test.json 2>&1 | grep -E "FAIL|SELFTEST|SCRIPT ERROR" || true
# headless main menu, tutorial (new player follows only the arrow), pause and settings; run 2 = after a restart
"$GODOT" --headless --path . -- --tuttest --savefile user://save_tut.json --fresh 2>&1 | grep -E "FAIL|SELFTEST|SCRIPT ERROR" || true
"$GODOT" --headless --path . -- --tutcheck --savefile user://save_tut.json 2>&1 | grep -E "FAIL|SELFTEST|SCRIPT ERROR" || true
# Screenshots open a Godot window (moved off-screen, but the owner still sees it): only with
# the owner's OK. Run with SHOTS=1.
if [ "$SHOTS" = "1" ]; then
  "$GODOT" --path . --position -4000,-4000 -- --shot 2>&1 | grep -E "PERF|ERROR|SCRIPT" || true
fi
