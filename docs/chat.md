# KekChat

Quest Party's own chat, named KekChat (2026-11-15).

Started 2026-11-15 on the `v023_chat` branch. A chat of our own over the Quest
Party channel, between Quest Party users only: on Forever addons cannot post
in normal chat, and everything here travels as addon messages, which we draw
ourselves. That is also what lets it do what normal chat cannot.

## Messages are feed entries (0.3.7)

Since 0.3.7 KekChat has no tab or window of its own. A message heard is a
feed entry of type `chat` (`data\feed-types.lua`), kept and drawn with
everything else: its first image in its square on the right, any others
inline before its saying. It is a **distinct** event: every message is its own row and
its own card to stamp, named by `w`, when it was said (the server's clock,
the same on every client). The filter row's KekChat icon hides chat rows from
your feed. The 0.3.6 list of messages moved into the feed at its times on the
first load of 0.3.7.

## The chat bar

Under the feed, on the Feed tab, above the filter row. By default it is only
**KekChat**, the red button with a down arrow, which opens the quick chats.
With **Custom KekChat** on in Settings, the builder sits beside it:

```
[KekChat v]
[KekChat v] [images] [type to pick       ] [Send] [Save] [your saves]
```

- **Images** opens the image picker (search, pages, arrows and Enter). Click
  up to three; click one again to take it out. Right-click the button clears
  them.
- **Type to pick:** a box that suggests, for the word typed, sayings
  ("gr" for Gratz!), effects ("rai" for Rain) and images whose names or tags
  hold it ("gem"). Space, Tab or Enter takes the highlighted one (an image is
  added, a saying or effect set) and clears the box for the next word; the
  arrows move the highlight; Enter on an empty box sends. Clicking into the
  empty box lists every saying. The typed word is never sent, and a word with
  no match is dropped, so this is a keyboard way to pick, not free text.
- **Send** sends it all as one message: `S` with `i`, `i2`, `i3` (the icons'
  file IDs), `k` (the saying's id) and `w` (when); an effect from the ready-made list adds `e` (the
  effect's id). Every client,
  yours included once the server sends it back, adds it to the feed and plays
  the effect over the panel.
- **Save** keeps the pair as one of your presets (account wide, up to
  `maxPresets`).
- **KekChat** (the red button at the right end) opens the quick chats: the
  built-in messages (`ChatPresets`, for anyone who does not want to make
  their own). Clicking one sends it straight away. Under them, the effects,
  as the same grid the stamp picker has (`ui\effect-grid.lua`): one plays
  over the feed for everyone and leaves no row.
- **Your saves** (the book, at the right end, beside Save) lists the ones you
  saved. Pick one to load it; right-click one to remove it.

## Pre-made words only (decided 2026-11-15)

Nobody types words of their own. Quest Party chat does not show in the game's
chat, so the game's reporting, filters and silences cannot reach it; with
only sayings from our own list there is nothing to report. A free-text line
and a grid of buttons were both tried the same day and replaced by the bar.

A saying travels as its id, and every client shows it from its own list, in
its own language. An id it does not know (from a newer version) is left out,
and anything that is not a plain id is dropped. A saying can also do
something on everyone's screen: Cheers! drops confetti.

## Effects, sounds and the particle engine

**Effects on cards (0.3.7).** Effects (`data\effects.lua`, `EffectPresets`)
are not KekChat messages any more: right-click any card, and under the stamps
pick one. It plays over that card on everyone's screen, with its sound, and
leaves nothing behind: no feed row, no stamp. It travels as a stamp message
with `e` (the effect's id) and no `s`, which older versions ignore. One played
from KekChat's list has no card: it goes under the key `~feed` and plays over
the feed. Each is
**empty** (images only, like Coin rain) or **worded** (with a saying, like
Gratz rain: its words fall as particles among the images). Same limits as a
stamp; muted players' effects never play.

A small particle engine of our own: `particles.lua` moves particles as plain
data (so the tests can check every effect starts, moves and ends, and that
fireworks pop), `ui\particles.lua` draws them, one layer per frame they play
over, a pool of textures, a cap of `maxParticles`, and nothing at all once
the last one is gone. An effect is data: a pattern, how many, how long, sizes,
speeds, gravity, spin, and a sound (a game sound id; one the client does not
have plays nothing). Only the effect's id travels. A worded effect turns some
of its particles into its saying's words (gold text), and fireworks rockets
burst into them too.

An effect plays over the panel when its message lands. Settings has **Chat effects** to turn them off, and a **Volume** (Mute, Soft,
Regular, Loud) that the speaker in the title bar steps through. A muted player's effects never play.

## The image picker

The game lists its icons (`GetMacroIcons`, `GetMacroItemIcons`, as the macro
icon picker does) as file IDs with no names, so they can be browsed but not
searched by word. Search runs over our own list instead (`data\chat.lua`,
`IconCatalog`): icon paths with tags, turned into file IDs at load with
`GetFileIDFromPath`; paths the game does not know are dropped. With nothing
typed, ours come first, then every icon in the game to browse.

## Muting

Right-click any of a player's cards: under the stamps, **Mute** (or
**Unmute**) them. Their KekChat rows hide, including what they sent before,
their stamps are ignored, and their sayings do nothing on your screen. Anyone on the game's ignore list is muted too. Kept across reloads.
(No one can be removed from a channel; muting is what each player controls.)

## Rules

- **Safety:** an image is only ever a number, a saying only an id; both are
  checked before anything is drawn, and what is drawn comes from this
  client's own data.
- **Spam, a timeout as in Rocket League's team chat:** past `burst` messages
  in `burstSeconds`, a sender is timed out for `timeoutSeconds`, doubling each
  time it happens again (up to `timeoutMax`), back to the start after
  `timeoutForgetSeconds` without one. Each client keeps this per sender:
  - **yours:** nothing can be sent until it is up; Send counts down and it
    and the effect tiles are greyed out;
  - **a spammer's:** everything they send is left out here until it is up,
    with one notice in your chat window ("Name is sending too fast: hidden
    for 15s"). Muting stays separate: permanent and by hand.
- **One press, one message:** a second press of Send or an effect tile within
  half a second (a double-click) does nothing.
- **History:** messages are feed entries, kept with the feed (its latest 200).

## Dev mode

In dev mode (`/qp dev on`), pretend players send an image, a saying or both
now and then, so the feed's chat can be seen busy without a second account.

## Later

More sayings, effects and sounds, item and quest links from cards, reactions,
`/roll`, mentions that flash the tab, and stamps: the game's atlas art and
raid markers as images, sent as names from a list we allow.

## The dock: Quest Party minimized

The **-** in the title bar minimizes Quest Party: the panel shrinks and fades
into the left edge of the screen (or the right, with **Dock on the right** in
Settings), and stays there as a dock (`ui\dock.lua`). Recent feed rows,
KekChat messages among them, stand as thin stick bars, newest on top, colored by the
player's class. As the mouse comes near, the bars grow toward it, the nearest
most, like the macOS dock; the one under it shows its icon and its line.
Clicking a bar grows the panel back out to where it was, on its row; moving it and minimizing again remembers the new spot. While docked, each
new event puffs its icon out of the dock. The dock is kept across reloads.
