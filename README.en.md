[🇧🇷 Português](README.md) | **🇺🇸 English**

# Terra Chamando

*(Portuguese for "Earth Calling")*

A cooperative 2D game built in Godot for the NASA Space Apps Challenge 2026, for the **Space Mission Design Game** challenge. The team plans a space mission on Earth, carries out the voyage inside the spacecraft and, at the end, receives a report showing what each planning decision caused in space.

Up to 4 players, over LAN or the internet. It can also be played solo.

**Play in the browser:** https://thallesgsrv.github.io/nasa-space-apps/

## The challenge

The Space Mission Design Game challenge asks for a game in which the user plans and carries out their own space mission. Here, planning follows NASA's nine Concept Maturity Levels (CML), and what the team decides at each level becomes the real flight parameters, rather than staying a mere opening menu.

## The idea

In the opening cutscene, the scientist at Earth Control checks the reactor, propulsion and communications with the spacecraft. The crew replies that everything is ready, and both sides agree on what holds for the whole game: the ship performs the maneuvers, Earth makes the predictions.

Before that, though, the mission has to exist. The game starts with planning and goes through the nine Concept Maturity Levels (CML), from the napkin sketch to the critical design review. Each choice costs credits and changes the ship. After launch, those choices come back as consequences: the rocket limits the mass, a risk nobody paid to mitigate becomes more likely, the spare part saves the reactor in a thermal failure, and the quality of communications decides whether the base can guide the reentry.

The key point is that all of this uses the same mission state (`MissionState`). Planning writes parameters that the flight really reads, the scientist has their own work on Earth, and NASA data shows up in events with a badge saying whether it is real or simulated.

## How the mission unfolds

1. **Planning.** After the cutscene and the tutorial, the player chooses between planning the mission (CML 1 to 9) or going with the default plan.
2. **Crew.** In multiplayer, each player takes a role in the lobby and can swap to a free role.
3. **Launch.** The CDR authorizes, the launch video plays and the crew boards. The scientist stays on Earth.
4. **Operation.** Survival (food, water, sleep, health, reactor core), the bionutrients mission, and the trip to the Moon, Mars or Jupiter.
5. **Events.** Every 30 seconds there is a draw among communication interference, an asteroid and a reactor failure. The risks accepted at CML 7 weigh on the draw. There is also the solar storm.
6. **Return.** Systems checklist, return window and reentry angle.
7. **Report.** Final grade, event timeline and the causes tied back to planning.

### The nine CMLs

| CML | Decision |
|---|---|
| 1 | Mission objective, decided by vote (bionutrients, cislunar radiation or optical communication) |
| 2 | Small, medium or heavy rocket: cost versus mass capacity |
| 3 | Power source and spacecraft structure |
| 4 | Instrument kit: science, spare parts and communication bandwidth |
| 5 | Reserve policy: schedule slack versus credits |
| 6 | Design inconsistencies: fix them by paying or accept the risk |
| 7 | Which of the three biggest risks to mitigate (12 credits each) |
| 8 | PDR: adjust the requirements that failed or approve with a waiver |
| 9 | CDR: authorize the launch |

CMLs 2 to 9 are split into four pairs, randomly assigned among the connected players, so each person decides one part of the design. Credits start at 100 and never go negative.

## Roles

The intended setup is two astronauts, one engineer and one scientist on Earth.

| Role | Where | What they do |
|---|---|---|
| Commander astronaut (host) | Spacecraft | Plays the mission and runs the whole simulation |
| Base / scientist | Earth | Analyzes samples, predicts hazards, decides the solar alert, calculates asteroid impact |
| Flight engineer | Spacecraft | Cools the reactor core and activates the shields |
| Astronaut 2 | Spacecraft | Same actions as the engineer |

When playing solo, the `1` key switches between the astronaut and the scientist.

## Mechanics

**Survival.** Food, water, sleep, health and core temperature. A core at 100% for 12 seconds blows up the ship. The ship has a cafeteria, a ration and water printer, a 20-slot locker, a 6-slot backpack, a dormitory and a first-aid station.

