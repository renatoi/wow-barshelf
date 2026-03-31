local Barshelf = LibStub("AceAddon-3.0"):GetAddon("Barshelf")
local L = Barshelf_L

---------------------------------------------------------------------------
-- Helper: safely call a function and unpack a table-or-multi return
---------------------------------------------------------------------------
local function SafeCooldown(func, ...)
  local ok, r1, r2 = pcall(func, ...)
  if not ok then
    return nil, nil
  end
  if type(r1) == "table" then
    return r1.startTime, r1.duration
  end
  return r1, r2
end

---------------------------------------------------------------------------
-- Item location cache: maps itemID -> { locType, bag, slot } or { locType, invSlot }
-- Populated out of combat; used as fast path in combat when C_Container
-- returns secret values.
---------------------------------------------------------------------------
local itemLocationCache = {}

local function CacheItemLocation(itemID)
  -- Equipped items (invSlot 0-19)
  for invSlot = 0, 19 do
    local ok, id = pcall(GetInventoryItemID, "player", invSlot)
    if ok and id == itemID then
      itemLocationCache[itemID] = { locType = "equip", invSlot = invSlot }
      return
    end
  end
  -- Bag items
  if C_Container then
    for bag = 0, 4 do
      local ok, numSlots = pcall(C_Container.GetContainerNumSlots, bag)
      if ok and numSlots then
        for slot = 1, numSlots do
          local ok2, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
          if ok2 and info and info.itemID == itemID then
            itemLocationCache[itemID] = { locType = "bag", bag = bag, slot = slot }
            return
          end
        end
      end
    end
  end
end

local function FindItemCooldown(itemID)
  local loc = itemLocationCache[itemID]

  -- Fast path: use cached location (works in combat)
  if loc then
    local st, dur
    if loc.locType == "equip" then
      st, dur = SafeCooldown(GetInventoryItemCooldown, "player", loc.invSlot)
    elseif loc.locType == "bag" then
      st, dur = SafeCooldown(C_Container.GetContainerItemCooldown, loc.bag, loc.slot)
    end
    if st then
      return st, dur
    end
  end

  -- Slow path: scan (only reliable out of combat due to secret values)
  if not InCombatLockdown() then
    CacheItemLocation(itemID)
    loc = itemLocationCache[itemID]
    if loc then
      if loc.locType == "equip" then
        return SafeCooldown(GetInventoryItemCooldown, "player", loc.invSlot)
      elseif loc.locType == "bag" then
        return SafeCooldown(C_Container.GetContainerItemCooldown, loc.bag, loc.slot)
      end
    end
  end

  return nil, nil
