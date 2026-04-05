## v1.4.0

### New Features
- **List layout mode for custom shelves**: New per-shelf "Layout" dropdown (Grid / List). List mode shows buttons in a vertical single-column layout with icon, spell/item name, and hotkey per row. Popup width auto-adjusts to label lengths (150–300px). The `# of Rows` slider is hidden in list mode.

### Bug Fixes
- **Shelf rename not saving**: Edit boxes now save on focus-lost (blur) in addition to Enter, fixing rename inside the Blizzard Settings panel where Enter/Backspace/arrow keys were intercepted. Escape reverts to the previous value.
- **Arrow/Backspace keys not working in edit boxes**: Keybind capture buttons were consuming keyboard events even when not in listening mode. They now propagate keys through when inactive.
- **Empty action bar slots disappearing on mouseover**: Reparented Blizzard action buttons are now immediately re-shown via an `OnHide` hook instead of relying on a 1-second watchdog, preventing empty slots from vanishing when trying to drag spells onto them.
- **Flyout spells silently rejected**: Dragging a flyout spell (e.g. Hunter Pet Skills, Mage Portals) onto a custom shelf now shows a helpful message instead of silently ignoring the drop.

---

## v1.3.3

### Bug Fixes
- **Right mouse button getting stuck**: The click-outside-to-close backdrop was registering for all mouse buttons (`AnyUp`), which could swallow `RightButtonUp` events before the game received them — causing the right mouse button to appear stuck. Now only listens for left-click.

---

## v1.3.2

### Bug Fixes
- **Cooldown taint errors in combat**: Fixed "secret values are only allowed during untainted execution" errors. In 12.0.1, addon code cannot pass secret cooldown values to ANY display function (`SetCooldown`, `CooldownFrame_Set`, `SetTimeFromStart` — all reject secrets from tainted code). Now uses `isActive` (boolean, never secret) to branch, and `issecretvalue()` to detect secret values before passing them. Cooldowns display normally outside combat; gracefully degrade during combat when values are secret.

---

## v1.3.1

### Bug Fixes
- **Shelf rename not working**: Fixed label edit box not responding to Enter/Backspace. Switched from `BackdropTemplate` to `InputBoxTemplate` which properly handles keyboard input inside the Blizzard Settings panel.

---

## v1.3.0

### New Features
- **Mount support on custom shelves**: Drag mounts from the Collections journal onto custom shelf buttons. Uses `/cast` macro for reliable summoning.
- **Battle pet support on custom shelves**: Drag companion pets from the Pet Journal onto custom shelf buttons. Summons via `/summonpet`.
- **Keybindings for custom shelves**: Assign key bindings to individual custom shelf slots via the per-shelf settings panel. Bindings work even when the popup is closed (via invisible proxy buttons). Keybind text shown on each button.

### Improvements
- **Cooldown display on custom shelves**: Proper dark "pizza" sweep overlay with countdown text, matching Blizzard's native action buttons. Uses `issecretvalue()` to handle 12.0.1 secret combat values gracefully.
- **GCD animation**: Global cooldown sweep now shows on all custom shelf buttons. Event-driven via `SPELL_UPDATE_COOLDOWN` / `ACTIONBAR_UPDATE_COOLDOWN` for instant response. Off-GCD abilities (defensives, some trinkets) correctly skip the sweep.
- **Handle icon for mounts, macros, and battle pets**: Dock handle now picks up icons from all custom shelf action types, not just spells and items.

### Bug Fixes
- **Items not activating on click**: Fixed `SecureActionButtonTemplate` item attribute format — now uses `"item:ID"` string instead of raw numeric ID.
- **Item cooldowns not displaying**: Fixed `C_Item.GetItemCooldown` return value unpacking — returns three separate values, not a table (unlike `C_Spell.GetSpellCooldown`). Added bag/equipment scan fallback with location caching for combat safety.

---

## v1.2.1

### New Options
- **Click outside to close popups**: Toggle in General settings. When disabled, shelf popups stay open until their handle is clicked again — useful for dragging spells from the spellbook onto action bar shelves without the shelf auto-closing.
- **Center popups on dock**: Toggle in General settings. Centers shelf popups horizontally on the dock instead of aligning them to their individual handle. Both options are off by default (existing behavior preserved).

