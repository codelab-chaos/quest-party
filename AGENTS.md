# Quest Party development

## Local WoW UI source

- Blizzard's UI source is checked out locally (a clone of Gethe/wow-ui-source).
  Set `WOW_UI_SOURCE` to its path; the examples below use it.
- Use this local source first when checking WoW APIs, events, templates and UI
  behavior, before searching the web.
- Quest Party targets WoW Forever. Read the `origin/forever` ref; the source
  checkout's `live` branch is retail and is not the target API baseline.
- Inspect the reference without switching its branch or modifying its files:

  ```sh
  git -C "$WOW_UI_SOURCE" show origin/forever:version.txt
  git -C "$WOW_UI_SOURCE" grep -n 'JoinPermanentChannel' origin/forever -- Interface
  ```

- Start with `Interface/AddOns/Blizzard_APIDocumentationGenerated/` for API
  documentation and the relevant Blizzard addon for working UI examples.
