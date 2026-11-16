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