end

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
    cd:SetDrawSwipe(true)
    cd:SetDrawEdge(true)
    cd:SetSwipeColor(0, 0, 0, 0.8)
    cd:SetHideCountdownNumbers(false)
    button.cooldown = cd

    local hotkey = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    hotkey:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    hotkey:SetJustifyH("LEFT")
    button.hotkey = hotkey

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
  self:ApplyKeybinds(shelf)
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
  button:SetAttribute("macrotext", nil)

  local texture
  if bc.type == "spell" and bc.id then
    button:SetAttribute("type", "spell")
    button:SetAttribute("spell", bc.id)
    texture = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(bc.id)
  elseif bc.type == "item" and bc.id then
    button:SetAttribute("type", "item")
    button:SetAttribute("item", "item:" .. bc.id)
    texture = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(bc.id)
  elseif bc.type == "macro" and bc.id then
    button:SetAttribute("type", "macro")
    button:SetAttribute("macro", bc.id)
    local _, iconTex = GetMacroInfo(bc.id)
    texture = iconTex
  elseif bc.type == "mount" and bc.id then
    local name, spellID, icon = C_MountJournal.GetMountInfoByID(bc.id)
    if name then
      button:SetAttribute("type", "macro")
      button:SetAttribute("macrotext", "/cast " .. name)
    end
    texture = icon
  elseif bc.type == "battlepet" and bc.id then
    local _, customName, _, _, _, _, _, petName, petIcon = C_PetJournal.GetPetInfoByPetID(bc.id)
    if petName then
      button:SetAttribute("type", "macro")
      button:SetAttribute("macrotext", "/summonpet " .. (customName or petName))
    end
    texture = petIcon
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
  elseif cursorType == "mount" then
    bc = { type = "mount", id = id }
  elseif cursorType == "battlepet" then
    bc = { type = "battlepet", id = id } -- id = petGUID (string)
  elseif cursorType == "petaction" then
    print("|cff00ccffBarshelf:|r " .. L["Pet actions are not supported."])
    return
  end

  if bc then
    shelf.config.buttons = shelf.config.buttons or {}
    shelf.config.buttons[slotIndex] = bc
    self:RestoreSlotAppearance(button)
    self:ApplyCustomAction(button, bc)
    self:SyncProxy(shelf, slotIndex, button)

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
  elseif bc.type == "mount" and bc.id then
    local _, spellID = C_MountJournal.GetMountInfoByID(bc.id)
    if spellID and C_Spell and C_Spell.PickupSpell then
      C_Spell.PickupSpell(spellID)
    end
  elseif bc.type == "battlepet" and bc.id then
    if C_PetJournal and C_PetJournal.PickupPet then
      C_PetJournal.PickupPet(bc.id)
    end
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
  button:SetAttribute("macrotext", nil)

  -- Clear proxy attributes too
  local proxy = shelf.proxyButtons and shelf.proxyButtons[slotIndex]
  if proxy then
    proxy:SetAttribute("type", nil)
    proxy:SetAttribute("spell", nil)
    proxy:SetAttribute("item", nil)
    proxy:SetAttribute("macro", nil)
    proxy:SetAttribute("macrotext", nil)
  end

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
    elseif bc.type == "mount" and bc.id then
      local name = C_MountJournal.GetMountInfoByID(bc.id)
      GameTooltip:AddLine(name or ("Mount #" .. bc.id), 1, 1, 1)
    elseif bc.type == "battlepet" and bc.id then
      local _, customName, _, _, _, _, _, petName = C_PetJournal.GetPetInfoByPetID(bc.id)
      GameTooltip:AddLine(customName or petName or tostring(bc.id), 1, 1, 1)
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

  local function UpdateAll()
    -- Get GCD info via spell 61304 (official GCD reference spell per Blizzard docs)
    local gcdInfo
    if C_Spell and C_Spell.GetSpellCooldown then
      local ok, info = pcall(C_Spell.GetSpellCooldown, 61304)
      if ok then
        gcdInfo = info
      end
    end

    for i, button in ipairs(shelf.buttons) do
      local bc = shelf.config.buttons and shelf.config.buttons[i]
      if bc and button.cooldown then
        self:UpdateCustomCooldown(button, bc, gcdInfo)
      end
    end
  end

  -- Polling fallback for long cooldowns (trinkets, potions, etc.)
  timer:SetScript("OnUpdate", function(_, dt)
    timer.elapsed = timer.elapsed + dt
    if timer.elapsed < 0.5 then
      return
    end
    timer.elapsed = 0
    UpdateAll()
  end)

  -- Event-driven updates catch the GCD instantly
  timer:RegisterEvent("SPELL_UPDATE_COOLDOWN")
  timer:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
  timer:SetScript("OnEvent", function()
    UpdateAll()
  end)

  shelf.cooldownTimer = timer
end

-- Apply cooldown to a Cooldown widget from a SpellCooldownInfo table.
-- Returns true if a cooldown was displayed, false otherwise.
-- In 12.0.1, cooldown numeric values (startTime, duration) can be secret
-- during combat. Addon code CANNOT pass secret values to any C function
-- (SetCooldown, SetTimeFromStart, CooldownFrame_Set all reject them).
-- We use issecretvalue() to detect this and gracefully degrade.
local function ApplySpellCooldown(cd, spellID)
  if not (C_Spell and C_Spell.GetSpellCooldown) then
    return false
  end
  local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
  if not ok or not info or not info.isActive then
    return false
  end
  -- isActive is true — there IS a cooldown. Check if values are secret.
  if issecretvalue(info.startTime) then
    return false -- combat secret — can't display from addon code
  end
  cd:SetCooldown(info.startTime, info.duration, info.modRate)
  return true
