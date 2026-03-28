local Barshelf = LibStub("AceAddon-3.0"):GetAddon("Barshelf")

local POPUP_INSET = 6

---------------------------------------------------------------------------
-- Create a popup frame for a shelf
---------------------------------------------------------------------------
function Barshelf:CreatePopup(shelf)
  local name = "BarshelfPopup_" .. (shelf.index or 0)
  -- SecureHandlerStateTemplate so the handle's secure snippet can Show/Hide it in combat
  local popup = CreateFrame("Frame", name, UIParent, "SecureHandlerStateTemplate, BackdropTemplate")
  popup:SetFrameStrata("DIALOG")
  popup:SetFrameLevel(10)
  popup:SetClampedToScreen(true)
  popup:Hide()

  popup:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  popup:SetBackdropColor(0.05, 0.05, 0.05, Barshelf.db.profile.popupBgAlpha or 0.92)
  popup:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)

  -- Prevent mouse-through to the backdrop
  popup:EnableMouse(true)

  -- Fade-in animation group (replaces removed UIFrameFadeIn)
  local fadeIn = popup:CreateAnimationGroup()
  local alphaAnim = fadeIn:CreateAnimation("Alpha")
  alphaAnim:SetFromAlpha(0)
  alphaAnim:SetToAlpha(1)
  alphaAnim:SetDuration(0.15)
  alphaAnim:SetSmoothing("OUT")
  -- WoW reverts alpha to the pre-animation value when an AnimationGroup finishes;
  -- pin it to 1 so the popup stays visible after the fade completes.
  fadeIn:SetScript("OnFinished", function()
    popup:SetAlpha(1)
  end)
  popup.fadeIn = fadeIn

  -- OnShow: fade-in + show backdrop + stacking + dock alpha
  popup:HookScript("OnShow", function(frame)
    if not InCombatLockdown() then
      if Barshelf.db.profile.animatePopups then
        frame:SetAlpha(0)
        alphaAnim:SetDuration(Barshelf.db.profile.animationDuration or 0.15)
        fadeIn:Play()
      end
      if Barshelf.backdrop then
        Barshelf.backdrop:Show()
      end
      if Barshelf.escHelper then
        Barshelf.escHelper:Show()
      end
    end

    local dockID = frame.shelf and frame.shelf.config.dockID or 1
    local dock = Barshelf.docks[dockID]

    if Barshelf.db.profile.stackPopups and not Barshelf.db.profile.closeOthers and dock then
      Barshelf:LayoutDockPopups(dock)
    else
      Barshelf:UpdatePopupAnchor(frame)
    end

    if dock and dock.UpdateMouseoverAlpha then
      dock:UpdateMouseoverAlpha()
    end
  end)

  -- OnHide: manage backdrop + re-stack + dock alpha
  popup:HookScript("OnHide", function()
    if not InCombatLockdown() then
      if not Barshelf:AnyPopupShown() then
        if Barshelf.backdrop then
          Barshelf.backdrop:Hide()
        end
        if Barshelf.escHelper then
          Barshelf.escHelper:Hide()
        end
      end
    end

    local dockID = popup.shelf and popup.shelf.config.dockID or 1
    local dock = Barshelf.docks[dockID]

    -- Re-stack remaining popups after this one hides
    if Barshelf.db.profile.stackPopups and not Barshelf.db.profile.closeOthers and dock then
      C_Timer.After(0, function()
        if not InCombatLockdown() then
          Barshelf:LayoutDockPopups(dock)
        end
      end)
    end

    -- Dock mouseover alpha (SetAlpha is safe in combat)
    if dock and dock.UpdateMouseoverAlpha then
      dock:UpdateMouseoverAlpha()
    end
  end)

  popup.shelf = shelf
  shelf.popup = popup
  return popup
end

