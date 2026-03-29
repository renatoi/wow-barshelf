local Barshelf = LibStub("AceAddon-3.0"):GetAddon("Barshelf")
local L = Barshelf_L

---------------------------------------------------------------------------
-- Bag shelf: handle-only shelf. Clicking the handle toggles bags.
-- The popup exists only to satisfy the secure handle framework; it is
-- an invisible 1x1 frame that immediately hides itself on show.
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Template keyword system for bag handle labels
---------------------------------------------------------------------------
function Barshelf:FormatBagLabel(template)
  local totalSlots, usedSlots = 0, 0
  pcall(function()
    for bag = 0, NUM_BAG_SLOTS do
      local slots = C_Container.GetContainerNumSlots(bag)
      totalSlots = totalSlots + slots
      for slot = 1, slots do
        if C_Container.GetContainerItemInfo(bag, slot) then
          usedSlots = usedSlots + 1
        end
      end
    end
  end)
  local freeSlots = totalSlots - usedSlots

  local result = template
  result = result:gsub("%$used", tostring(usedSlots))
  result = result:gsub("%$total", tostring(totalSlots))
  result = result:gsub("%$free", tostring(freeSlots))
  return result
end

---------------------------------------------------------------------------
-- Create
---------------------------------------------------------------------------
function Barshelf:CreateBagShelf(config, index)
  if not config.label or config.label == "Bags" then
    config.label = "$used/$total"
  end

  local shelf = {
    config = config,
    index = index,
    type = "bags",
    buttons = {},
  }

  shelf.popup = self:CreatePopup(shelf)
  self:ActivateBagShelf(shelf)
  return shelf
end

---------------------------------------------------------------------------
-- Activate: wire handle click to toggle bags, register BAG_UPDATE
---------------------------------------------------------------------------
function Barshelf:ActivateBagShelf(shelf)
  -- Make the popup invisible (1x1, no backdrop)
  local popup = shelf.popup
  popup:SetSize(1, 1)
  popup:SetAlpha(0)
  popup:EnableMouse(false)

  self:HideBagContainer(shelf)

  -- Event frame for label updates
  local eventFrame = CreateFrame("Frame")
  eventFrame:RegisterEvent("BAG_UPDATE")
  eventFrame:SetScript("OnEvent", function()
    self:UpdateBagHandleLabel(shelf)
  end)
  shelf._bagEventFrame = eventFrame

  -- Deferred initial update (handle may not exist yet)
  C_Timer.After(0.1, function()
    -- Wire the handle to toggle bags on left-click
    if shelf.handle then
      shelf.handle:HookScript("OnClick", function(_, mouseButton)
        if mouseButton == "LeftButton" and not InCombatLockdown() then
          ToggleAllBags()
        end
      end)
    end
    self:UpdateBagHandleLabel(shelf)
  end)
end

---------------------------------------------------------------------------
-- Update handle label using template
---------------------------------------------------------------------------
function Barshelf:UpdateBagHandleLabel(shelf)
  if not shelf.handle then
    return
  end
  local template = shelf.config.label or "$used/$total"
  local text = self:FormatBagLabel(template)
  shelf.handle.label:SetText(text)

  -- Only re-layout handles if out of combat (LayoutHandles calls Show on secure frames)
  if not InCombatLockdown() then
    local dock = self.docks[shelf.config.dockID or 1]
    if dock then
      dock:LayoutHandles()
    end
  end
end

---------------------------------------------------------------------------
-- Hide the original Blizzard bag container
---------------------------------------------------------------------------
function Barshelf:HideBagContainer(shelf)
  local containerNames = { "BagsBar", "MicroButtonAndBagsBar", "BagBar" }
  for _, name in ipairs(containerNames) do
    local frame = _G[name]
    if frame and frame.Hide then
      shelf.hiddenBagContainer = frame
      pcall(function()
        frame:Hide()
        RegisterStateDriver(frame, "visibility", "hide")
      end)
      return
    end
  end
end

---------------------------------------------------------------------------
-- Deactivate: clean up events and restore hidden frames
---------------------------------------------------------------------------
function Barshelf:DeactivateBagShelf(shelf)
  if shelf._bagEventFrame then
    shelf._bagEventFrame:UnregisterAllEvents()
    shelf._bagEventFrame:SetScript("OnEvent", nil)
    shelf._bagEventFrame = nil
  end

  if shelf.hiddenBagContainer then
    UnregisterStateDriver(shelf.hiddenBagContainer, "visibility")
    shelf.hiddenBagContainer:Show()
    shelf.hiddenBagContainer = nil
  end
end
