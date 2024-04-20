# Turf Wars

A game built on Downstream which uses Sky Strife as the combat layer. This was House B's efforts during the Autonomous Anonymous 2024 hackathon event.

End to end we are demonstrating:

- Initiating a Turf Wars game on the Judge building
- Conquering a tile by placing a 'Battle' building down and starting a Sky Strife match from the building's ui
- Joining the game via the Sky Strife frontend
  - Due to limitations (which were intentional) with Downstream's plugin system, direct calls to join a match via metamask couldn't be done
- Playing out a Sky Strife match which is associated with the tile in contention
- The winner of the match will gain that tile for their team and it'll light up in the teams colour

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

- The `Judge` building is in charge of starting a game, keeping track of score and painting the claimed tiles the team's colour
- The `BattleBoy` building is in charge of starting a Sky Strife match, querying the outcome of the match and telling the `Judge` building the winner. It has to be funded with `Orb` tokens to be able to start matches
- The `Counter` building is what displays score on the map

The `contracts` folder contains the `InitTurfWars.s.sol` script which uses interfaces from Downstream and Skystrife to make the two Downstream buildings aware of each other, get the address of the Sky Strife `Orb` token and fund the battle building with orbs so that it is able to create matches.

## The Game

It's still not finished as a game but you can test the concept by building a 'Battle' building on a tile, starting a sky strife match from the building's UI, joining and playing the match through the Sky Strife frontend, returning to Downstream to 'claim' the win and seeing the tile light up with the winning team's colour. Only the winning team is able to press the 'Claim button'

## To-do

- [ ] Offset the map so 0, 0, 0 is where the Judge building is
- [ ] Restrict Battle building UI so it disables the 'Start Battle' button when there is a Sky Strife match waiting to be played on that tile
- [ ] After a match has started add a button to directly open the Sky Strife match: `http://localhost:1337/match?asPlayer=&useExternalWallet=&match={matchID}`
- [ ] Don't allow battles to be started by non Turf Wars players
- [ ] Don't allow battles to be started until the game starts
- [ ] Instead of claiming just the one tile under the battle building, maybe claim an area around the tile so the map can be claimed faster
- [ ] Fix the reset code
- [ ] If placing a battle building down on an unoccupied tile, the player can gain that tile after a period of time of they are not challenged
- [ ] Tidy up the code to remove Duck Burger

## Gameplay ideas

Maybe instead of goo to build a battle building, you have to build one with a battalion item which opens up a another gameplay mechanic where you have to produce a batallion from a barracks. This also means if the challenger loses they'll lose their batalion