---------------------------------------------------------------------------
-- Anchor logic with auto-flip
---------------------------------------------------------------------------
function Barshelf:UpdatePopupAnchor(popup)
  if InCombatLockdown() then
    return
  end
  local shelf = popup.shelf
  if not shelf or not shelf.handle then
    return
  end

  local config = shelf.config
  local handle = shelf.handle
  local anchor = config.popupAnchor or "AUTO"

  if anchor == "AUTO" then
    local scale = handle:GetEffectiveScale()
    local _, hy = handle:GetCenter()
    hy = (hy or 0) * scale
    local sh = GetScreenHeight() * UIParent:GetEffectiveScale()

    -- Estimate popup height
    local num = config.numButtons or 12
    local rows = config.numRows or 1
    local bsz = config.buttonSize or 36
    local bpad = config.buttonPadding or 2
    local ph = rows * (bsz + bpad) - bpad + POPUP_INSET * 2

    anchor = (hy - ph < 0) and "TOP" or "BOTTOM"
  end

  popup._resolvedAnchor = anchor
  popup:ClearAllPoints()
  if anchor == "BOTTOM" then
    popup:SetPoint("TOP", handle, "BOTTOM", 0, -2)
  elseif anchor == "TOP" then
    popup:SetPoint("BOTTOM", handle, "TOP", 0, 2)
  elseif anchor == "LEFT" then
    popup:SetPoint("RIGHT", handle, "LEFT", -2, 0)
  elseif anchor == "RIGHT" then
    popup:SetPoint("LEFT", handle, "RIGHT", 2, 0)
  end
end

---------------------------------------------------------------------------
-- Stack visible popups for a dock (when stackPopups is on)
---------------------------------------------------------------------------
function Barshelf:LayoutDockPopups(dock)
  if InCombatLockdown() then
    self:QueueForCombat(function()
      self:LayoutDockPopups(dock)
    end)
    return
  end
  if not dock or not dock.orderedShelves then
    return
  end

  local visiblePopups = {}
  for _, shelf in ipairs(dock.orderedShelves) do
    if shelf.popup and shelf.popup:IsShown() then
      visiblePopups[#visiblePopups + 1] = shelf.popup
    end
  end

  if #visiblePopups == 0 then
    return
  end

  -- First popup: anchor to its handle using standard logic
  self:UpdatePopupAnchor(visiblePopups[1])
  local stackDir = visiblePopups[1]._resolvedAnchor or "BOTTOM"

  -- Subsequent popups: stack relative to previous
  local GAP = 2
  for i = 2, #visiblePopups do
    local prev = visiblePopups[i - 1]
    local curr = visiblePopups[i]
    curr:ClearAllPoints()
    curr._resolvedAnchor = stackDir

    if stackDir == "BOTTOM" then
      curr:SetPoint("TOP", prev, "BOTTOM", 0, -GAP)
    elseif stackDir == "TOP" then
      curr:SetPoint("BOTTOM", prev, "TOP", 0, GAP)
    elseif stackDir == "LEFT" then
      curr:SetPoint("RIGHT", prev, "LEFT", -GAP, 0)
    elseif stackDir == "RIGHT" then
      curr:SetPoint("LEFT", prev, "RIGHT", GAP, 0)
    end
  end
end

---------------------------------------------------------------------------
-- Lay out buttons inside a popup
---------------------------------------------------------------------------
function Barshelf:LayoutPopupButtons(popup, buttons, config)
  if InCombatLockdown() then
    self:QueueForCombat(function()
      self:LayoutPopupButtons(popup, buttons, config)
    end)
    return
  end

  local num = config.numButtons or #buttons
  local nRows = config.numRows or 1
  local cols = math.ceil(num / math.max(nRows, 1))
  local bsz = config.buttonSize or 36
  local bpad = config.buttonPadding or 2
  local stride = bsz + bpad
  local rows = math.ceil(math.max(num, 1) / cols)

  popup:SetSize(cols * stride - bpad + POPUP_INSET * 2, rows * stride - bpad + POPUP_INSET * 2)

  local total = math.max(num, #buttons)
  for i = 1, total do
    local button = buttons[i]
    if not button then -- skip nil holes
    elseif i <= num then
      local row = math.floor((i - 1) / cols)
      local col = (i - 1) % cols
      local x = POPUP_INSET + col * stride
      local y = -POPUP_INSET - row * stride

      button:SetParent(popup)
      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", popup, "TOPLEFT", x, y)
      button:SetSize(bsz, bsz)
      button:Show()
    else
      button:Hide()
    end
  end
end
