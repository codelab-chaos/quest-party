# KekChat

Quest Party's own chat, named KekChat (2026-11-15).

Started 2026-11-15 on the `v023_chat` branch. A chat of our own over the Quest
Party channel, between Quest Party users only: on Forever addons cannot post
in normal chat, and everything here travels as addon messages, which we draw
ourselves. That is also what lets it do what normal chat cannot.

## The chat bar

Along the bottom of the chat, one row:

```
[images] [type to pick       ] [Send] [Save] [your saves]
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
  file IDs) and `k` (the saying's id); an effect from the KekChat button's list adds `e` (the
  effect's id). Every client,
  yours included once the server sends it back, shows the sender's name, the
  images popping in and the saying beside them, and plays the effect.
- **Save** keeps the pair as one of your presets (account wide, up to
  `maxPresets`).
- **The KekChat button** (KekChat's name, a red button with a down arrow, top
  left) drops down everything ready made: **Messages**, the built-in presets
  (`ChatPresets`, for anyone who does not want to make their own), then
  **Effects** (`data\effects.lua`, `EffectPresets`), each **empty** (images
  only, like Coin rain) or **worded** (with a saying, like Gratz rain: its
  words fall as particles among the images). Effects are not built by the
  player yet. Clicking any of them sends it straight away.
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

A small particle engine of our own: `particles.lua` moves particles as plain
data (so the tests can check every effect starts, moves and ends, and that
fireworks pop), `ui\particles.lua` draws them, one layer per frame they play
over, a pool of textures, a cap of `maxParticles`, and nothing at all once
the last one is gone. An effect is data: a pattern, how many, how long, sizes,
speeds, gravity, spin, and a sound (a game sound id; one the client does not
have plays nothing). Only the effect's id travels. A worded effect turns some
of its particles into its saying's words (gold text), and fireworks rockets
burst into them too.

Images pop in as a message arrives; click a message's images to pop them
again and replay its effect. Settings has **Chat effects** to turn them off, and a **Volume** (Mute, Soft,
Regular, Loud) that the speaker in the title bar steps through. A muted player's effects never play.

## The image picker

The game lists its icons (`GetMacroIcons`, `GetMacroItemIcons`, as the macro
icon picker does) as file IDs with no names, so they can be browsed but not
searched by word. Search runs over our own list instead (`data\chat.lua`,
`IconCatalog`): icon paths with tags, turned into file IDs at load with
`GetFileIDFromPath`; paths the game does not know are dropped. With nothing
typed, ours come first, then every icon in the game to browse.

## Muting

Right-click a message to mute its sender, or unmute them: nothing they send
shows, including what they sent before, and their sayings do nothing on your
screen. Anyone on the game's ignore list is muted too. Kept across reloads.
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
  - **a spammer's:** everything they send is hidden here until it is up, with
    one grey notice in chat ("Name is sending too fast: hidden for 15s"),
    not kept across a reload. Muting stays separate: permanent and by hand.
- **One press, one message:** a second press of Send or an effect tile within
  half a second (a double-click) does nothing.
- **History:** the latest `maxMessages` are saved, so chat survives a reload.

## Where it shows

- A **KekChat** tab at the right end of the tab row shows the chat in place of
  the feed.
- **▷** pops it out beside the feed, where the player card goes; a card opened
  while chat is out sits to the right of it. **◁**, or the KekChat tab, docks it back.

## Sandbox

Pretend players send an image, a saying or both now and then, so the chat can
be seen busy without a second account. What you send in the sandbox goes out
marked as a pretend player of your name: shown there as you, ignored by friends.

## Later

More sayings, effects and sounds, item and quest links from cards, reactions,
`/roll`, mentions that flash the tab, and stamps: the game's atlas art and
raid markers as images, sent as names from a list we allow.

## The dock: Quest Party minimized

The **-** in the title bar minimizes Quest Party: the panel shrinks and fades
into the left edge of the screen (or the right, with **Dock on the right** in
Settings), and stays there as a dock (`ui\dock.lua`). Recent events, feed rows
and KekChat messages, stand as thin stick bars, newest on top, colored by the
player's class. As the mouse comes near, the bars grow toward it, the nearest
most, like the macOS dock; the one under it shows its icon and its line.
Clicking a bar grows the panel back out to where it was (on KekChat for a chat
bar); moving it and minimizing again remembers the new spot. While docked, each
new event puffs its icon out of the dock. The dock is kept across reloads.
