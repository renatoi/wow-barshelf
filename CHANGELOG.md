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