**Missions.**
- *Bionutrients:* pick up the fungus culture, heat it, centrifuge it and send it to the base through the capsule. The base analyzes the sample (Petri dish and microscope) and gives a verdict, which influences the next mission.
- *Voyage:* choose the route at the command chair. Time limit, energy, fuel and mass come from the design.
- *Solar storm (CME):* the base reads the terminal (X-ray flux and angle), checks the safe-limit manual and decides whether to alert or ignore. With an alert, the ship has 20 seconds to turn on the shields in the reactor room. A false alarm costs energy and time. Ignoring a real storm costs health and reverses the controls for a few seconds.
- *Return to Earth:* systems check, return window and reentry.

**Voyage events.**
- *Communication:* a blackout whose duration depends on the design's communications.
- *Asteroid:* the ship only notices it about 12 seconds before impact. The base calculates the time and the ship decides whether to maneuver, which costs fuel, energy and time.
- *Reactor:* a valve puzzle to stabilize it. A spare part cushions the overheating.

**Origin badges.** Every event in the report is marked as `REAL` (real scientific record), `RISCO` (real phenomenon with simulated occurrence; "risk") or `FICT` (challenge created for the game). No fictional event is presented as NASA data.

**Report.** The grade (A to E) combines science (30%), ship (20%), decisions (15%), efficiency (10%), budget (10%) and, in multiplayer, cooperation with the base (15%). The report is saved to `user://last_report.json`.

**Minigames.** Petri dish, microscope, reagent preparation by proportion, formula board, asteroid dodging with the ship, and reactor valves.

The game is available in Portuguese and English, has music for each room, an optional tutorial and, in the Petri dish, the color name is shown for players who cannot distinguish colors.

## NASA data

Currently only the DONKI API (solar flares) is integrated. A Python script queries DONKI on the server and generates a static JSON, which the game reads to set the intensity of the solar storm. The intensity comes from the real record; the direction of the ejection is always simulated, and the on-screen badge says so.

The game looks for the feed in this order: `NASA_FEED_URL` (environment variable or the `nasa/feed_url` setting), the cache at `user://nasa_feed.json` and, lastly, `data/space_events.json`. The game never calls `api.nasa.gov` directly, so the key does not ship with the build.

In the browser build there are no environment variables, so the feed address must be in the project's `nasa/feed_url` setting, and the server delivering the JSON must allow CORS (GitHub Pages usually does). While the feed is not configured, the published build uses the local file.

```bash
NASA_API_KEY=your_key python3 tools/nasa_feed_proxy.py output/space_events.json 30
```

Without a key, the script uses `DEMO_KEY`, which has a low, shared limit. The `data/space_events.json` file has only three historical flares (2003, 2017 and 2024) filled in by hand, so check dates and classes in DONKI before presenting them as official data.

EONET and NeoWs are not integrated yet. The asteroid event is randomly drawn and marked as `RISCO`.

## Technologies

- Godot 4 (2D, Forward+ renderer) and GDScript, about 11 thousand lines
- Networking with `ENetMultiplayerPeer` (LAN) and `WebSocketMultiplayerPeer` (internet and browser)
- Python 3, standard library only, for the DONKI feed
- Videos in Ogg Theora, audio in MP3 and WAV, PixelOperator8 font
- User interface built in code
- Godot's own headless tests and a shell script for networking

## Rooms in HTML and CSS

The `rooms_html/` folder has the seven ship rooms drawn with HTML and CSS only, based on the real collisions, doors and interaction zones of the `.tscn` scenes (same positions and 3:2 proportion as the game). Open `rooms_html/index.html` in the browser: the doors lead from one room to another and the stage stays centered at any window size.

## Code organization

The game is made of autoloads that share state. The host is the authority and clients receive a mirror.

