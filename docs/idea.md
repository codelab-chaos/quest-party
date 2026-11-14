# Quest Party

The idea is to re-create the basic functionality of my old addon quest-tweet here ../questtweet/

We want these enhancements:
- Party Panel: shown in the concept-art.png
- Ability to filter; we want persistent feed, meaning, if a user has a quest in progress and is actively gathering kills or mats. we want to show that as apersisted card instead of a chat feed? 
- We would like more persistences and the ability to sync and track what your party is doing
- We want the ability for folks to easily tap into a feed or be part of a feed. 

## Notes

- Sharing may have to scale to larger channels (8 or more players, not just a few friends). Each player's messages go to everyone, and the game allows an addon a short burst and then about one message a second. What is already in place for that: only quests that are underway are shown and told, a newcomer's catch-up is one message per quest, answers to a hello are spread over a few seconds, and rapid counts for one objective collapse to the newest. What to watch as channels grow: the burst when several people join at once, kills still costing a message each, and how many quest cards fit in the panel.