### Improvements
- **Pinned popup drag grip**: The grip is now a visible tab that protrudes above the popup frame (16px, with background and dot pattern). Hidden at idle and appears on mouseover for a cleaner look.
- **Grip integrated with popup fade**: Hovering the grip keeps the pinned popup at full opacity; the grip shares the same enter/leave polling as the popup itself.

### Bug Fixes
- **Blizzard Action Bar 1 appearing over shelves**: Added an aggressive OnShow hook on hidden bar frames to immediately re-hide them when Blizzard's TWW action bar code tries to show them. Properly managed through activate/deactivate/Edit Mode cycles.
- **Bags not opening in combat**: Removed unnecessary `InCombatLockdown()` guard from `ToggleAllBags()` call. Also set the bag handle's secure snippet to a no-op to prevent popup toggle side-effects during combat.
- **Edit Mode exit redundancy**: Simplified `OnEditModeExit` to just call `RebuildAll()` instead of manually re-hiding bars then rebuilding (the rebuild already handles everything).

---

## v1.2.0

### New Shelf Types
- **Bags shelf**: Click handle to toggle all bags open/closed. Handle displays used/total bag space using template keywords (`$used/$total`). No popup — pure handle convenience.
- **Status shelf**: Custom XP and reputation progress bars in a popup. Purple XP bar with level/percentage, green reputation bar with faction/standing. Handle shows compact template text (e.g., `Lv$level $xp%`). Hides Blizzard's status tracking bars.
- **Micro menu shelf**: Reparent Blizzard's micro menu buttons into a shelf popup. Auto-detects available buttons, native sizing, configurable rows.
- **Multi-faction tracking**: Track multiple reputations beyond Blizzard's watched faction. Hierarchical faction picker organized by expansion with search. Each tracked faction gets its own colored bar in the status popup.

### Pinned Popups
- Pin any shelf as an always-visible bar via the "Pin as bar" checkbox.
- Drag pinned popups anywhere on screen via the grip handle at the top.
- Per-shelf idle opacity with mouseover reveal (reuses dock fade pattern).
- Handle click toggles pinned popup visibility without unpinning.
- Pinned popups survive ESC, backdrop clicks, and close-others.
- Hidden during Edit Mode, restored after.

### Icon Picker
- Click the shelf icon preview to browse all WoW icons in a scrollable grid.
- 32K+ icon name database (auto-updated monthly from Townlong Yak via CI).
- Search by icon filename, spell name (from spellbook), or FileDataID.
- FauxScrollFrame virtual scrolling — only visible buttons exist in memory.
- Drag spell/item/macro onto the icon preview as an alternative.
- Right-click the icon preview to reset to auto-detect.

### Options Panel Overhaul
- **Unified "Shelves & Docks" panel**: Tree view shows docks as headers with shelves grouped underneath. Click a dock to configure its name, orientation, and appearance.
- **Simplified add buttons**: Two buttons ("+ Add Dock", "+ Add Shelf") with a type picker dropdown replacing 6 separate buttons.
- **Override Appearance**: Per-shelf checkbox to customize Open Direction, Handle Style, and handle sizing. Unchecked = inherits from global Appearance tab. Existing per-shelf customizations auto-detected and preserved.
- **Shelf Defaults in Appearance tab**: Global defaults for Open Direction and Handle Style.
- **Template label system**: Status and Bags shelves support `$keyword` placeholders in handle labels (`$level`, `$xp`, `$used`, `$total`, etc.).
- **Defaults button**: Resets shelf/dock settings with confirmation dialog.
- **Proper arrow buttons**: Blizzard scroll arrow templates for move up/down with tooltips.
- **Detail panel layout**: Title, controls row (Enabled/Move/Delete/Defaults), Pinning, then Layout & Sizing.

### Profiles & Migration
- Account-wide AceDB profiles via `BarshelfGlobalDB` with cross-character sharing.
- Automatic per-character → account-wide migration on first login per character.
- Each character's data migrates under its own profile name (no shared "Default").
- Old data preserved as fallback (marked `_migrated`, not wiped).
- Legacy `dockMouseoverHide` boolean auto-converted to `dockIdleAlpha` at runtime.
- Migration test suite with 21 assertions across 7 scenarios, runs in CI.