```
scripts/
  game_state.gd      needs, inventory, capsule
  mission_state.gd   CML 1-9, parameters, risks, log and report
  missions.gd        mission steps
  voyage.gd          voyage, events, reactor, asteroid
  solar.gd           solar storm
  nasa_feed.gd       solar events with cache and fallback
  interactions.gd    what each ship object does
  net.gd             LAN, WebSocket, roles and RPCs
  lobby.gd, ghost.gd lobby and the other players' "ghosts"
  lang.gd            Portuguese and English
  audio.gd           music and effects
  ui/                HUD, dialogs, screens and minigames
scenes/              menu, cutscene, game, rooms
data/                offline feed fallback
tools/               NASA feed and network test
tests/               automated tests
```

On the network, the host runs the simulation and sends a mirror of the state about 10 times per second. Client requests go through `Net.call_host`, which only runs if the player's role allows it (`Net.CALL_ROLES`). For example, only the scientist calls `Solar.decide`.

The data path is: `MissionState.params` feeds `Voyage`, `Solar` and the event draw, which write to `MissionState.log`, from which the report is produced.

## How to run

Use Godot 4.6 or newer, the standard version (not .NET). `project.godot` is marked as 4.7 and the tests below were run on 4.6.

```bash
git clone https://github.com/thallesgsrv/nasa-space-apps
cd nasa-space-apps
godot --headless --import    # first time only
godot --path .
```

| Key | Action |
|---|---|
| WASD or arrows | Move |
| F, Enter or Space | Interact and confirm |
| I or Tab | Backpack |
| M or J | Mission menu |
| V | Review the current objective |
| 1 | Switch between astronaut and scientist |
| Esc | Cancel or close |

### Export

`export_presets.cfg` has the Web (no threads, does not require COOP/COEP headers) and Linux presets. With the export templates installed:

```bash
mkdir -p build/web build/linux
godot --headless --export-release "Web" build/web/index.html
godot --headless --export-release "Linux (host/servidor)" build/linux/nasa-space-apps.x86_64
```

To test the Web build locally, run `python -m http.server 8000` inside `build/web`. Opening `index.html` with a double click does not work.

## Multiplayer and how to put it online

On LAN the game uses ENet: UDP 24565 for the game and UDP 24566 for room discovery. Over the internet it uses WebSocket on TCP port 24567. In either case the host is the desktop executable, and the browser can only join rooms that have already been created (by address, with no automatic discovery).

The playable version is published on GitHub Pages (link at the top). To publish again, export the Web preset and upload the `build/web` folder to GitHub Pages, itch.io, Netlify or Cloudflare Pages.

The catch is HTTPS: an HTTPS page blocks `ws://` connections. The game client accepts `wss://`, so there are three paths:

- TLS tunnel. The host runs `cloudflared tunnel --url http://localhost:24567` and the others join with `wss://tunnel-address`. It is the simplest and does not require opening a port on the router.
- Your own server with Caddy or nginx handling TLS in front of port 24567.
- Local network over HTTP: the host serves `build/web` with `python -m http.server 8000` and players use `http://IP:8000` and `ws://IP:24567`. Open the ports in the firewall and check that the Wi-Fi does not isolate clients.

Solo mode works on any static hosting.

## Tests

```bash
godot --headless res://tests/run_tests.tscn
bash tools/run_net_tests.sh /path/to/godot ws
```

In the last run (Godot 4.6, commit `8c0a0a5`), the rules suite finished with 303 checks and 0 failures. The network test, with 4 players and a fifth one refused, and the team planning test also passed. The suite covers loading all scenes, state reset, game over, the bionutrients flow, the voyage with each event, the reactor, the solar storm with and without alert, the NASA feed and the effect of planning on the flight.

At the end of the run, Godot prints "RID allocations leaked at exit" warnings. This happens when headless mode shuts down and does not indicate a failure.

## What is already done