end

function Barshelf:UpdateCustomCooldown(button, bc, gcdInfo)
  -- Branch on isActive (boolean, never secret) to decide show vs clear.
  -- When isActive=true but values are secret (combat), gracefully skip
  -- (12.0.1 limitation: addon code cannot pass secrets to display APIs).
  -- When values are not secret (out of combat), display normally via SetCooldown.
  local cd = button.cooldown

  if bc.type == "spell" and bc.id then
    if ApplySpellCooldown(cd, bc.id) then
      return
    end
  elseif bc.type == "item" and bc.id then
    if C_Item and C_Item.GetItemCooldown then
      local ok, st, dur, enable = pcall(C_Item.GetItemCooldown, bc.id)
      if ok and st and enable and enable ~= 0 and not issecretvalue(st) then
        cd:SetCooldown(st, dur)
        return
      end
    end
  elseif bc.type == "mount" and bc.id then
    local ok, _, spellID = pcall(C_MountJournal.GetMountInfoByID, bc.id)
    if ok and spellID and ApplySpellCooldown(cd, spellID) then
      return
    end
  elseif bc.type == "macro" or bc.type == "battlepet" then
    if gcdInfo and gcdInfo.isActive and not issecretvalue(gcdInfo.startTime) then
      cd:SetCooldown(gcdInfo.startTime, gcdInfo.duration, gcdInfo.modRate)
      return
    end
  end

  cd:Clear()
end

---------------------------------------------------------------------------
-- Keybinding support — proxy buttons + override bindings
---------------------------------------------------------------------------
local KEYBIND_ABBREVS = {
  ["CTRL%-"] = "c",
  ["SHIFT%-"] = "s",
  ["ALT%-"] = "a",
  ["NUMPAD"] = "N",
}

local function FormatKeybindText(key)
  if not key then
    return ""
  end
  local text = key
  for pattern, abbr in pairs(KEYBIND_ABBREVS) do
    text = text:gsub(pattern, abbr)
  end
  return text
end

function Barshelf:SyncProxy(shelf, slotIndex, button)
  if InCombatLockdown() then
    return
  end
  local proxy = shelf.proxyButtons and shelf.proxyButtons[slotIndex]
  if not proxy then
    return
  end
  for _, attr in ipairs({ "type", "spell", "item", "macro", "macrotext" }) do
    proxy:SetAttribute(attr, button:GetAttribute(attr))
  end
end

function Barshelf:ApplyKeybinds(shelf)
  if InCombatLockdown() then
    return
  end

  ClearOverrideBindings(shelf.popup)
  shelf.proxyButtons = shelf.proxyButtons or {}

  for i, button in ipairs(shelf.buttons) do
    local key = shelf.config.keybinds and shelf.config.keybinds[i]

    -- Create proxy if it doesn't exist yet
    local proxyName = "BarshelfCBtnProxy_" .. (shelf.index or 0) .. "_" .. i
    local proxy = shelf.proxyButtons[i]
    if not proxy then
      proxy = CreateFrame("Button", proxyName, UIParent, "SecureActionButtonTemplate")
      proxy:SetSize(1, 1)
      proxy:SetAlpha(0)
      proxy:EnableMouse(false)
      proxy:Show()
      shelf.proxyButtons[i] = proxy
    end

    -- Mirror action attributes from popup button to proxy
    self:SyncProxy(shelf, i, button)

    -- Set the override binding
    if key then
      SetOverrideBindingClick(shelf.popup, false, key, proxyName)
    end

    -- Update keybind label on the popup button
    if button.hotkey then
      button.hotkey:SetText(FormatKeybindText(key))
    end
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

  -- Clear keybind overrides
  if shelf.popup and not InCombatLockdown() then
    ClearOverrideBindings(shelf.popup)
  end

  -- Hide and clean up proxy buttons
  if shelf.proxyButtons then
    for _, proxy in pairs(shelf.proxyButtons) do
      if proxy then
        if not InCombatLockdown() then
          proxy:SetAttribute("type", nil)
        end
        proxy:Hide()
      end
    end
    wipe(shelf.proxyButtons)
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
