local Barshelf = LibStub("AceAddon-3.0"):GetAddon("Barshelf")

---------------------------------------------------------------------------
-- Bar shelves reparent Blizzard's own action buttons at their native size.
-- No resizing, no chrome stripping — Blizzard's code handles cooldowns,
-- usability, range coloring, and proc highlights natively (including in
-- combat where addon code can't read "secret values").
---------------------------------------------------------------------------
function Barshelf:CreateBarShelf(config, index)
  local shelf = {
    config = config,
    index = index,
    type = "bar",
    buttons = {},
    originalParents = {},
    originalPoints = {},
    originalScales = {},
  }

  shelf.popup = self:CreatePopup(shelf)
  self:ActivateBarShelf(shelf)
  return shelf
end

---------------------------------------------------------------------------
-- Activate: reparent Blizzard buttons into our popup at native size
---------------------------------------------------------------------------
function Barshelf:ActivateBarShelf(shelf)
  if InCombatLockdown() then
    self:QueueForCombat(function()
      self:ActivateBarShelf(shelf)
    end)
    return
  end

  local info = self.BAR_INFO[shelf.config.barID]
  if not info then
    return
  end

  wipe(shelf.buttons)

  -- Use config.numButtons directly (set by AddBarShelf from Edit Mode state).
  -- Don't re-check IsShown() here — during early load (OnEnable), Blizzard's
  -- bars may not be shown yet, which would give blizzardCount=0.
  local num = shelf.config.numButtons or info.count

  for i = 1, num do
    local button = _G[info.prefix .. i]
    if button then
      shelf.originalParents[i] = button:GetParent()
      shelf.originalScales[i] = button:GetScale()
      local n = button:GetNumPoints()
      if n > 0 then
        shelf.originalPoints[i] = { button:GetPoint(1) }
      end

      -- Prevent Blizzard's bar management from hiding reparented buttons
      RegisterStateDriver(button, "visibility", "show")
      button._barshelfManaged = true

      shelf.buttons[i] = button
    end
  end

  self:LayoutBarPopup(shelf)

  -- Force Blizzard's update on occupied buttons to clear stale icons.
  -- Skip empty buttons — UpdateAction hides them, breaking the showgrid
  -- state that keeps empty slots visible during drag operations.
  local function RefreshAllButtons()
    for _, button in pairs(shelf.buttons) do
      pcall(function()
        if not HasAction(button.action or 0) then
          return
        end
        if button.UpdateAction then
          button:UpdateAction()
        elseif button.Update then
          button:Update()
        elseif ActionButton_Update then
          ActionButton_Update(button)
        end
      end)
    end
  end

  RefreshAllButtons()

  -- Also refresh every time the popup opens (icons may go stale
  -- while the popup is hidden due to Blizzard's event handlers)
  shelf.popup:HookScript("OnShow", function()
    C_Timer.After(0, function()
      if not InCombatLockdown() then
        RefreshAllButtons()
      end
    end)
  end)

  -- Forward grid show/hide to reparented buttons: since buttons are no
  -- longer children of the action bar, they miss Blizzard's ShowGrid
  -- broadcast when the player picks up a spell. Listen for the events
  -- and manually show/hide empty buttons to match native behavior.
  local popup = shelf.popup
  local buttons = shelf.buttons

  local gridHandler = CreateFrame("Frame")
  gridHandler:RegisterEvent("ACTIONBAR_SHOWGRID")
  gridHandler:RegisterEvent("ACTIONBAR_HIDEGRID")
  gridHandler:SetScript("OnEvent", function(_, event)
    -- Defer to next frame: the event fires inside a secure call chain
    -- (e.g. PickupSpellBookItem), so calling Show/ShowGrid on secure
    -- frames would cause ADDON_ACTION_BLOCKED.
    C_Timer.After(0, function()
      if InCombatLockdown() then
        return
      end
      for _, btn in pairs(buttons) do
        if btn and btn._barshelfManaged and not HasAction(btn.action or 0) then
          if event == "ACTIONBAR_SHOWGRID" then
            if btn.ShowGrid then
              btn:ShowGrid()
            else
              btn:Show()
            end
          else
            if btn.HideGrid then
              btn:HideGrid()
            else
              btn:Hide()
            end
          end
        end
      end
    end)
  end)
  shelf._gridHandler = gridHandler

  -- Watchdog: re-assert parenting if Blizzard moves buttons back.
  -- Throttled to once per second to avoid fighting with Blizzard's
  -- own button updates.
  local watchdogElapsed = 0
  popup:SetScript("OnUpdate", function(_, dt)
    watchdogElapsed = watchdogElapsed + dt
    if watchdogElapsed < 1 then
      return
    end
    watchdogElapsed = 0
    if InCombatLockdown() then
      return
    end
    for _, btn in pairs(buttons) do
      if btn and btn._barshelfManaged then
        if btn:GetParent() ~= popup then
          btn:SetParent(popup)
        end
      end
    end
  end)

  -- Hide the original Blizzard bar frame
  if info.frame then
    local barFrame = _G[info.frame]
    if barFrame then
      shelf.hiddenBarFrame = barFrame
      shelf.barFrameWasShown = barFrame:IsShown()
      barFrame:Hide()
      RegisterStateDriver(barFrame, "visibility", "hide")
      -- Aggressively re-hide if Blizzard's code tries to show the bar frame
      -- (TWW 12.0 action bar system can override state drivers in some cases)
      barFrame._barshelfHidden = true
      if not barFrame._barshelfHooked then
        barFrame:HookScript("OnShow", function(frame)
          if frame._barshelfHidden and not InCombatLockdown() then
            frame:Hide()
          end
        end)
        barFrame._barshelfHooked = true
      end
    end
  end
end

---------------------------------------------------------------------------
-- Layout bar buttons in a grid. Uses SetScale to resize Blizzard buttons
-- uniformly (icon, border, cooldown all scale together).
---------------------------------------------------------------------------
local BAR_POPUP_INSET = 4

function Barshelf:LayoutBarPopup(shelf)
  if InCombatLockdown() then
    self:QueueForCombat(function()
      self:LayoutBarPopup(shelf)
    end)
    return
  end

  local config = shelf.config
  local popup = shelf.popup
  local buttons = shelf.buttons
  local numRows = config.numRows or 1
  local cols = math.ceil((config.numButtons or 12) / math.max(numRows, 1))
  local num = config.numButtons or 12
  local bpad = config.buttonPadding or 2

  -- Read the first button's native size (guard against uninitialized frames
  -- reporting 0 during early load — TWW overhauled the action bar system)
  local nativeSize = 36
  for i = 1, num do
    if buttons[i] then
      local w, h = buttons[i]:GetWidth(), buttons[i]:GetHeight()
      if w > 10 or h > 10 then
        nativeSize = math.max(w, h)
      end
      break
    end
  end

  -- Scale the POPUP frame itself (like Bartender4 does).
  -- Buttons are positioned at native coordinates inside it.
  -- This avoids SetScale/SetPoint offset confusion on individual buttons.
  local targetSize = config.buttonSize or nativeSize
  local popupScale = targetSize / nativeSize

  local stride = nativeSize + bpad
  local rows = math.ceil(math.max(num, 1) / cols)

  popup:SetScale(popupScale)
  popup:SetSize(cols * stride - bpad + BAR_POPUP_INSET * 2, rows * stride - bpad + BAR_POPUP_INSET * 2)

  -- Resolve row order: per-shelf override > global setting > auto-detected
  local rowOrder = config.rowOrder or Barshelf.db.profile.barRowOrder or "auto"
  local bottomUp
  if rowOrder == "bottomup" then
    bottomUp = true
  elseif rowOrder == "topdown" then
    bottomUp = false
  else -- "auto": use what was detected from Blizzard's layout
    bottomUp = config.bottomUp or false
  end

  for i = 1, #buttons do
    local button = buttons[i]
    if not button then
    elseif i <= num then
      local row = math.floor((i - 1) / cols)
      if bottomUp then
        row = rows - 1 - row
      end
      local col = (i - 1) % cols
      local x = BAR_POPUP_INSET + col * stride
      local y = -BAR_POPUP_INSET - row * stride

      button:SetParent(popup)
      button:SetScale(1)
      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", popup, "TOPLEFT", x, y)
      button:Show()
    else
      button:Hide()
    end
  end
end

---------------------------------------------------------------------------
-- Deactivate: return buttons to their original parent
---------------------------------------------------------------------------
function Barshelf:DeactivateBarShelf(shelf)
  if InCombatLockdown() then
    self:QueueForCombat(function()
      self:DeactivateBarShelf(shelf)
    end)
    return
  end

  -- Restore the original Blizzard bar frame (always show it —
  -- if the shelf is being removed, the user wants the bar back)
  if shelf.hiddenBarFrame then
    shelf.hiddenBarFrame._barshelfHidden = nil
    UnregisterStateDriver(shelf.hiddenBarFrame, "visibility")
    shelf.hiddenBarFrame:Show()
    shelf.hiddenBarFrame = nil
    shelf.barFrameWasShown = nil
  end

  -- Remove watchdog, grid handler, and reset popup scale
  shelf.popup:SetScript("OnUpdate", nil)
  shelf.popup:SetScale(1)
  if shelf._gridHandler then
    shelf._gridHandler:UnregisterAllEvents()
    shelf._gridHandler = nil
  end

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