- Planning with the nine CMLs, with costs, budget validation, inconsistencies at CML 6, requirements at the PDR, a vote at CML 1 and the split of the others among the players.
- Planning that really changes the flight (mass, fuel, consumption, time, risk, parts and communications), verified by tests.
- LAN and WebSocket multiplayer with role-based permissions, state mirroring and an integration test.
- Scientist's laboratory with sample analysis, formula board, reagent bench and base panel (ship monitor, hazard forecast, asteroid calculation).
- Solar storm with six possible outcomes, depending on the alert and the shields.
- Three voyage events with different mechanics.
- Return to Earth and a three-page post-mission report.
- Six rooms on the ship, plus the laboratory on Earth, each with music.
- Survival, inventory, locker and capsule to Earth.
- Portuguese and English translation (about 770 texts).

## What is half-done

- **Classes.** The lobby lets players swap roles, but the flight engineer and astronaut 2 have exactly the same permissions. Missing are a maintenance and diagnostics mechanic exclusive to the engineer, and a class selection screen at the start.
- **CML 1 objective.** The vote is recorded and appears in the report, but it does not change the mission. Choosing cislunar radiation or optical communication does not create any corresponding experiment, and the game always runs the bionutrients mission.
- **Tasks.** There are four missions, six minigames and the onboard tasks, which is still few for a long match.
- **Events.** Only three types, with no chaining between them.
- **NASA.** Only DONKI, and it only feeds the solar storm.
- **Economy and rewards.** Credits exist only in planning and turn into points in the report. There is no economy during operation and no upgrades between missions.
- **Propulsion chamber.** The panel replies that the control is under development.
- **Browser multiplayer.** The Web build is published, but joining a room from the HTTPS page (with `wss://`) has not yet been tested end to end.

## Roadmap

1. Make the CML 1 objective matter, or reduce the options to what exists.
2. Give the engineer their own maintenance and diagnostics actions.
3. Add tasks and events, with chaining (a poorly handled event makes another worse).
4. Test multiplayer through the browser with `wss://` and configure the NASA feed in the Web build.
5. Integrate NeoWs into the asteroid event and EONET into events that affect the base.
6. Economy during operation and some kind of progression.
7. Expand the DONKI fallback and update the feed automatically with a GitHub Action.
8. Implement the propulsion chamber panel and save games.
9. Rebalance the numbers, which the code itself marks as provisional.

## Points of attention

- `project.godot` declares Godot 4.7, and the old README mentioned 4.6. It is worth agreeing on a single version.
- The project uses Forward+, and Godot 4's Web export works with the Compatibility renderer. Check on the first export that it opens in the browser.
- Assets total about 57 MB, of which 24 MB is music. For Web, it is worth compressing the MP3s.
- There are unreferenced template assets: `knight`, `slime_green`, `slime_purple`, `coin`, `fruit`, `platforms`, `world_tileset`, a PNG with a UUID name, `time_for_adventure.mp3` and `Laboratorio_futurista_em_pixel_art.webp`.
- The scene `scenes/baseterrestre/saladecontrole.tscn` is not used by anything.
- The repository has a single commit.

## Credits and license

The license has not been defined yet, and the repository has no `LICENSE` file. Also missing are the asset credits (music, effects, font, sprites and interface) and the team list.

### Use of AI

- **Code:** we used Claude Code to help write the GDScript. The game design, the idea of linking planning to flight, and the architecture are ours.
- **Images:** some of the images were generated with AI and then hand-edited in PixelStudio and Pixelorama.
- **Videos:** the videos used in the opening cutscene (`assets/videos/`) were generated with AI.
- **Documentation:** this README and the submission text were written with the help of Claude (Anthropic) from our code and notes, and reviewed by the team.
- No NASA logo, flag or mission identifier was used or generated.

### Data and references

- NASA DONKI, solar flare data (api.nasa.gov).
- NASA's Concept Maturity Levels (CML) and PDR and CDR reviews, as a reference for planning.
- Godot Engine 4 (MIT license), Python 3, Git and GitHub.
- PixelOperator8 font.

Terra Chamando - Project developed for the NASA Space Apps Challenge 2026, for the Space Mission Design Game challenge.
