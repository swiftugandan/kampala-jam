# Game Brief: Kampala Jam

Source of the idea: an article by Dr Ian Clarke in New Vision.

**One-sentence pitch:** Drive the real streets of Kampala from Speke Resort, Munyonyo to the Uganda Martyrs' Shrine, Namugongo as fast as you can, past the landmarks you know, without running over a boda boda.

## Core loop
- Press DRIVE. The game decides what day it is: each finished run moves on to a harder one, from Sunday morning to the day the kids go back to school.
- Read the road and choose: squeeze, wait, detour, or brave the flood. The "maps" line does not know about today's closures.
- Every incident costs penalty points, and every penalty point is a second added to your time.
- Finish and tomorrow is worse. Fail and you try today again, now knowing where the ditches are.

## Player goal & fail state — what "working" looks like
- Reach the finish with the lowest score (time in seconds + penalty points).
- A run fails if penalties reach the licence limit (licence withdrawn) or the day's time cap passes.
- Run over a boda boda and the penalty is the highest in the game. Hidden ditches under flood water swallow the car.

## MVP — what must exist to be the game
- Real road network and building footprints from OpenStreetMap, with named, recognisable landmarks along the way.
- Drivable car with keyboard, gamepad and touch controls; on web, desktop and Android.
- Left-hand traffic: cars, taxis, trucks, school vans and weaving boda bodas, with jams.
- The penalty ladder: scratches, contact, obstructions, altercations, collisions, run-overs.
- Road hazards: open drains, rebar manholes, marram, trenches, unannounced closures, flag-wavers.
- Weather and floods with hidden ditches; the presidential convoy closure.
- A self-advancing campaign: five days of rising difficulty with the "Boxed In" Muyenga run among them, then ever-busier school terms. Local best times. The player never picks a difficulty.

## Out of scope — not building this
- 3D, multiplayer, online leaderboards, in-app purchases, car customisation, voice acting.
- Native iOS build for now (needs a newer Xcode host); iPhones and iPads play the web build.
- Naming real contractors or officials in-game. Works signage uses invented names.

## Build order
1. OSM pipeline and map, because everything depends on it being real.
2. Car on the real road network with camera and rendering.
3. Traffic and the penalty ladder.
4. Hazards, weather, convoy.
5. UI, touch, audio, then exports on every platform.

---
**Who it's for / what they feel:** Kampala drivers who will laugh in recognition, and everyone else who will not believe this is real.

**Art & audio direction:** Bright top-down vector map: red murram, iron-sheet roofs, equatorial green, signwriter lettering. Synthesised horns, sirens and rain.

**Reference game:** Crazy Taxi: the readable arcade driving against a clock; the MVP keeps the free routing through a real-feeling city and drops the passengers.
