# Quest Party

The idea is to re-create the basic functionality of my old addon quest-tweet here ../questtweet/

We want these enhancements:
- Party Panel: shown in the concept-art.png
- Ability to filter; we want persistent feed, meaning, if a user has a quest in progress and is actively gathering kills or mats. we want to show that as apersisted card instead of a chat feed? 
- We would like more persistences and the ability to sync and track what your party is doing
- We want the ability for folks to easily tap into a feed or be part of a feed. 

## Notes

- Sharing may have to scale to larger channels (8 or more players, not just a few friends). Each player's messages go to everyone, and the game allows an addon a short burst and then about one message a second. What is already in place for that: only quests that are underway are shown and told, a newcomer's catch-up is one message per quest, answers to a hello are spread over a few seconds, and rapid counts for one objective collapse to the newest. What to watch as channels grow: the burst when several people join at once, kills still costing a message each, and how many quest cards fit in the panel.

## Future ideas

Dreamed up on 13 November 2026, after channel sharing started working. None of this is planned or built. Each idea says what it would need, so it can be picked up later.

### A state tab that scales to any number of players

For people who want more than the feed: a passive view of where everyone stands, that still reads well with 3 players or 30.

- **Shape:** a table, one row per player, that scrolls and sorts. Columns such as level, zone, what they are working on, XP per hour, last active. A row stays one line however many players there are, which is what a card per player per quest cannot do.
- **What it needs:** one small status message per player that says how they stand now, sent on hello and again when it changes, no more than about once a minute. This is the same "how things stand" idea the quest messages already use.
- **Cost:** one message per player per minute at most, so it grows gently with the size of the channel.
- **Open questions:** which columns; whether sorting by XP per hour turns it into a race, and whether that is wanted; whether a row opens to show that player's quests.

### Tabs as stat containers

The XP, Achv, Prof and Party tabs are only the feed with a filter on it. Each could show stats for everyone on the channel above its feed rows.

- **XP:** level, bar to next level, XP per hour, estimated time to level, levels gained today.
- **Achv:** total points, how many earned, earned this week, the most recent one.
- **Prof:** each profession with a skill bar, points gained this session.
- **Party:** who is sharing, level, zone, what they are working on, last active.
- **What it needs:** the same status message as above. Each player's own client works its numbers out, since only it sees every gain. Rates over time (per hour, this week) need the player's client to keep its own tallies, which can only start from when this is installed.
- **Not checked yet:** which achievement totals and profession skill levels the Forever client lets an addon read. Today Quest Party only catches skill-up messages.

### Sharing professions and goods

Each player shares what they can make and what they have to spare, so friends know who to ask.

- **Examples:** "Uther: Blacksmithing 150, can make Iron Buckle", "Jaina has 40 Linen Cloth spare".
- **Why it is harder:** it is verbose. A recipe list or a bag of goods is far more than fits in a message or two, and sending it to everyone on a channel would flood it.
- **A way that scales:** tell everyone only the short part (which professions, at what skill), and send the long part (recipes, goods) only when someone asks for one player's list. A request and an answer between two players, not a broadcast.
- **Open questions:** whether goods to spare are picked by hand or read from bags; whether this overlaps with what the auction addon already knows about items.

### The look

The concept art is much fancier than the panel today: player portraits, art behind each row, a big level badge, a search box. See `concept-art.png` here and the newer renders in `../auction-hero/docs/concept-art/`. Portraits and row art are a separate job from any of the ideas above, and none of them depend on it.