### Localization
- Full translations: German, French, Spanish, Brazilian Portuguese.
- Partial translations: Italian, Russian, Korean, Simplified/Traditional Chinese.
- Localized .toc Notes for all supported locales.
- All UI strings use the `L[]` localization system with metatable fallback.

### Bug Fixes
- **Custom shelf buttons not casting**: Removed `ActionButtonTemplate` interference with secure action attributes.
- **Custom shelf icon/slot misalignment**: Icons fill the full button area.
- **Drag-and-drop onto custom shelves**: Click-based drop handling as fallback.
- **Bar shelf tiny icons**: Safety floor for button size reads (< 10px → 36px fallback).
- **Shift+click no longer casts**: Secure handler bypassed via `shift-type1`/`shift-type2` attributes.
- **Edit Mode ADDON_ACTION_BLOCKED**: Deferred handlers with `C_Timer.After(0)`.
- **Dock invisible during drag**: `FadeTo(1)` properly stops running fade animation.
- **Grid blinking on mouseover**: Bar shelf watchdog throttled to 1 check/second.
- **Combat safety**: Popup anchor/stacking, SetFrameLevel, and bags Hide all guarded with `InCombatLockdown()`.
- **Popup z-ordering**: Most recently shown popup renders on top (20-level gap clears child frames).
- **Icon size mismatch**: Slider default matches native TWW button size (45px for bars).

### Infrastructure
- Custom addon logo (`assets/logo.tga`) for addon list and minimap icon.
- `TextureNames.lua`: 32K+ icon FileDataID → name mappings from Townlong Yak.
- `scripts/update-texture-names.sh`: Downloads and regenerates texture names.
- Monthly CI job auto-updates `TextureNames.lua` and opens a PR if data changed.
- Migration test suite in CI (`tests/test_migration.lua`).

---

## v1.1.0

### New Features
- **Dock idle fade**: docks can fade to a configurable opacity when idle (no popup open, mouse not hovering). Slider from 0% (fully hidden) to 100% (disabled). Configurable fade animation duration.
- **Popup stacking**: when "Close other popups" is off, multiple open popups now stack sequentially instead of overlapping. Direction follows the first popup's anchor.
- **Shift+click pickup**: shift+click or shift+drag a custom shelf button to pick up the spell/item/macro (like Blizzard action bars). Shift+right-click still clears.

### Bug Fixes
- **Custom shelf buttons not casting spells**: removed `ActionButtonTemplate` which was overriding secure action attributes via its PreClick handler. Buttons now use only `SecureActionButtonTemplate` with manual visual elements.
- **Custom shelf icon/slot misalignment**: icons now fill the full button area instead of using ActionButtonTemplate's inset positioning.
- **Drag-and-drop onto custom shelves**: added click-based drop handling as fallback, since `SecureActionButtonTemplate` consumes the event before `OnReceiveDrag` fires.
- **Bar shelf tiny icons**: added safety floor for button size reads — buttons reporting < 10px during early TWW load now fall back to 36px instead of producing broken micro-scale popups.
- **Shift+click no longer casts**: secure handler is bypassed on shift+click via `shift-type1`/`shift-type2` attributes, preventing unintended spell casts when picking up or clearing slots.

---

## v1.0.0

Initial release.

- Bar shelves: reparent Blizzard action bars 1-8 into popup grids
- Custom shelves: drag-and-drop spells, items, macros (OPie-like)
- Multiple docks with horizontal/vertical orientation
- Auto-detect Blizzard Edit Mode settings (icons, rows, size, padding)
- Popup auto-anchor with screen-edge flip
- Dock/shelf/popup appearance settings (opacity, border, padding, sizing)
- Handle display modes (icon, label, or both)
- Shelf reordering via config panel
- ESC-to-close, click-outside-to-close
- Edit Mode integration: shows original bars during Edit Mode
- Ace3 integration: AceDB profiles, Blizzard Settings panel with subcategories
- Minimap icon via LibDBIcon
- Combat-safe secure handlers and queue system
