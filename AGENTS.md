# Quest Party development

## Local WoW UI source

- Blizzard's UI source is checked out at `/home/chadneff/git/hub/wow-ui-source`.
- Use this local source first when checking WoW APIs, events, templates and UI
  behavior, before searching the web.
- Quest Party targets WoW Forever. Read the `origin/forever` ref; the source
  checkout's `live` branch is retail and is not the target API baseline.
- Inspect the reference without switching its branch or modifying its files:

  ```sh
  git -C /home/chadneff/git/hub/wow-ui-source show origin/forever:version.txt
  git -C /home/chadneff/git/hub/wow-ui-source grep -n 'JoinPermanentChannel' origin/forever -- Interface
  ```

- Start with `Interface/AddOns/Blizzard_APIDocumentationGenerated/` for API
  documentation and the relevant Blizzard addon for working UI examples.
