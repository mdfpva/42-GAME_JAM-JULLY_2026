# Eternal Chase

[![Play on itch.io](https://img.shields.io/badge/itch.io-Play%20in%20your%20browser-fa5c5c?logo=itchdotio&logoColor=white)](https://mdfpva.itch.io/eternal-chase)
![Godot](https://img.shields.io/badge/Godot-4.7-478cbf?logo=godotengine&logoColor=white)
![GDScript](https://img.shields.io/badge/GDScript-100%25%20of%20gameplay%20code-355570)
![42 Game Jam](https://img.shields.io/badge/42%20Game%20Jam-July%202026-black)

A fast 2D endless-runner platformer made for the **42 Game Jam (July 2026)**.
Run as far as you can through procedurally generated terrain, stomp and shoot enemies,
chain combos, collect coins, and survive the bosses.

**▶ Play it now on itch.io: [Eternal Chase by mdfpva](https://mdfpva.itch.io/eternal-chase)**

<!-- TODO: drop a gameplay GIF or screenshot here, e.g.
![Gameplay](assets/gameplay.gif)
-->

## Features

- **Procedural terrain with guaranteed reachability** — the generator mirrors the
  player's real jump physics (with a safety margin for human timing), so every gap
  it creates is provably jumpable
- **4 biomes** rotating every 500 m — Plains, Ice, Cave and Night, each with its own
  palette and clear color
- **Boss fights every 1500 m** — two boss types: a shooter and a charger that
  telegraphs before dashing
- **10 temporary power-ups** — Flight, Instant Kill, Coin Magnet, Rapid Fire,
  Super Jump, Shield, Slow Motion, Double Speed, Double Coins, Double Kills
- **Tight platforming feel** — coyote time, jump buffering, variable jump height,
  squash & stretch, particle trails and screen shake
- **Combo system** up to ×9 for chained kills
- **3 random missions per run** with score bonuses, plus 6 achievements
- **Meta-progression** — coins persist between runs and buy permanent upgrades
  (speed, jump, buff duration) and cosmetic trails
- **Ghost replay** of your best run racing alongside you
- **Daily mode** — one shared seed per day
- **Local top-5 scoreboard** with high-score tracking
- **100% procedural audio** — the music is a technopop cover of *"Eternal Chase"*
  by **bedbyeleven** (used with the band's permission), synthesized sample-by-sample
  at runtime in GDScript, and every sound effect is generated in code at startup.
  No audio asset files are used by the game.

## Controls

| Action | Keyboard          | Gamepad             |
| ------ | ----------------- | ------------------- |
| Move   | ← → arrows        | D-pad / left stick  |
| Jump   | Space / Enter     | A                   |
| Shoot  | X                 | X / Square          |
| Pause  | Esc / P           | Start               |

During the Flight power-up, ↑ ↓ also steer vertically. Release jump early for a
shorter hop.

## Run it locally

**Web build (no Godot required):**

```bash
./jogar_web.sh
```

This serves the prebuilt web export at `http://localhost:8060` and opens it in your
browser. (Godot web exports need an HTTP server — opening `index.html` via `file://`
won't work.)

**From source:**

1. Install [Godot 4.7+](https://godotengine.org/)
2. Open `project.godot` in the editor
3. Press <kbd>F5</kbd>

## Project structure

```
scenes/       Game scenes (Player, Enemy, Boss, Coin, platforms, Main…)
scripts/      All gameplay logic in GDScript (~2000 lines)
export/web/   Prebuilt HTML5 export (the build published on itch.io)
assets/       Minimal art — visuals are drawn from tinted primitives
```

## Credits

- **Code, design & audio synthesis** — Miguel ([@mdfpva](https://github.com/mdfpva)), student at 42 Porto
- **Original song** — *"Eternal Chase"* by **bedbyeleven**; the in-game soundtrack is
  a procedural cover used with the band's permission
- **Engine** — [Godot 4.7](https://godotengine.org/)
