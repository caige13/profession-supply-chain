local ADDON_NAME, ns = ...

ns.MailHelper = {}

local fillButton = nil
local statusText = nil
local mailQueue = {}       -- list of { itemID, quantity } remaining to send
local currentBatch = {}    -- items being attached in current mail
local pendingLogItems = {} -- items attached in current fill sequence for logging
local currentRecipient = nil
local mailIndex = 0        -- which mail we're on (1/3, 2/3, etc.)
local totalMails = 0
local isAttaching = false

function ns.MailHelper.Initialize()
    ns.Events.Register("MAIL_SHOW", function()
        ns.MailHelper.OnMailboxOpened()
    end, "MailHelper")

    ns.Events.Register("MAIL_CLOSED", function()
        ns.MailHelper.OnMailboxClosed()
    end, "MailHelper")

    ns.Events.Register("MAIL_SUCCESS", function()
        ns.MailHelper.OnMailSent()
    end, "MailHelper")
end

function ns.MailHelper.OnMailboxOpened()
    if not fillButton then
        ns.MailHelper.CreateUI()
    end
    fillButton:Show()
    ns.MailHelper.UpdateButtonState()
end

function ns.MailHelper.OnMailboxClosed()
    if fillButton then
        fillButton:Hide()
    end
    if statusText then
        statusText:Hide()
    end
    ns.MailHelper.ResetState()
end

