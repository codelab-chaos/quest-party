# Libraries

Shipped inside Quest Party, unchanged, as WoW addons embed them (each loads only
if no newer copy is already loaded by another addon).

| Library | Version | From | License |
|---|---|---|---|
| LibStub | 2 | [WoWUIDev/Ace3](https://github.com/WoWUIDev/Ace3) at `ac3d122` | Public domain (its header) |
| CallbackHandler-1.0 | from Ace3 at `ac3d122` | [WoWUIDev/Ace3](https://github.com/WoWUIDev/Ace3) | BSD, `CallbackHandler-1.0/LICENSE.txt` |
| HereBeDragons-2.0, HereBeDragons-Pins-2.0 | 2.18-release | [Nevcairiel/HereBeDragons](https://github.com/Nevcairiel/HereBeDragons) | BSD (its TOC's X-License), by Hendrik "nevcairiel" Leppkes |

HereBeDragons puts Quest Party's players on the world map and the minimap
(`ui\map-pins.lua`). Map addons that show HereBeDragons icons, OpenMap among
them, show them too.
