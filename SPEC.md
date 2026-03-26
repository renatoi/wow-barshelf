# Barshelf — Feature Spec v2

## Summary

Barshelf lets WoW players hide their action bars via Edit Mode and access them through a compact floating dock. The dock contains handles (icon, label, or both) that toggle popup grids of action buttons. Two shelf types: **Bar Shelves** reparent Blizzard's own buttons (zero taint risk), and **Custom Shelves** let users assign arbitrary spells/items/macros to buttons (OPie-like). Fully compatible with 12.0.1's Secret Values combat API.

## Motivation

Players want cleaner UIs without losing quick access to action bars. Edit Mode lets you hide bars, but then those abilities are gone from screen. Barshelf brings them back on-demand — and goes further by letting users create custom button groups for spells that don't even live on a Blizzard bar.

---

## Scope

### In Scope
- **Bar Shelves**: Bars 2–8 (reparented Blizzard buttons, bulletproof in combat)
- **Custom Shelves**: User-assigned spells/items/macros (SecureActionButtons, combat execution works, cooldown display may degrade gracefully)
- Single draggable dock frame containing all handles side-by-side
- Handle display modes: label only, icon only, icon + label (configurable per shelf)
- Click-to-toggle popup grids (combat-safe via SecureHandlerClickTemplate)
- Click-outside-to-close (out of combat)
- Popup anchor: auto-flip at screen edges + per-shelf configurable direction
- Popup open/close animation (fade), configurable to disable
- Configurable per shelf: label text, button count, columns, icon size, padding, anchor
- Configurable globally: close-others behavior, animation, minimap icon
- Slash command (`/barshelf`) and minimap icon
- SavedVariables persistence (per-character)

### Out of Scope (Non-Goals)
- Bar 1 (Main Action Bar) — stance/paging complexity
- Keybind remapping — users keep their existing keybinds
- Replacing Bartender4/Dominos — this is complementary
- Titan Panel integration
- Profiles / spec-switching
- Inline macrotext on Custom Shelves (removed in 11.0; only saved macro indices)

---

## Architecture

### Bar-to-Button Mapping (Bar Shelves)

| Bar ID | Global Button Names               | Action Slots |
|--------|------------------------------------|-------------|
| 2      | `MultiBarBottomLeftButton[1-12]`   | 61–72       |
| 3      | `MultiBarRightButton[1-12]`       | 25–36       |
| 4      | `MultiBarLeftButton[1-12]`        | 37–48       |
| 5      | `MultiBarBottomRightButton[1-12]` | 49–60       |
| 6      | `MultiBar5Button[1-12]`           | —           |
| 7      | `MultiBar6Button[1-12]`           | —           |
| 8      | `MultiBar7Button[1-12]`           | —           |

### Frame Hierarchy

Users can create **multiple docks**, each independently positioned. Shelves are assigned to a dock.

```
BarshelfDock<D>  (Frame, draggable, contains its assigned handles side-by-side)
  ├── BarshelfHandle<D>_1  (SecureHandlerClickTemplate)
  │     ├── Icon texture (optional)
  │     ├── FontString label (optional)
  │     └── FrameRef → BarshelfPopup<D>_1
  ├── BarshelfHandle<D>_2
  │     └── ...
  └── BarshelfHandle<D>_N

BarshelfPopup<D>_<N>  (Frame, anchored to its handle)
  ├── Grid of action buttons (reparented Blizzard buttons OR custom SecureActionButtons)
  └── Background + border

BarshelfBackdrop  (Button, fullscreen, low strata — click-outside-to-close, out of combat only)
```

**Default**: one dock created automatically. Users add more via settings.

### Two Shelf Types

#### Bar Shelf (type = "bar")
- Reparents Blizzard's own `MultiBar*Button` frames into the popup
- Blizzard's untainted code handles cooldowns, proc glows, range checking
- **Zero taint risk** — safest option for 12.0.1
- Limited to Bars 2–8, max 12 buttons per shelf

