local Barshelf = LibStub("AceAddon-3.0"):GetAddon("Barshelf")
local L = Barshelf_L

---------------------------------------------------------------------------
-- Create a custom shelf (user-assigned spells / items / macros)
---------------------------------------------------------------------------
function Barshelf:CreateCustomShelf(config, index)
  local shelf = {
    config = config,
    index = index,
    type = "custom",
    buttons = {},
  }

  shelf.popup = self:CreatePopup(shelf)
  self:CreateCustomButtons(shelf)
  return shelf
end

---------------------------------------------------------------------------
-- Button creation
---------------------------------------------------------------------------
function Barshelf:CreateCustomButtons(shelf)
  if InCombatLockdown() then
    self:QueueForCombat(function()
      self:CreateCustomButtons(shelf)
    end)
    return
  end

  local config = shelf.config
  local num = config.numButtons or 6

  for i = 1, num do
    local btnName = "BarshelfCBtn_" .. (shelf.index or 0) .. "_" .. i
    -- Only SecureActionButtonTemplate — ActionButtonTemplate's PreClick
    -- overrides our type/spell attributes, preventing spells from casting
    local button = CreateFrame("Button", btnName, shelf.popup, "SecureActionButtonTemplate")
    button:SetSize(config.buttonSize or 36, config.buttonSize or 36)
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:RegisterForDrag("LeftButton")
    button.shelfIndex = i

    -- Prevent secure handler from firing on shift+click
    -- (shift+click = pickup, shift+right-click = clear)
    button:SetAttribute("shift-type1", "")
    button:SetAttribute("shift-type2", "")

    -- Visual elements (replaces ActionButtonTemplate)
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
    button.bg = bg

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    button.icon = icon

    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")

    local cd = CreateFrame("Cooldown", btnName .. "CD", button, "CooldownFrameTemplate")
    cd:SetAllPoints()
    button.cooldown = cd

    -- Apply saved action if any
    local bc = config.buttons and config.buttons[i]
    if bc then
      self:ApplyCustomAction(button, bc)
    else
      self:SetEmptySlotAppearance(button)
    end

    -- Receive drag (out-of-combat only)
    button:SetScript("OnReceiveDrag", function(btn)
      if InCombatLockdown() then
        return
      end
      self:HandleCustomDrop(shelf, i, btn)
    end)

    -- Shift+drag to pick up (like Blizzard action bars)
    button:SetScript("OnDragStart", function(btn)
      if InCombatLockdown() then
        return
      end
      if IsShiftKeyDown() then
        self:PickupCustomSlot(shelf, i, btn)
      end
    end)

    -- Handle drops and shift+click pickup/clear
    button:HookScript("OnClick", function(btn, mb)
      if InCombatLockdown() then
        return
      end
      if IsShiftKeyDown() then
        if mb == "RightButton" then
          self:ClearCustomSlot(shelf, i, btn)
        else
          self:PickupCustomSlot(shelf, i, btn)
        end
        return
      end
      -- Handle cursor drops (drag-to-assign)
      local cursorType = GetCursorInfo()
      if cursorType then
        self:HandleCustomDrop(shelf, i, btn)
      end
    end)

    -- Tooltip
    button:SetScript("OnEnter", function(btn)
      self:ShowCustomButtonTooltip(btn, shelf, i)
    end)
    button:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)

    shelf.buttons[i] = button
  end

  self:LayoutPopupButtons(shelf.popup, shelf.buttons, config)
  self:StartCooldownTimer(shelf)
end

---------------------------------------------------------------------------
-- Apply an action to a custom button
---------------------------------------------------------------------------
function Barshelf:ApplyCustomAction(button, bc)
  if InCombatLockdown() then
    return
  end

  -- Clear previous
  button:SetAttribute("type", nil)
  button:SetAttribute("spell", nil)
  button:SetAttribute("item", nil)
  button:SetAttribute("macro", nil)

  local texture
  if bc.type == "spell" and bc.id then
    button:SetAttribute("type", "spell")
    button:SetAttribute("spell", bc.id)
    texture = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(bc.id)
  elseif bc.type == "item" and bc.id then
    button:SetAttribute("type", "item")
    button:SetAttribute("item", bc.id)
    texture = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(bc.id)
  elseif bc.type == "macro" and bc.id then
    button:SetAttribute("type", "macro")
    button:SetAttribute("macro", bc.id)
    local _, iconTex = GetMacroInfo(bc.id)
    texture = iconTex
  end

  if button.icon then
    button.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    button.icon:Show()
  end
end

---------------------------------------------------------------------------
-- Empty slot look
---------------------------------------------------------------------------
function Barshelf:SetEmptySlotAppearance(button)
  if button.icon then
    button.icon:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    button.icon:Show()
    button.icon:SetDesaturated(true)
    button.icon:SetAlpha(0.35)
  end
end

function Barshelf:RestoreSlotAppearance(button)
  if button.icon then
    button.icon:SetDesaturated(false)
    button.icon:SetAlpha(1)
  end
end

