local ADDON_NAME, ns = ...

ns.MainFrame = {}

local frame = nil
local tabs = {}
local activeTab = nil

local TAB_DEFINITIONS = {
    { name = "Overview",     key = "overview",     module = "OverviewTab" },
    { name = "Simulation",   key = "simulation",   module = "SimulationTab" },
    { name = "Inventory",    key = "inventory",    module = "InventoryTab" },
    { name = "Accounts",     key = "accounts",     module = "AccountsTab" },
    { name = "Bottlenecks",  key = "bottlenecks",  module = "BottlenecksTab" },
    { name = "Actions",      key = "actions",      module = "ActionsTab" },
    { name = "Settings",     key = "settings",     module = "SettingsTab" },
    { name = "Debug",        key = "debug",        module = "DebugTab" },
}

function ns.MainFrame.Initialize()
    -- Auto-refresh active tab when data changes
    ns.Events.Register("PSC_MERGE_UPDATED", function()
        ns.MainFrame.RefreshActiveTab()
    end, "MainFrame")

    ns.Events.Register("PSC_SIMULATION_COMPLETE", function()
        ns.MainFrame.RefreshActiveTab()
    end, "MainFrame")
end

local function createMainFrame()
    frame = CreateFrame("Frame", "PSCMainFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(880, 550)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("HIGH")

    -- Only the title bar area is draggable (not the whole frame)
    local dragBar = CreateFrame("Frame", nil, frame)
    dragBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    dragBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    dragBar:SetHeight(25)
    dragBar:EnableMouse(true)
    dragBar:RegisterForDrag("LeftButton")
    dragBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    dragBar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    -- Title
    frame.TitleText:SetText("Profession Supply Chain v" .. ns.VERSION)

    -- Tab buttons
    local tabButtonWidth = 100
    local tabStartX = 10

    for i, tabDef in ipairs(TAB_DEFINITIONS) do
        local tabButton = CreateFrame("Button", "PSCTab" .. tabDef.key, frame, "UIPanelButtonTemplate")
        tabButton:SetSize(tabButtonWidth, 24)
        tabButton:SetPoint("TOPLEFT", frame, "TOPLEFT", tabStartX + (i - 1) * (tabButtonWidth + 4), -55)
        tabButton:SetText(tabDef.name)
        tabButton:SetScript("OnClick", function()
            ns.MainFrame.SelectTab(tabDef.key)
        end)

        tabs[tabDef.key] = {
            button = tabButton,
            definition = tabDef,
            content = nil,
            initialized = false,
        }
    end

    -- Content area
    frame.contentArea = CreateFrame("Frame", nil, frame)
    frame.contentArea:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -85)
    frame.contentArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)

    -- Close behavior
    frame:SetScript("OnHide", function()
        frame:StopMovingOrSizing()
    end)

    tinsert(UISpecialFrames, "PSCMainFrame")
end

function ns.MainFrame.SelectTab(tabKey)
    -- Hide all tab content
    for key, tab in pairs(tabs) do
        if tab.content then
            tab.content:Hide()
        end
        tab.button:SetEnabled(key ~= tabKey)
    end

    local tab = tabs[tabKey]
    if not tab then return end

    -- Lazy-initialize tab content
    if not tab.initialized then
        local module = ns[tab.definition.module]
        if module and module.Create then
            tab.content = module.Create(frame.contentArea)
            tab.initialized = true
        end
    end

    -- Show and refresh
    if tab.content then
        tab.content:Show()
        local module = ns[tab.definition.module]
        if module and module.Refresh then
            module.Refresh()
        end
    end

    activeTab = tabKey
end

function ns.MainFrame.Toggle()
    if not frame then
        createMainFrame()
        frame:Show()
        ns.MainFrame.SelectTab("overview")
    elseif frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        if activeTab then
            ns.MainFrame.SelectTab(activeTab)
        else
            ns.MainFrame.SelectTab("overview")
        end
    end
end

function ns.MainFrame.Show()
    if not frame then
        createMainFrame()
    end
    frame:Show()
    if not activeTab then
        ns.MainFrame.SelectTab("overview")
    end
end

function ns.MainFrame.Hide()
    if frame then
        frame:Hide()
    end
end

function ns.MainFrame.GetFrame()
    return frame
end

function ns.MainFrame.GetContentArea()
    return frame and frame.contentArea
end

function ns.MainFrame.RefreshActiveTab()
    if not frame or not frame:IsShown() then return end
    if not activeTab then return end

    local tab = tabs[activeTab]
    if tab and tab.initialized then
        local module = ns[tab.definition.module]
        if module and module.Refresh then
            module.Refresh()
        end
    end
end
