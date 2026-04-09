local ADDON_NAME, ns = ...

ns.SettingsTab = {}

local contentFrame = nil

function ns.SettingsTab.Create(parent)
    contentFrame = CreateFrame("Frame", nil, parent)
    contentFrame:SetAllPoints()

    local y = -10

    -- Header
    local header = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, y)
    header:SetText("Settings")
    y = y - 30

    -- Sync enabled toggle
    local syncCheck = CreateFrame("CheckButton", "PSCSyncEnabled", contentFrame, "InterfaceOptionsCheckButtonTemplate")
    syncCheck:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, y)
    syncCheck.Text:SetText("Enable Sync")
    syncCheck:SetChecked(ns.DB.settings.syncEnabled)
    syncCheck:SetScript("OnClick", function(self)
        ns.DB.settings.syncEnabled = self:GetChecked()
        if ns.DB.settings.syncEnabled then
            ns.Print("Sync enabled")
        else
            ns.Print("Sync disabled — no data will be sent or received")
        end
    end)
    y = y - 30

    -- TSM adapter toggle
    local tsmCheck = CreateFrame("CheckButton", "PSCEnableTSM", contentFrame, "InterfaceOptionsCheckButtonTemplate")
    tsmCheck:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, y)
    tsmCheck.Text:SetText("Enable TSM Integration")
    tsmCheck:SetChecked(ns.DB.settings.enableTSM)
    tsmCheck:SetScript("OnClick", function(self)
        ns.DB.settings.enableTSM = self:GetChecked()
    end)
    y = y - 30

    -- CraftSim adapter toggle
    local csCheck = CreateFrame("CheckButton", "PSCEnableCraftSim", contentFrame, "InterfaceOptionsCheckButtonTemplate")
    csCheck:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, y)
    csCheck.Text:SetText("Enable CraftSim Integration")
    csCheck:SetChecked(ns.DB.settings.enableCraftSim)
    csCheck:SetScript("OnClick", function(self)
        ns.DB.settings.enableCraftSim = self:GetChecked()
    end)
    y = y - 30

    -- Debug toggle
    local debugCheck = CreateFrame("CheckButton", "PSCDebugMode", contentFrame, "InterfaceOptionsCheckButtonTemplate")
    debugCheck:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, y)
    debugCheck.Text:SetText("Debug Mode")
    debugCheck:SetChecked(ns.DB.settings.debug)
    debugCheck:SetScript("OnClick", function(self)
        ns.DB.settings.debug = self:GetChecked()
        ns.debug = ns.DB.settings.debug
    end)
    y = y - 40

    -- Your Account Key (show first so they can share it)
    local keyHeader = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    keyHeader:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, y)
    keyHeader:SetText("|cffffd100Your Account Key|r")
    y = y - 18

    -- Copyable key field
    local keyBox = CreateFrame("EditBox", "PSCAccountKeyBox", contentFrame, "InputBoxTemplate")
    keyBox:SetSize(400, 20)
    keyBox:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 15, y)
    keyBox:SetAutoFocus(false)
    keyBox:SetText(ns.DB.localAccount.accountKey or "unknown")
    keyBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    keyBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    -- Prevent editing — read-only, just for copying
    keyBox:SetScript("OnTextChanged", function(self)
        self:SetText(ns.DB.localAccount.accountKey or "unknown")
    end)
    y = y - 18

    local shareNote = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    shareNote:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, y)
    shareNote:SetText("Share this key with your friend. They paste it below to sync with you.")
    y = y - 30

    -- Add Friend's Key section
    local peerHeader = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    peerHeader:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, y)
    peerHeader:SetText("|cffffd100Add Friend's Key|r")
    y = y - 20

    local addPeerBox = CreateFrame("EditBox", "PSCAddPeerBox", contentFrame, "InputBoxTemplate")
    addPeerBox:SetSize(300, 20)
    addPeerBox:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 15, y)
    addPeerBox:SetAutoFocus(false)
    addPeerBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local addPeerBtn = CreateFrame("Button", nil, contentFrame, "UIPanelButtonTemplate")
    addPeerBtn:SetSize(100, 22)
    addPeerBtn:SetPoint("LEFT", addPeerBox, "RIGHT", 8, 0)
    addPeerBtn:SetText("Add Peer")
    addPeerBtn:SetScript("OnClick", function()
        local key = addPeerBox:GetText():trim()
        if key == "" then
            ns.Print("Enter a friend's account key first.")
            return
        end
        if key == ns.DB.localAccount.accountKey then
            ns.Print("That's your own key!")
            return
        end
        ns.DB.settings.trustedPeers[key] = true
        ns.Print("Added trusted peer: %s", key)
        addPeerBox:SetText("")
        addPeerBox:ClearFocus()
        ns.SettingsTab.Refresh()
    end)
    y = y - 30

    -- Current trusted peers list
    local trustedHeader = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    trustedHeader:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, y)
    trustedHeader:SetText("|cffffd100Trusted Peers|r")
    y = y - 18

    contentFrame.peerListLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    contentFrame.peerListLabel:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 15, y)
    contentFrame.peerListLabel:SetWidth(500)
    contentFrame.peerListLabel:SetJustifyH("LEFT")
    y = y - 40

    -- Remove peer button
    local removePeerBox = CreateFrame("EditBox", "PSCRemovePeerBox", contentFrame, "InputBoxTemplate")
    removePeerBox:SetSize(300, 20)
    removePeerBox:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 15, y)
    removePeerBox:SetAutoFocus(false)
    removePeerBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local removePeerBtn = CreateFrame("Button", nil, contentFrame, "UIPanelButtonTemplate")
    removePeerBtn:SetSize(110, 22)
    removePeerBtn:SetPoint("LEFT", removePeerBox, "RIGHT", 8, 0)
    removePeerBtn:SetText("Remove Peer")
    removePeerBtn:SetScript("OnClick", function()
        local key = removePeerBox:GetText():trim()
        if key == "" then return end
        if ns.DB.settings.trustedPeers[key] then
            ns.DB.settings.trustedPeers[key] = nil
            ns.Print("Removed trusted peer: %s", key)
        else
            ns.Print("Key not found in trusted peers.")
        end
        removePeerBox:SetText("")
        removePeerBox:ClearFocus()
        ns.SettingsTab.Refresh()
    end)
    y = y - 40

    -- Reset button
    local resetBtn = CreateFrame("Button", nil, contentFrame, "UIPanelButtonTemplate")
    resetBtn:SetSize(150, 24)
    resetBtn:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 10, y)
    resetBtn:SetText("Reset All Data")
    resetBtn:SetScript("OnClick", function()
        StaticPopup_Show("PSC_CONFIRM_RESET")
    end)

    -- Confirmation dialog
    StaticPopupDialogs["PSC_CONFIRM_RESET"] = {
        text = "Reset all Profession Supply Chain data? This cannot be undone.",
        button1 = "Reset",
        button2 = "Cancel",
        OnAccept = function()
            ns.SavedVariables.ResetAll()
            ReloadUI()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    return contentFrame
end

function ns.SettingsTab.Refresh()
    if not contentFrame or not contentFrame.peerListLabel then return end

    local peerList = {}
    for key in pairs(ns.DB.settings.trustedPeers) do
        local displayName = ns.ItemUtil.GetAccountDisplayName(key)
        peerList[#peerList + 1] = string.format("  %s  |cff888888(%s)|r", displayName, key)
    end

    if #peerList > 0 then
        contentFrame.peerListLabel:SetText(table.concat(peerList, "\n"))
    else
        contentFrame.peerListLabel:SetText("  |cff888888No peers added — accepting all connections|r")
    end
end
