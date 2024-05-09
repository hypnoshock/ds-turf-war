# Turf Wars

A game built on Downstream which uses Sky Strife as the combat layer. This was House B's efforts during the Autonomous Anonymous 2024 hackathon event.

## The Game

Main Mechanic: Paint the zone tiles by walking on them and score a point for your team. Secure areas by placing a base building for your team, so no other team can place a building there.
Recover secured areas by starting a battle on the enemy's base building; this will initiate a sky strife match. If the winner is the building owner, nothing happens; if the winner is the opponent, the building gets destroyed, and the tiles around it get painted in the opponent's color.
The opponent can then secure the area by placing a building.
If no secure building was placed, one team can place a building on the other's color and secure the area, but only if it's already painted.

The buildings are not going to be that easy to build; players only start with materials for 1 or 2 buildings, and then need to destroy other players' buildings to recover some materials

## The Techicals

We were developing locally during the hack so the process to test the game is to start a local instance of Sky Strife by following the instructions on their Github repo `https://github.com/latticexyz/skystrife-public`. The commit we were running this hack on was `cc96480c3148c3ea139cbb8da026ade34e7d086b`

We are also running Downstream `https://github.com/playmint/ds` locally with a slightly doctored config to make it point to the `anvil` instance that Sky Strife spins up.

- `.devstartup.js` was edited remove the command that starts up `anvil`
- `core/src/cog.ts` was edited to use `networkID: '31337`
- `frontend/public/config.json` was edited to use `networkID: '31337`
- Downstream started by running `make dev` from the project root

When both projects are running we can then deploy Turf Wars by running the following at the root of the project

```shell
  npm ci && ./deploy-local.sh
```

The private keys in the `.env` file are the default `anvil` keys when no mnemonic is specified.

### Project Layout

The `downstream` folder contains the Downstream building contracts and the map for the game. These are applied to a Downstream zone via the `ds` cli tool.

The main logic to the game is found in the `Zone` contract. Interactions with this contract are done via the UI found in buildings.

Buildings:

- The `TurWarsHQ` building is frontend only. It's used as a UI interface to join a team and reset the game.
- The `Base` building the interface to starting matches and claiming wins via the intermediary `TurfWars` contract.
- The `StartBuilding` has two yaml files for each of the team's starting positions. It is frontend only and is used as an interface to set a team as ready

The `contracts` folder contains the `InitTurfWars.s.sol` script which uses interfaces from Downstream and Skystrife to make the two Downstream buildings aware of each other, get the address of the Sky Strife `Orb` token and fund the battle building with orbs so that it is able to create matches.

## To-do

- [ ] Search for item slot to deposit hammers
- [ ] UI
  - [ ] Clearer which team you're on when clicking the start buildings
  - [ ] Being able to leave after joining
  - [ ] Choosing your team instead of being assigned a team
- [ ] Resetting
  - [ ] Decide when it's possible to reset the game.
- [ ] Win state (Which side has the most tiles after the timer has run out)
  - [ ] Medals for winning (air drop if possible)
- [ ] Internal book keeping for hammers so players can't play with more hammers than they started with
- [ ] Auto burn excess hammers on join
- [ ] Configurable matches
  - [ ] Size of claimed area
  - [ ] Match length
  - [ ] Auto tile painting
  - [ ] Number of buildings you can construct

### Nice to have

- [ ] Start positions not to be hardcoded
- [ ] Security around who can start battles
  - [ ] Don't allow battles to be started by non Turf Wars players
  - [ ] Don't allow battles to be started until the game starts
- [ ] Orb to DS item bridge?
- [ ] Restrict construction to bases and blockers (if allowed)
- [ ] Prize pool

### Done

- [x] Deploy script to update building and zone impl addresses if they have changed
- [x] Don't allow the attacker to claim on timeout if the defender has joined the match
- [x] Look into Sky Strife's private match system and see if we can prevent non TW players from joining
- [x] Eth and orb withdrawal on mediator contract
- [x] Fix deploy script to work with Garnet
  - [x] Don't redeploy interim script
  - [ ] Initial deploy of interim script to be done by zone contract
- [x] Tidy up empty bags (the whole spawning bag, transferring item and destroying bag is probably VERY gassy)
- [x] If placing a battle building down on an unoccupied tile, the player can gain that tile after a period of time of they are not challenged
- [x] Raise cost of base building so you can only build 1 or 2
- [x] Offset the map so 0, 0, 0 is where the Judge building is
- [x] Restrict Battle building UI so it disables the 'Start Battle' button when there is a Sky Strife match waiting to be played on that tile
- [x] After a match has started add a button to directly open the Sky Strife match: `http://localhost:1337/match?asPlayer=&useExternalWallet=&match={matchID}`
- [x] Instead of claiming just the one tile under the battle building, claim an area around the tile so the map can be claimed faster
- [x] Fix the reset code
- [x] Tidy up the code to remove Duck Burger

## Gameplay ideas

- [ ] Allow construction of blockers
- [ ] Secure mode where placing building doesn't claim the tiles but allows the team to claim (doesn't override secured tiles from the other team)
- [ ] Successfully defending your tower shouldn't destroy it (or maybe it should, can't decide if it's fun that you can relocate)
- [ ] Random spawn of powerups
  - [ ] Freeze opponents for x blocks
- [ ] Placing a building down doesn't paint tiles, it just secures the area meaning the opposing team cannot paint there
- [ ] Placing a building down in an area that was already painted another colour either:
  - [ ] Colours tiles the team's colour
  - [ ] Allows the team to start claiming tiles in that area

## Problems

- The first match in window can't be worked out in the DS client because we don't have ability to make contract calls. Presently I'm finding this match during deployment and setting it on the building contract.
