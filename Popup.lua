local Barshelf = LibStub("AceAddon-3.0"):GetAddon("Barshelf")
local L = Barshelf_L

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

  -- OnShow: raise to top + fade-in + show backdrop + stacking + dock alpha
  popup:HookScript("OnShow", function(frame)
    -- Bag shelves use an invisible popup; hide immediately and skip all logic
    if frame.shelf and frame.shelf.config.type == "bags" then
      if not InCombatLockdown() then
        frame:Hide()
      end
      return
    end

    -- Raise above other popups (gap of 20 clears child frame levels)
    -- SetFrameLevel is protected on secure frames during combat
    if not InCombatLockdown() then
      Barshelf._popupZCounter = (Barshelf._popupZCounter or 10) + 20
      frame:SetFrameLevel(Barshelf._popupZCounter)
    end
    local isPinned = frame.shelf and frame.shelf.config.pinned

    if not InCombatLockdown() and not isPinned then
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

    if isPinned then
      -- Restore saved position when re-shown via handle toggle
      if not InCombatLockdown() then
        local pt = frame.shelf and frame.shelf.config.pinnedPoint
        if pt then
          frame:ClearAllPoints()
          frame:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
        end
      end
      if frame.UpdatePinnedAlpha then
        frame:UpdatePinnedAlpha()
      end
    else
      -- Anchor/stacking requires SetPoint which is protected on secure frames
      if not InCombatLockdown() then
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
      end
    end
  end)

  -- OnHide: manage backdrop + re-stack + dock alpha
  popup:HookScript("OnHide", function()
    local isPinned = popup.shelf and popup.shelf.config.pinned

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

    -- Cancel pinned fade timer
    if popup._pinnedFadeTimer then
      popup._pinnedFadeTimer:Cancel()
      popup._pinnedFadeTimer = nil
    end

    if not isPinned then
      local dockID = popup.shelf and popup.shelf.config.dockID or 1
      local dock = Barshelf.docks[dockID]

      if Barshelf.db.profile.stackPopups and not Barshelf.db.profile.closeOthers and dock then
        C_Timer.After(0, function()
          if not InCombatLockdown() then
            Barshelf:LayoutDockPopups(dock)
          end
        end)
      end

      if dock and dock.UpdateMouseoverAlpha then
        dock:UpdateMouseoverAlpha()
      end
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
  local anchor
  if config.overrideAppearance then
    anchor = config.popupAnchor or "AUTO"
  else
    anchor = Barshelf.db.profile.defaultPopupAnchor or "AUTO"
  end

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
    if shelf.popup and shelf.popup:IsShown() and not shelf.config.pinned then
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
-- Pinned popup: drag + fade setup
---------------------------------------------------------------------------
function Barshelf:SetupPopupPinning(shelf)
  local popup = shelf.popup
  if not popup or not shelf.config.pinned then
    return
  end

  -- Already set up (e.g., after RebuildAll re-calls ShowPinnedPopups)
  if popup._pinnedSetup then
    if popup.UpdatePinnedAlpha then
      popup:UpdatePinnedAlpha()
    end
    return
  end
  popup._pinnedSetup = true

  -- Drag via grip child frame (avoids OnUpdate conflict with bar shelf watchdog)
  popup:SetMovable(true)

  local grip = CreateFrame("Frame", nil, popup)
  grip:SetHeight(12)
  grip:SetPoint("TOPLEFT", popup, "TOPLEFT", 3, -3)
  grip:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -3, -3)
  grip:EnableMouse(true)
  grip:RegisterForDrag("LeftButton")

  -- Grip dot pattern (same style as dock grip)
  for row = 0, 1 do
    for col = 0, 2 do
      local dot = grip:CreateTexture(nil, "ARTWORK")
      dot:SetSize(2, 2)
      dot:SetColorTexture(0.5, 0.5, 0.5, 0.7)
      dot:SetPoint("CENTER", grip, "CENTER", (col - 1) * 4, (0.5 - row) * 4)
    end
  end

  grip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(L["Drag to move"], 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  local dragTicker = CreateFrame("Frame")
  local function BeginPopupDrag()
    if InCombatLockdown() or popup._isDragging then
      return
    end
    popup._isDragging = true
    popup:SetAlpha(1)
    local scale = popup:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    popup._dragOffsetX = cx / scale - (popup:GetLeft() or 0)
    popup._dragOffsetY = cy / scale - (popup:GetTop() or 0)
    dragTicker:SetScript("OnUpdate", function()
      if not popup._isDragging then
        return
      end
      local s = popup:GetEffectiveScale()
      local mx, my = GetCursorPosition()
      popup:ClearAllPoints()
      popup:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", mx / s - popup._dragOffsetX, my / s - popup._dragOffsetY)
    end)
  end
  local function EndPopupDrag()
    if not popup._isDragging then
      return
    end
    popup._isDragging = false
    dragTicker:SetScript("OnUpdate", nil)
    local point, _, relPoint, x, y = popup:GetPoint()
    if point then
      shelf.config.pinnedPoint = { point, relPoint, x, y }
    end
    if popup.UpdatePinnedAlpha then
      popup:UpdatePinnedAlpha()
    end
  end

  grip:SetScript("OnDragStart", BeginPopupDrag)
  grip:SetScript("OnDragStop", EndPopupDrag)
  popup._pinnedGrip = grip
  popup._pinnedDragTicker = dragTicker

  -- Fade animation group (separate from the open fade-in animation)
  local fg = popup:CreateAnimationGroup()
  local fa = fg:CreateAnimation("Alpha")
  fa:SetSmoothing("OUT")
  fg:SetScript("OnFinished", function()
    popup:SetAlpha(popup._pinnedTargetAlpha or 1)
  end)
  popup._pinnedFadeGroup = fg
  popup._pinnedFadeAnim = fa

  function popup:PinnedFadeTo(targetAlpha)
    if self._pinnedTargetAlpha == targetAlpha then
      if self._pinnedFadeGroup and self._pinnedFadeGroup:IsPlaying() then
        return
      end
      if math.abs(self:GetAlpha() - targetAlpha) < 0.01 then
        return
      end
    end
    self._pinnedTargetAlpha = targetAlpha
    local duration = Barshelf.db.profile.dockFadeDuration or 0.3
    if self._pinnedFadeGroup:IsPlaying() then
      self._pinnedFadeGroup:Stop()
      self:SetAlpha(self:GetAlpha())
    end
    local current = self:GetAlpha()
    if math.abs(current - targetAlpha) < 0.01 then
      self:SetAlpha(targetAlpha)
      return
    end
    if duration <= 0 then
      self:SetAlpha(targetAlpha)
      return
    end
    self._pinnedFadeAnim:SetFromAlpha(current)
    self._pinnedFadeAnim:SetToAlpha(targetAlpha)
    self._pinnedFadeAnim:SetDuration(duration)
    self._pinnedFadeGroup:Play()
  end

  function popup:UpdatePinnedAlpha()
    local idleAlpha = shelf.config.popupIdleAlpha or 1.0
    if self._pinnedFadeTimer then
      self._pinnedFadeTimer:Cancel()
      self._pinnedFadeTimer = nil
    end
    if idleAlpha >= 1.0 then
      self:PinnedFadeTo(1)
      return
    end
    if self._isDragging then
      self:PinnedFadeTo(1)
      return
    end
    if self:IsMouseOver() then
      self:PinnedFadeTo(1)
      self._pinnedFadeTimer = C_Timer.NewTimer(0.2, function()
        self._pinnedFadeTimer = nil
        self:UpdatePinnedAlpha()
      end)
    else
      self:PinnedFadeTo(idleAlpha)
    end
  end

  -- Wire enter/leave for fade
  popup:HookScript("OnEnter", function(self)
    if self.UpdatePinnedAlpha and shelf.config.pinned then
      self:UpdatePinnedAlpha()
    end
  end)
  popup:HookScript("OnLeave", function(self)
    if self.UpdatePinnedAlpha and shelf.config.pinned then
      self:UpdatePinnedAlpha()
    end
  end)

  popup:UpdatePinnedAlpha()
end

function Barshelf:CleanupPopupPinning(shelf)
  local popup = shelf.popup
  if not popup then
    return
  end

  if popup._pinnedFadeTimer then
    popup._pinnedFadeTimer:Cancel()
    popup._pinnedFadeTimer = nil
  end
  if popup._pinnedGrip then
    popup._pinnedGrip:Hide()
  end
  if popup._pinnedDragTicker then
    popup._pinnedDragTicker:SetScript("OnUpdate", nil)
  end
  if popup._pinnedFadeGroup and popup._pinnedFadeGroup:IsPlaying() then
    popup._pinnedFadeGroup:Stop()
  end
  popup:SetAlpha(1)
  popup._pinnedSetup = nil
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
