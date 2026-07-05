#!/bin/bash
# Serve o export web do jogo e abre-o no browser.
# (Exports web do Godot não funcionam com file:// — precisam de HTTP.)
PORT=8060
DIR="$(dirname "$0")/export/web"

if ! curl -s -o /dev/null "http://localhost:$PORT/index.html"; then
	(cd "$DIR" && nohup python3 -m http.server "$PORT" >/dev/null 2>&1 &)
	sleep 1
fi
xdg-open "http://localhost:$PORT/index.html"
