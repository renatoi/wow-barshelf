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
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
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

    -- OnShow: fade-in + show backdrop
    popup:HookScript("OnShow", function(frame)
        if not InCombatLockdown() then
            if Barshelf.db.profile.animatePopups then
                frame:SetAlpha(0)
                alphaAnim:SetDuration(Barshelf.db.profile.animationDuration or 0.15)
                fadeIn:Play()
            end
            if Barshelf.backdrop then Barshelf.backdrop:Show() end
            if Barshelf.escHelper then Barshelf.escHelper:Show() end
        end
        Barshelf:UpdatePopupAnchor(frame)
    end)

    -- OnHide: manage backdrop
    popup:HookScript("OnHide", function()
        if not InCombatLockdown() then
            if not Barshelf:AnyPopupShown() then
                if Barshelf.backdrop then Barshelf.backdrop:Hide() end
                if Barshelf.escHelper then Barshelf.escHelper:Hide() end
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
    if InCombatLockdown() then return end
    local shelf = popup.shelf
    if not shelf or not shelf.handle then return end

    local config  = shelf.config
    local handle  = shelf.handle
    local anchor  = config.popupAnchor or "AUTO"

    if anchor == "AUTO" then
        local scale = handle:GetEffectiveScale()
        local _, hy  = handle:GetCenter()
        hy = (hy or 0) * scale
        local sh = GetScreenHeight() * UIParent:GetEffectiveScale()

        -- Estimate popup height
        local num  = config.numButtons or 12
        local rows = config.numRows or 1
        local bsz  = config.buttonSize or 36
        local bpad = config.buttonPadding or 2
        local ph   = rows * (bsz + bpad) - bpad + POPUP_INSET * 2

        anchor = (hy - ph < 0) and "TOP" or "BOTTOM"
    end

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
-- Lay out buttons inside a popup
---------------------------------------------------------------------------
function Barshelf:LayoutPopupButtons(popup, buttons, config)
    if InCombatLockdown() then
        self:QueueForCombat(function() self:LayoutPopupButtons(popup, buttons, config) end)
        return
    end

    local num    = config.numButtons    or #buttons
    local nRows  = config.numRows       or 1
    local cols   = math.ceil(num / math.max(nRows, 1))
    local bsz    = config.buttonSize    or 36
    local bpad   = config.buttonPadding or 2
    local stride = bsz + bpad
    local rows   = math.ceil(math.max(num, 1) / cols)

    popup:SetSize(
        cols * stride - bpad + POPUP_INSET * 2,
        rows * stride - bpad + POPUP_INSET * 2
    )

    local total = math.max(num, #buttons)
    for i = 1, total do
        local button = buttons[i]
        if not button then -- skip nil holes
        elseif i <= num then
            local row = math.floor((i - 1) / cols)
            local col = (i - 1) % cols
            local x =  POPUP_INSET + col * stride
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
