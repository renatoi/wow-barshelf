local Barshelf = LibStub("AceAddon-3.0"):GetAddon("Barshelf")

---------------------------------------------------------------------------
-- Micro menu shelf: reparent Blizzard's micro buttons into a popup grid.
---------------------------------------------------------------------------

-- Ordered list of micro button frame names (TWW 12.0.x)
-- Checked dynamically; missing buttons are skipped.
Barshelf.MICRO_BUTTON_NAMES = {
  "CharacterMicroButton",
  "ProfessionMicroButton",
  "PlayerSpellsMicroButton",
  "SpellbookMicroButton",
  "TalentMicroButton",
  "AchievementMicroButton",
  "QuestLogMicroButton",
  "GuildMicroButton",
  "LFDMicroButton",
  "CollectionsMicroButton",
  "EJMicroButton",
  "HelpMicroButton",
  "StoreMicroButton",
  "MainMenuMicroButton",
}

function Barshelf:CreateMicroShelf(config, index)
  local shelf = {
    config = config,
    index = index,
    type = "micro",
    buttons = {},
    originalParents = {},
    originalPoints = {},
    originalScales = {},
  }

  shelf.popup = self:CreatePopup(shelf)
  self:ActivateMicroShelf(shelf)
  return shelf
end

---------------------------------------------------------------------------
-- Activate: reparent micro buttons into our popup
---------------------------------------------------------------------------
function Barshelf:ActivateMicroShelf(shelf)
  if InCombatLockdown() then
    self:QueueForCombat(function()
      self:ActivateMicroShelf(shelf)
    end)
    return
  end

  wipe(shelf.buttons)

  local idx = 0
  for _, name in ipairs(self.MICRO_BUTTON_NAMES) do
    local button = _G[name]
    if button then
      idx = idx + 1
      shelf.originalParents[idx] = button:GetParent()
      shelf.originalScales[idx] = button:GetScale()
      local n = button:GetNumPoints()
      if n > 0 then
        shelf.originalPoints[idx] = { button:GetPoint(1) }
      end

      RegisterStateDriver(button, "visibility", "show")
      button._barshelfManaged = true
      shelf.buttons[idx] = button
    end
  end

  -- Always use actual count (micro buttons are fixed, not user-configurable)
  shelf.config.numButtons = idx
  self:LayoutMicroPopup(shelf)

  -- Watchdog: Blizzard's UpdateMicroButtonsParent() aggressively reparents
  -- micro buttons. Re-assert our parenting every frame (out of combat).
  local popup = shelf.popup
  local buttons = shelf.buttons
  popup:SetScript("OnUpdate", function()
    if InCombatLockdown() then
      return
    end
    for _, btn in pairs(buttons) do
      if btn and btn._barshelfManaged then
        if btn:GetParent() ~= popup then
          btn:SetParent(popup)
        end
        if not btn:IsShown() then
          btn:Show()
        end
      end
    end
  end)

  -- Hide the original micro menu container if possible
  self:HideMicroMenuContainer(shelf)
end

---------------------------------------------------------------------------
-- Hide the original Blizzard micro menu container
---------------------------------------------------------------------------
function Barshelf:HideMicroMenuContainer(shelf)
  -- TWW uses MicroMenuContainer or MicroMenu; try known frame names
  local containerNames = { "MicroMenuContainer", "MicroMenu", "MicroButtonAndBagsBar" }
  for _, name in ipairs(containerNames) do
    local frame = _G[name]
    if frame and frame.Hide then
      shelf.hiddenMicroContainer = frame
      frame:Hide()
      RegisterStateDriver(frame, "visibility", "hide")
      return
    end
  end
end

---------------------------------------------------------------------------
-- Layout micro buttons in a grid at their native size
---------------------------------------------------------------------------
local MICRO_POPUP_INSET = 4

function Barshelf:LayoutMicroPopup(shelf)
  if InCombatLockdown() then
    self:QueueForCombat(function()
      self:LayoutMicroPopup(shelf)
    end)
    return
  end

  local config = shelf.config
  local popup = shelf.popup
  local buttons = shelf.buttons
  local num = #buttons
  local numRows = config.numRows or 1
  local cols = math.ceil(num / math.max(numRows, 1))
  local bpad = config.buttonPadding or 0

  -- Read native size from the first button
  local nativeW, nativeH = 28, 36
  for i = 1, num do
    if buttons[i] then
      local w, h = buttons[i]:GetWidth(), buttons[i]:GetHeight()
      if w > 10 then
        nativeW = w
      end
      if h > 10 then
        nativeH = h
      end
      break
    end
  end

  -- No scaling — use native button dimensions
  popup:SetScale(1)

  local strideX = nativeW + bpad
  local strideY = nativeH + bpad
  local rows = math.ceil(math.max(num, 1) / cols)

  popup:SetSize(cols * strideX - bpad + MICRO_POPUP_INSET * 2, rows * strideY - bpad + MICRO_POPUP_INSET * 2)

  for i = 1, num do
    local button = buttons[i]
    if button then
      local row = math.floor((i - 1) / cols)
      local col = (i - 1) % cols
      local x = MICRO_POPUP_INSET + col * strideX
      local y = -MICRO_POPUP_INSET - row * strideY

      button:SetParent(popup)
      button:SetScale(1)
      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", popup, "TOPLEFT", x, y)
      button:Show()
    end
  end
end

---------------------------------------------------------------------------
-- Deactivate: return micro buttons to their original parent
---------------------------------------------------------------------------
function Barshelf:DeactivateMicroShelf(shelf)
  if InCombatLockdown() then
    self:QueueForCombat(function()
      self:DeactivateMicroShelf(shelf)
    end)
    return
  end

  -- Restore the original container
  if shelf.hiddenMicroContainer then
    UnregisterStateDriver(shelf.hiddenMicroContainer, "visibility")
    shelf.hiddenMicroContainer:Show()
    shelf.hiddenMicroContainer = nil
  end

  -- Remove watchdog
  shelf.popup:SetScript("OnUpdate", nil)
  shelf.popup:SetScale(1)

  for i = 1, #shelf.buttons do
    local button = shelf.buttons[i]
    if button then
      button._barshelfManaged = nil
      UnregisterStateDriver(button, "visibility")
      button:SetScale(shelf.originalScales[i] or 1)
      local origParent = shelf.originalParents[i]
      if origParent then
        button:SetParent(origParent)
      end
      local origPt = shelf.originalPoints[i]
      if origPt then
        button:ClearAllPoints()
        button:SetPoint(unpack(origPt))
      end
    end
  end

  wipe(shelf.buttons)
  wipe(shelf.originalParents)
  wipe(shelf.originalPoints)
  wipe(shelf.originalScales)
end