function ns.MailHelper.CreateUI()
    -- "Fill Recommended Items" button on the send mail frame
    fillButton = CreateFrame("Button", "PSCMailFillButton", SendMailFrame, "UIPanelButtonTemplate")
    fillButton:SetSize(180, 26)
    fillButton:SetPoint("BOTTOMLEFT", SendMailFrame, "BOTTOMLEFT", 10, 35)
    fillButton:SetText("Fill Recommended Items")
    fillButton:SetScript("OnClick", function()
        ns.MailHelper.OnFillClicked()
    end)
    fillButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Profession Supply Chain", 1, 1, 1)
        GameTooltip:AddLine("Fill attachment slots with items recommended by the action plan.", nil, nil, nil, true)
        GameTooltip:AddLine("You must click Send manually.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    fillButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Status text below the button
    statusText = SendMailFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("TOPLEFT", fillButton, "BOTTOMLEFT", 0, -4)
    statusText:SetWidth(200)
    statusText:SetJustifyH("LEFT")
    statusText:Hide()
end

function ns.MailHelper.UpdateButtonState()
    if not fillButton then return end

    -- Check if there's a recipient typed
    local recipient = SendMailNameEditBox:GetText():trim()

    if recipient ~= "" then
        -- Check if this recipient is a known character in the network
        local transfers = ns.MailHelper.GetTransfersForRecipient(recipient)
        if #transfers > 0 then
            fillButton:SetText(string.format("Fill Items for %s", recipient))
            fillButton:Enable()
        else
            fillButton:SetText("Fill Recommended Items")
            fillButton:Enable()
        end
    else
        -- No recipient — suggest next transfer from action plan
        local nextTransfer = ns.ActionPlanner.GetNextTransfer()
        if nextTransfer then
            fillButton:SetText(string.format("Fill for %s", nextTransfer.destination or "?"))
            fillButton:Enable()
        else
            fillButton:SetText("No Recommended Transfers")
            fillButton:Disable()
        end
    end
end

function ns.MailHelper.OnFillClicked()
    local recipient = SendMailNameEditBox:GetText():trim()
    local transfers = {}

    if recipient ~= "" then
        transfers = ns.MailHelper.GetTransfersForRecipient(recipient)
    else
        -- Use the next transfer from the action plan
        local nextTransfer = ns.ActionPlanner.GetNextTransfer()
        if nextTransfer then
            recipient = ns.MailHelper.CharKeyToName(nextTransfer.destination)
            transfers = { nextTransfer }
            -- Pre-fill the recipient name
            SendMailNameEditBox:SetText(recipient)
        end
    end

    if #transfers == 0 then
        ns.Print("No recommended items to send to this character.")
        return
    end

    -- Build the full item queue
    mailQueue = {}
    for _, transfer in ipairs(transfers) do
        mailQueue[#mailQueue + 1] = {
            itemID = transfer.itemID,
            quantity = transfer.quantity,
            itemName = transfer.itemName,
        }
    end

    currentRecipient = recipient
    mailIndex = 0
    totalMails = math.ceil(ns.MailHelper.CountTotalStacks(mailQueue) / ns.Config.MAX_MAIL_ATTACHMENTS)

    -- Fill the first batch
    ns.MailHelper.FillNextBatch()
end

function ns.MailHelper.FillNextBatch()
    if #mailQueue == 0 then
        ns.MailHelper.SetStatus("|cff00ff00All recommended items have been attached and sent.|r")
        return
    end

    mailIndex = mailIndex + 1
    isAttaching = true

    local totalAttached = 0

    for i = #mailQueue, 1, -1 do
        if totalAttached >= ns.Config.MAX_MAIL_ATTACHMENTS then
            break
        end

        local item = mailQueue[i]
        local slotsLeft = ns.Config.MAX_MAIL_ATTACHMENTS - totalAttached
        local attached = ns.MailHelper.AttachItemFromBags(item.itemID, item.quantity, slotsLeft)

        if attached > 0 then
            totalAttached = totalAttached + attached
            -- Track what was attached for mail log
            local sentQty = item.quantity
            pendingLogItems[#pendingLogItems + 1] = {
                itemID = item.itemID,
                itemName = item.itemName,
                quantity = sentQty,
            }
            -- AttachItemFromBags returns stacks attached, estimate quantity sent
            item.quantity = item.quantity - sentQty  -- assume all sent for now
            if item.quantity <= 0 then
                table.remove(mailQueue, i)
            end
        end
    end

    isAttaching = false

    -- Update status
    if totalAttached == 0 then
        ns.MailHelper.SetStatus("|cffff4444No matching items found in bags.|r")
    elseif #mailQueue > 0 then
        local remainingMails = math.ceil(ns.MailHelper.CountTotalStacks(mailQueue) / ns.Config.MAX_MAIL_ATTACHMENTS)
        ns.MailHelper.SetStatus(string.format(
            "Mail %d — %d items attached. Send when ready.\n%d more mail(s) queued.",
            mailIndex, totalAttached, remainingMails))
    else
        ns.MailHelper.SetStatus(string.format(
            "Mail %d — %d items attached. Send when ready.\nThis is the last mail.",
            mailIndex, totalAttached))
    end
end

-- Attach items of a given itemID from bags into mail slots
-- Returns the number of stacks attached
function ns.MailHelper.AttachItemFromBags(itemID, maxQuantity, maxSlots)
    local attached = 0
    local quantityRemaining = maxQuantity
    maxSlots = maxSlots or ns.Config.MAX_MAIL_ATTACHMENTS

    -- Scan bags 0-4 + reagent bag (5)
    local reagentBag = Enum.BagIndex and Enum.BagIndex.ReagentBag or 5
    local bagsToScan = { 0, 1, 2, 3, 4, reagentBag }
    for _, bag in ipairs(bagsToScan) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            if quantityRemaining <= 0 then return attached end

            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID and not info.isLocked then
                local stackCount = info.stackCount
                if stackCount <= quantityRemaining then
                    -- Pick up entire stack
                    C_Container.PickupContainerItem(bag, slot)
                    ClickSendMailItemButton()
                    quantityRemaining = quantityRemaining - stackCount
                    attached = attached + 1
                else
                    -- Split stack
                    C_Container.SplitContainerItem(bag, slot, quantityRemaining)
                    ClickSendMailItemButton()
                    quantityRemaining = 0
                    attached = attached + 1
                end

                if attached >= maxSlots then
                    return attached
                end
            end
        end
    end

    return attached
end

function ns.MailHelper.OnMailSent()
    -- Log this mail send
    if currentRecipient and #pendingLogItems > 0 then
        local charKey = ns.CharacterScanner.GetCurrentCharacterKey()
        ns.MailHelper.RecordMailLog(charKey, currentRecipient, pendingLogItems)

        -- Optimistically credit recipient's inventory so optimizer still sees materials
        local recipientKey = ns.MailHelper.FindCharacterKey(currentRecipient)
        if recipientKey then
            for _, item in ipairs(pendingLogItems) do
                ns.InventoryIndex.AdjustPendingMail(item.itemID, recipientKey, item.quantity)
            end
            ns.ResourceAllocator.InvalidateCache()
            ns.CraftSimPlanner.InvalidateCache()
            ns.Debug("MailHelper: optimistic inventory update for %s (%d items)", recipientKey, #pendingLogItems)
        end

        wipe(pendingLogItems)
    end

    if #mailQueue > 0 then
        -- Wait a moment for bags to update, then fill next batch
        C_Timer.After(0.5, function()
            ns.MailHelper.FillNextBatch()
        end)
    else
        ns.MailHelper.SetStatus("|cff00ff00All recommended items sent!|r")
        C_Timer.After(3, function()
            ns.MailHelper.ResetState()
        end)
    end
end

function ns.MailHelper.RecordMailLog(sender, recipient, items)
    if not ns.DB.mailLog then ns.DB.mailLog = {} end
    local entry = {
        timestamp = ns.TimeUtil.Now(),
        sender = sender or "Unknown",
        recipient = recipient or "Unknown",
        items = {},
    }
    for _, item in ipairs(items) do
        entry.items[#entry.items + 1] = {
            itemID = item.itemID,
            itemName = item.itemName or "",
            quantity = item.quantity or 0,
        }
    end
    ns.DB.mailLog[#ns.DB.mailLog + 1] = entry
    -- Cap at 200 entries
    while #ns.DB.mailLog > 200 do
        table.remove(ns.DB.mailLog, 1)
    end
    ns.Events.Fire("PSC_MAIL_LOGGED", entry)
end

function ns.MailHelper.ResetState()
    wipe(mailQueue)
    wipe(currentBatch)
    wipe(pendingLogItems)
    currentRecipient = nil
    mailIndex = 0
    totalMails = 0
    isAttaching = false
    if statusText then
        statusText:Hide()
    end
    ns.MailHelper.UpdateButtonState()
end

function ns.MailHelper.SetStatus(text)
    if statusText then
        statusText:SetText(text)
        statusText:Show()
    end
end

-- Get transfers where the destination matches the recipient name
function ns.MailHelper.GetTransfersForRecipient(recipientName)
    local currentChar = ns.CharacterScanner.GetCurrentCharacterKey()
    if not currentChar then return {} end

    local plan = ns.ActionPlanner.GeneratePlan()
    local transfers = {}

    recipientName = recipientName:lower()

    for _, action in ipairs(plan) do
        if action.actionType == "transfer" and action.source == currentChar then
            local destName = ns.MailHelper.CharKeyToName(action.destination):lower()
            if destName == recipientName or (action.destination and action.destination:lower():find(recipientName, 1, true)) then
                transfers[#transfers + 1] = action
            end
        end
    end

    return transfers
end

-- Resolve a bare character name to a full "Name-Realm" key by searching known characters
function ns.MailHelper.FindCharacterKey(recipientName)
    if not recipientName or recipientName == "" then return nil end
    local lowerName = recipientName:lower()

    -- Check local characters
    for charKey in pairs(ns.DB.localScans.characters) do
        local name = charKey:match("^(.+)-")
        if name and name:lower() == lowerName then
            return charKey
        end
    end

    -- Check network characters
    for _, snapshot in pairs(ns.DB.networkSnapshots) do
        if snapshot.characters then
            for charKey in pairs(snapshot.characters) do
                local name = charKey:match("^(.+)-")
                if name and name:lower() == lowerName then
                    return charKey
                end
            end
        end
    end

    return nil
end

-- Extract character name from "Name-Realm" key
function ns.MailHelper.CharKeyToName(charKey)
    if not charKey then return "" end
    local name = charKey:match("^(.+)-")
    return name or charKey
end

-- Count total stacks needed for a queue of items
function ns.MailHelper.CountTotalStacks(queue)
    local count = 0
    for _, item in ipairs(queue) do
        -- Estimate stacks (simplified: 1 stack per item entry)
        count = count + 1
    end
    return count
end

-- Hook the recipient editbox to update button state when changed
local function hookRecipientBox()
    if SendMailNameEditBox then
        SendMailNameEditBox:HookScript("OnTextChanged", function()
            if not isAttaching then
                ns.MailHelper.UpdateButtonState()
            end
        end)
    end
end

-- Defer the hook until SendMailFrame exists
local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
hookFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    C_Timer.After(2, hookRecipientBox)
end)