#### Custom Shelf (type = "custom")
- Creates new `SecureActionButtonTemplate` buttons
- User assigns spells/items/macros by dragging from spellbook/bags onto popup slots (out of combat)
- Attributes set: `type="spell"`, `spell=spellID` / `type="item"`, `item=itemID` / `type="macro"`, `macro=macroIndex`
- **Execution in combat**: Works (secure template guarantees this)
- **Cooldown display**: Uses `pcall` + `issecretvalue()` checks. Graceful degradation — if cooldown data is secret, the sweep may not render but the button still functions
- **Icon display**: `C_Spell.GetSpellTexture()`, `C_Item.GetItemIconByID()` — not restricted
- User-defined button count (not tied to 12)

### Combat Safety Model

| Operation | In Combat | Out of Combat |
|-----------|-----------|---------------|
| Click handle → toggle popup | YES (secure handler) | YES |
| Click outside → close popup | NO (toggle only) | YES (backdrop) |
| Click action buttons (bar shelf) | YES (Blizzard's own) | YES |
| Click action buttons (custom shelf) | YES (SecureActionButton) | YES |
| Cooldown display (bar shelf) | YES (Blizzard handles it) | YES |
| Cooldown display (custom shelf) | DEGRADED (may not render) | YES |
| Assign spell to custom slot | NO | YES (drag from spellbook) |
| Change grid layout / settings | NO (queued) | YES |
| Reparent buttons | NO (queued) | YES |
| Drag dock to reposition | NO | YES |

### Secure Handler Snippet (toggle)

```lua
-- Set on each handle. Runs in restricted environment (combat-safe).
-- closeOthers: snippet iterates frame refs to all other popups and hides them.
local popup = self:GetFrameRef("popup")
if popup:IsShown() then
    popup:Hide()
else
    -- Close others if configured
    local i = 1
    while true do
        local other = self:GetFrameRef("otherpopup" .. i)
        if not other then break end
        if other:IsShown() then other:Hide() end
        i = i + 1
    end
    popup:Show()
end
```

### Queued Changes

When settings are modified during combat, changes are stored in a pending queue and applied on `PLAYER_REGEN_ENABLED`.

---

## Dock & Handle Design

### The Dock
- Single frame (`BarshelfDock`) containing all shelf handles arranged horizontally
- Draggable (out of combat); position saved in SavedVariables
- Subtle background + border so it's visible but not intrusive
- Handles auto-arrange: when shelves are enabled/disabled, remaining handles re-flow

### Handle Display Modes (per shelf)
- `"label"` — text only (e.g., "Bar 3")
- `"icon"` — icon only (first non-empty button's texture, or a default icon)
- `"both"` — icon + label side by side

### Handle Configuration (per shelf)
- `iconSize`: pixels (default 16)
- `labelFontSize`: points (default 12)
- Custom label text (default: "Bar N" for bar shelves, user-chosen for custom)

---

## Popup Design

### Anchor & Positioning
- **Default**: auto-detect. Popup appears below the dock. If the dock is near the bottom of the screen, popup flips above.
- **Per-shelf override**: user can set anchor direction — `BOTTOM` (below handle), `TOP` (above), `LEFT`, `RIGHT`
- Popup anchors to its specific handle within the dock

### Animation
- **Default**: fade in/out (0.15s duration)
- **Configurable**: users can disable animation (instant show/hide)
- Animation uses `UIFrameFadeIn` / `UIFrameFadeOut` (out of combat) or instant toggle (in combat, since fade functions are insecure)

### Grid Layout (per shelf)
- `numButtons`: 1–12 for bar shelves, 1–24 for custom shelves
- `columns`: buttons per row (wraps to multiple rows)
- `buttonSize`: pixels (default 36, range 24–48)
- `buttonPadding`: pixels between buttons (default 2, range 0–10)
- Background + thin border around the grid

---

## Shelf Configuration

### Bar Shelf Config

```lua
{
    type = "bar",
    barID = 3,                  -- Blizzard bar 2-8
    dockID = 1,                 -- Which dock this shelf belongs to
    enabled = true,
    label = "Action Bar 3",     -- Custom rename
    displayMode = "both",       -- "label", "icon", "both"
    iconSize = 16,
    labelFontSize = 12,
    numButtons = 12,            -- 1-12
    columns = 12,               -- Grid columns
    buttonSize = 36,            -- Pixels
    buttonPadding = 2,          -- Pixels
    popupAnchor = "AUTO",       -- "AUTO", "BOTTOM", "TOP", "LEFT", "RIGHT"
}
```

### Custom Shelf Config

```lua
{
    type = "custom",
    dockID = 1,                 -- Which dock this shelf belongs to
    enabled = true,
    label = "My Cooldowns",
    displayMode = "both",
    iconSize = 16,
    labelFontSize = 12,
    numButtons = 6,             -- 1-24
    columns = 3,
    buttonSize = 36,
    buttonPadding = 2,
    popupAnchor = "AUTO",
    buttons = {
        [1] = { type = "spell", id = 12345 },
        [2] = { type = "item",  id = 67890 },
        [3] = { type = "macro", id = 5 },
        [4] = nil,  -- empty slot
        ...
    },
}
```

### Dock Config

```lua
{
    id = 1,
    name = "Main",              -- User-renamable dock label (shown in settings, not in-game)
    point = nil,                -- Saved position {point, relPoint, x, y} or nil for default
    orientation = "HORIZONTAL", -- "HORIZONTAL" or "VERTICAL" handle arrangement
}
```

### Global Settings

```lua
{
    closeOthers = true,         -- Opening one shelf closes others (global across all docks)
    showMinimap = true,
    animatePopups = true,       -- Fade animation on popups
    animationDuration = 0.15,
    docks = {                   -- Array of dock configs
        [1] = { id = 1, name = "Main", point = nil, orientation = "HORIZONTAL" },
    },
    shelves = { ... },          -- Ordered array of shelf configs (each has dockID)
    nextDockID = 2,             -- Auto-increment for new docks
    nextShelfID = 1,            -- Auto-increment for new shelves
}
```

---

## User Interactions

### First Launch
1. Addon loads, no shelves configured. Dock is hidden (nothing to show).
2. User types `/barshelf` or clicks minimap icon → settings panel opens.
3. User adds a Bar Shelf (picks Bar 3) or a Custom Shelf → handle appears in dock.
4. User drags dock to desired position.

### Normal Usage — Bar Shelf
1. User hides action bars via Edit Mode.
2. Dock shows handles: `[icon] Bar 3` `[icon] Bar 5`.
3. Click handle → popup fades in anchored to handle, showing that bar's buttons.
4. Click abilities in popup (works in combat).
5. Click handle again or click elsewhere → popup fades out.

### Normal Usage — Custom Shelf
1. User creates a custom shelf "Potions" with 4 slots.
2. Out of combat, user opens the popup and drags potions from bags onto slots.
3. In combat, clicks potion button → uses the potion.
4. Spells/items can be dragged from spellbook the same way.

### Settings Panel (`/barshelf`)
- **Dock list** (top):
  - List of docks with rename field and orientation toggle (H/V)
  - "Add Dock" / "Delete Dock" buttons
  - Dock assignment shown per shelf
- **Shelf list** (left side):
  - Ordered list of shelves grouped by dock
  - "Add Bar Shelf" / "Add Custom Shelf" buttons
  - Enable/disable toggle per shelf
  - Delete button per shelf
  - Dock assignment dropdown per shelf
- **Shelf settings** (right side, per selected shelf):
  - Label text input
  - Display mode dropdown (Label / Icon / Both)
  - Icon size slider
  - Label font size slider
  - Number of buttons slider
  - Columns slider
  - Button size slider
  - Button padding slider
  - Popup anchor dropdown (Auto / Bottom / Top / Left / Right)
  - For bar shelves: bar ID dropdown (Bar 2–8)
  - For custom shelves: button assignment grid (drag targets)
- **Global section** (bottom):
  - "Close others when opening" checkbox
  - "Animate popups" checkbox
  - "Show minimap icon" checkbox
  - "Reset all dock positions" button

---

## Edge Cases & Failure Modes

1. **Bar not enabled in Blizzard UI**: Shelf shows anyway. Empty buttons are the user's responsibility.

2. **Enter combat while settings panel open**: Close panel. Queue pending changes.

3. **Enter combat while dragging dock**: Drop at current position. Save.

4. **Addon loaded mid-combat**: Defer all setup to `PLAYER_REGEN_ENABLED`.

5. **Same bar on two shelves**: Disallow — each Blizzard bar can only appear in one bar shelf (buttons can only have one parent). Show warning in settings.

16. **Deleting a dock with shelves**: Shelves move to dock 1 (default). Cannot delete the last dock.

17. **Empty dock** (no shelves assigned): Hide the dock frame. Show again when a shelf is assigned to it.

6. **Other addons skinning buttons** (e.g., Masque): Bar shelf buttons retain skins since they're the same frames.

7. **Disabling a bar shelf**: Reparent buttons back to original parent. Remove handle from dock.

8. **Disabling a custom shelf**: Hide custom buttons. Remove handle from dock.

9. **Logout / reload**: Save all configs, dock position, custom shelf button assignments.

10. **Close-others behavior**: Secure handler snippet iterates frame refs to hide other popups before showing current.

11. **Custom shelf cooldown display in dungeons**: If `C_Spell.GetSpellCooldown()` returns secret values, `pcall` catches the error. Button still works for clicking — only the cooldown sweep may not render.

12. **Custom shelf spell removed/changed**: On `SPELLS_CHANGED` / `BAG_UPDATE`, validate custom button assignments. Show "?" icon for invalid entries.

13. **Popup off screen**: Auto-anchor detects screen edges and flips direction. Uses `GetScreenWidth()` / `GetScreenHeight()` vs popup dimensions.

14. **Animation during combat**: Fade uses insecure API (`UIFrameFadeIn`). In combat, fall back to instant show/hide. Users won't notice — combat toggles are fast clicks anyway.

15. **Dock has no shelves**: Hide the dock frame entirely. Show again when a shelf is enabled.

---

## Acceptance Criteria

### Core
1. Dock frames appear with their assigned handles arranged per orientation (H or V).
2. Multiple docks can exist, each independently draggable. Positions persist across `/reload`.
3. Clicking a handle toggles its popup. No "Addon action blocked" errors in combat.
4. With `closeOthers=true`, opening shelf A closes all other open popups (across all docks).

### Bar Shelves
5. Enabling Bar 3 reparents `MultiBarRightButton[1-12]` into the popup grid.
6. Buttons are clickable in combat with no taint errors.
7. Cooldowns, proc glows, range coloring all work (Blizzard's code handles them).
8. Disabling the shelf returns buttons to their original Blizzard parent.

### Custom Shelves
9. User can drag a spell from spellbook onto an empty custom slot (out of combat).
10. User can drag an item from bags onto a custom slot (out of combat).
11. Custom buttons execute spells/items in combat.
12. Custom button icons display correctly.
13. Cooldown display works out of combat; gracefully degrades in combat if secret values restrict it.

### Handle Display
14. Handle modes work: label-only shows text, icon-only shows icon, both shows both.
15. Icon size and label font size are independently configurable.
16. Handles re-flow in dock when shelves are added/removed.

### Popup
17. Grid layout: columns=4, numButtons=8 → 4x2 grid.
18. Button subset: numButtons=6 shows only buttons 1–6.
19. buttonSize=24 scales buttons to 24px.
20. Auto-anchor flips popup direction when dock is near screen edge.
21. Manual anchor override (TOP/BOTTOM/LEFT/RIGHT) works.
22. Popup fades in/out when animation is enabled.
23. Animation disabled → instant show/hide.

### Settings & Persistence
24. `/barshelf` opens settings panel.
25. Minimap icon left-click opens settings.
26. All shelf configs survive `/reload` and re-login.
27. Custom shelf button assignments persist.
28. Same Blizzard bar cannot be assigned to two bar shelves (validation).

### Safety
29. No Lua errors on fresh character first load.
30. No Lua errors on `/reload` with saved config.
31. No combat taint errors in dungeons/raids (bar shelves).
32. Graceful degradation for custom shelf cooldowns under secret value restrictions.

---

## File Structure

```
Barshelf.toc            -- Addon metadata, file list
Core.lua                -- Initialization, events, saved variables, slash command, combat queue
Dock.lua                -- Dock frame, handle creation, handle layout
BarShelf.lua            -- Bar shelf: popup creation, button reparenting
CustomShelf.lua         -- Custom shelf: SecureActionButton creation, drag-to-assign, cooldown handling
Popup.lua               -- Shared popup frame logic: grid layout, anchor, animation, backdrop
Config.lua              -- Settings panel UI, minimap icon (LibDBIcon)
Libs/
  LibDataBroker-1.1/    -- LDB for minimap icon
  LibDBIcon-1.0/        -- Minimap icon rendering
  LibStub/              -- Library loader
```
