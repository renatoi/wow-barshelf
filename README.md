<p align="center">
  <img src="assets/barshelf_logo_transparent_256.png" alt="Barshelf" width="128" />
</p>

<h1 align="center">Barshelf</h1>

<p align="center">
  <b>Hide your action bars. Access them on demand.</b>
</p>

<p align="center">
  <a href="https://www.curseforge.com/wow/addons/barshelf">CurseForge</a> &middot;
  <a href="https://addons.wago.io/addons/qGYZjRNg">Wago</a> &middot;
  <a href="https://github.com/renatoi/wow-barshelf/releases">GitHub Releases</a>
</p>

---

Barshelf lets you declutter your UI by hiding Blizzard's action bars and accessing them through a compact floating dock. Click a shelf handle to pop open your action bar in a customizable grid — then click again (or press ESC, or click away) to dismiss it.

Since Barshelf reparents Blizzard's actual buttons (not copies), everything works natively in combat: cooldowns, usability, range coloring, proc highlights, and tooltips.

## Features

- **Bar Shelves (Bars 1–8)** — Reparent any Blizzard action bar into a popup grid. Cooldowns, range checks, and proc highlights work in combat.
- **Custom Shelves** — Drag spells, items, or macros onto buttons to create your own popup groups (OPie-like).
- **Configurable Grid** — Set # of icons, # of rows, icon size, and padding per shelf. Auto-detects Blizzard's Edit Mode settings when adding a bar.
- **Multiple Docks** — Horizontal or vertical. Drag the grip to reposition. Each dock holds any number of shelves.
- **Appearance Controls** — Dock/shelf/handle background opacity, border toggle, padding, handle icon and font sizes — global defaults with per-shelf overrides.
- **Edit Mode Aware** — Entering Edit Mode temporarily restores hidden bars so you can configure Blizzard's settings. Changes are picked up automatically on exit.
- **Profiles** — AceDB profile support. Switch, copy, or reset configurations per character.
- **Blizzard Settings Integration** — All options live in the AddOns tab with subcategories: General, Appearance, Shelves, Docks, Profiles.

## Installation

Install from [CurseForge](https://www.curseforge.com/wow/addons/barshelf) or [Wago](https://addons.wago.io/addons/qGYZjRNg) using your preferred addon manager (CurseForge app, WowUp, etc.).

Manual install: download the latest zip from [GitHub Releases](https://github.com/renatoi/wow-barshelf/releases), extract it into your `World of Warcraft/_retail_/Interface/AddOns/` folder, and restart the game.

## Usage

Open settings from the game menu (**Esc > Options > AddOns > Barshelf**) or type:

```
/bs              -- Open settings
/barshelf        -- Open settings (alternate)
```

### Getting started

1. Type `/bs` or click the minimap icon to open settings.
2. Go to the **Shelves** tab and click **+ Add Bar Shelf**.
3. A dock appears on screen with your shelf handle — click it to toggle the popup.
4. Right-click any handle to jump to that shelf's settings.
5. Drag the dotted grip on the dock to reposition it.

### Settings tabs

| Tab | What it does |
|---|---|
| **General** | Close-others behavior, popup animation, minimap icon, bar row order |
| **Appearance** | Dock/shelf/handle opacity, border, padding, icon and font sizes |
| **Shelves** | Add, remove, and configure shelves — action bar, grid layout, handle style |
| **Docks** | Add, remove, and configure docks — name, orientation |
| **Profiles** | Create, copy, or reset setting profiles |

### Slash commands

```
/bs              -- Open settings
/bs reset        -- Reset dock positions to center
/bs rebuild      -- Force rebuild all docks and shelves
```

### Tips

- Set your action bars to **Hidden** in Blizzard's Edit Mode — Barshelf hides them automatically when a shelf is active and restores them when removed.
- Use **Custom Shelves** for utility spells, profession cooldowns, or consumables you don't need on your main bars.
- Adjust **# of Rows** to create compact grids (e.g., 3 columns × 4 rows for a 12-button bar).

## Development

### Project structure

```
Barshelf.toc         -- Addon manifest
Core.lua             -- AceAddon lifecycle, events, shelf/dock management
Options.lua          -- AceConfig tables + Blizzard Settings panels
Dock.lua             -- Dock frame creation, handle display, grip drag
Popup.lua            -- Popup frame creation, anchor logic, button layout
BarShelf.lua         -- Bar shelf: reparent Blizzard buttons, grid layout
CustomShelf.lua      -- Custom shelf: drag-to-assign spells/items/macros
embeds.xml           -- Ace3 library loader
Libs/                -- Embedded Ace3 framework + LibDBIcon + LibDataBroker
```

### Linting & formatting

The project uses [luacheck](https://github.com/lunarmodules/luacheck) for linting and [StyLua](https://github.com/JohnnyMorganz/StyLua) for formatting.

```bash
make lint            # Run luacheck
make format          # Auto-format with StyLua
make format-check    # Check formatting without modifying
```

CI runs both checks on every push and PR via `.github/workflows/lint.yml`.

### Releasing

Releases are automated via GitHub Actions. To publish a new version:

1. Update `CHANGELOG.md` with the new version section.
2. Tag the commit: `git tag v1.1.0 && git push --tags`
3. The workflow packages the addon and publishes to CurseForge, Wago, and GitHub Releases.

## License

MIT