---------------------------------------------------------------------------
-- Drag-and-drop handler
---------------------------------------------------------------------------
function Barshelf:HandleCustomDrop(shelf, slotIndex, button)
  local cursorType, id, subType, spellID = GetCursorInfo()
  if not cursorType then
    return
  end
  ClearCursor()

  local bc
  if cursorType == "spell" then
    -- In 12.0, GetCursorInfo for spells returns: "spell", slotIndex, "spell", spellID
    bc = { type = "spell", id = spellID or id }
  elseif cursorType == "item" then
    bc = { type = "item", id = id }
  elseif cursorType == "macro" then
    bc = { type = "macro", id = id }
  elseif cursorType == "petaction" then
    print("|cff00ccffBarshelf:|r " .. L["Pet actions are not supported."])
    return
  end

  if bc then
    shelf.config.buttons = shelf.config.buttons or {}
    shelf.config.buttons[slotIndex] = bc
    self:RestoreSlotAppearance(button)
    self:ApplyCustomAction(button, bc)

    -- Update handle icon
    local dock = self.docks[shelf.config.dockID or 1]
    if dock and shelf.handle then
      dock:UpdateHandleIcon(shelf.handle, shelf)
    end
  end
end

---------------------------------------------------------------------------
-- Pick up a slot's action onto the cursor (shift+click, like Blizzard bars)
---------------------------------------------------------------------------
function Barshelf:PickupCustomSlot(shelf, slotIndex, button)
  if InCombatLockdown() then
    return
  end
  local bc = shelf.config.buttons and shelf.config.buttons[slotIndex]
  if not bc then
    return
  end

  if bc.type == "spell" and bc.id then
    if C_Spell and C_Spell.PickupSpell then
      C_Spell.PickupSpell(bc.id)
    elseif PickupSpell then
      PickupSpell(bc.id)
    end
  elseif bc.type == "item" and bc.id then
    if C_Item and C_Item.PickupItem then
      C_Item.PickupItem(bc.id)
    elseif PickupItem then
      PickupItem(bc.id)
    end
  elseif bc.type == "macro" and bc.id then
    PickupMacro(bc.id)
  end

  self:ClearCustomSlot(shelf, slotIndex, button)
end

---------------------------------------------------------------------------
-- Clear a slot
---------------------------------------------------------------------------
function Barshelf:ClearCustomSlot(shelf, slotIndex, button)
  if InCombatLockdown() then
    return
  end

  button:SetAttribute("type", nil)
  button:SetAttribute("spell", nil)
  button:SetAttribute("item", nil)
  button:SetAttribute("macro", nil)

  if shelf.config.buttons then
    shelf.config.buttons[slotIndex] = nil
  end

  self:SetEmptySlotAppearance(button)
end

---------------------------------------------------------------------------
-- Tooltip for custom buttons
---------------------------------------------------------------------------
function Barshelf:ShowCustomButtonTooltip(button, shelf, slotIndex)
  local bc = shelf.config.buttons and shelf.config.buttons[slotIndex]
  GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
  if not bc then
    GameTooltip:AddLine(L["Empty Slot"], 0.5, 0.5, 0.5)
    GameTooltip:AddLine(L["Drag a spell, item, or macro here"], 0.7, 0.7, 0.7)
  else
    if bc.type == "spell" and bc.id then
      local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(bc.id)
      GameTooltip:AddLine(name or ("Spell #" .. bc.id), 1, 1, 1)
    elseif bc.type == "item" and bc.id then
      local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(bc.id)
      GameTooltip:AddLine(name or ("Item #" .. bc.id), 1, 1, 1)
    elseif bc.type == "macro" and bc.id then
      local name = GetMacroInfo(bc.id)
      GameTooltip:AddLine(name or ("Macro #" .. bc.id), 1, 1, 1)
    end
    GameTooltip:AddLine(L["Shift+click to pick up | Shift+Right-click to clear"], 0.5, 0.5, 0.5)
  end
  GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Cooldown updates (with 12.0.1 secret-value safety)
---------------------------------------------------------------------------
function Barshelf:StartCooldownTimer(shelf)
  if shelf.cooldownTimer then
    return
  end

  local timer = CreateFrame("Frame")
  timer.elapsed = 0
  timer:SetScript("OnUpdate", function(_, dt)
    timer.elapsed = timer.elapsed + dt
    if timer.elapsed < 0.5 then
      return
    end
    timer.elapsed = 0

    for i, button in ipairs(shelf.buttons) do
      local bc = shelf.config.buttons and shelf.config.buttons[i]
      if bc and button.cooldown then
        self:UpdateCustomCooldown(button, bc)
      end
    end
  end)
  shelf.cooldownTimer = timer
end

function Barshelf:UpdateCustomCooldown(button, bc)
  local ok = pcall(function()
    if bc.type == "spell" and bc.id then
      if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(bc.id)
        if info and info.startTime then
          button.cooldown:SetCooldown(info.startTime, info.duration)
        end
      end
    elseif bc.type == "item" and bc.id then
      if C_Item and C_Item.GetItemCooldown then
        local info = C_Item.GetItemCooldown(bc.id)
        if info and info.startTime then
          button.cooldown:SetCooldown(info.startTime, info.duration)
        end
      end
    end
  end)
  -- If pcall fails (secret values in 12.0.1), silently degrade
  if not ok and button.cooldown then
    button.cooldown:Hide()
  end
end

---------------------------------------------------------------------------
-- Deactivation
---------------------------------------------------------------------------
function Barshelf:DeactivateCustomShelf(shelf)
  if shelf.cooldownTimer then
    shelf.cooldownTimer:SetScript("OnUpdate", nil)
    shelf.cooldownTimer = nil
  end
  for _, button in ipairs(shelf.buttons) do
    if button then
      if not InCombatLockdown() then
        button:SetAttribute("type", nil)
      end
      button:Hide()
    end
  end
  wipe(shelf.buttons)
end
