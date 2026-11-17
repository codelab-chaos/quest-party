# Feed card scenes

Painted backgrounds for feed cards: 16 WoW-flavored scenes in one atlas
image, swapped or mixed and matched per feed type and per profession.

- The list, the atlas shape, each scene's brief and which card gets which
  scene: `QuestParty/data/scenes.lua` (`Scenes`, `SceneByType`, `SceneBySkill`).
- Picking a scene and cropping it to a card: `QuestParty/scenes.lua`.
- Putting it on a texture: `ns.Look.SetScene(texture, scene, width, height)`.
- The template and the atlas: `scripts/scenes.py`.

Not drawn on the cards yet: until the art is in, the atlas holds a
placeholder per scene (dark, its tint rising at the right).

## The atlas

One 1024 x 512 TGA (`QuestParty/media/scenes.tga`): two columns of eight
512 x 64 cells, scene 1 top left, 2 top right, 3 under 1, and so on.

A cell is 8 to 1, about a feed row's shape. A card shows the middle of its
scene, cropped to the card's own shape and never stretched:

- **one-line rows** (about 18 to 1) show a band about 28 pixels tall across
  the middle;
- **most cards** (6 to 9 to 1) show nearly all of it, a taller card losing a
  little off each side.

The game samples half a texel in from each cell's edge, so neighbours never
bleed in.

## Painting a scene

```sh
scripts/scenes.py template   # art/scenes/template.svg and template.png
```

`template.svg` labels every cell with its number, name, brief and file name;
`template.png` is the same guide at the atlas' exact size, to paint over as a
layer. Each cell has:

| Zone | Where (cell pixels) | What goes there |
| --- | --- | --- |
| Icon (red) | x 0 to 56 | Plain and dark: the event's icon sits on it. |
| Text (middle) | x 56 to 421 | Dark and quiet, under 35% brightness: white and gold text sits on it. |
| Focus (gold) | x 421 to 512 | The thing that makes the scene recognizable: the forge's glow, the keep, the chest. The time or count sits on it. |
| Bands (dashed) | blue y 18 to 46, white y 5 to 59 | What cards show. Keep the focus inside the blue band. |

Save each scene as `art/scenes/<id>.png` (8-bit RGB or RGBA, at least
1536 x 192, the 8 to 1 shape; anything else is cropped about the middle).
Then:

```sh
scripts/scenes.py build      # QuestParty/media/scenes.tga
```

The build lists each scene as art or placeholder, and warns when a scene's
text zone is too bright for white text. A new or replaced atlas needs the
game restarted the first time, then `/reload`.

## Mixing and matching

Any scene can go on any card: change `SceneByType` (by feed type) or
`SceneBySkill` (a skill-up, by profession). A new scene is a new line in
`Scenes` (the atlas has room for 16; a bigger atlas is a change to
`SceneAtlas`), its art, and a build.
