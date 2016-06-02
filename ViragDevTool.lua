-- create global instance
ViragDevTool = {
    --static constant useed for metatable name
    METATABLE_NAME = "$metatable",

    --this 2 keyword are for cmd operations
    -- you can use /vdt find somestr parentname(can be in format _G.Frame.Button)
    -- for examle "/vdt find Virag" will find every variable in _G that has *Virag* pattern
    -- "/vdt find Data ViragDevTool" will find every variable that has *Data* in their name in _G.ViragDevTool object if it exists
    -- same for "startswith"
    FIND_CMD_KEYWORD = "find",
    STARTS_WITH_CMD_KEYWORD = "startswith",

    -- stores arguments for fcunction calls --todo implement
    tArgs = {},

    -- mapping table is used to store searches and diferent values that are frequently used
    -- for example we may need some api or some variable so we can add it here
    mapping = {},

    -- this variable will be used only on first load so it is just default init with empty values.
    -- will be replaced with ViragDevTool_Settings at 2-nd start
    DEFAULT_SETTINGS = {
        -- stores history of recent calls to /vdt
        history = {},
        favourites = {} --todo implement
    }
}

-- just remove global reference so it is easy to read with my ide
local ViragDevTool = ViragDevTool

local pairs, tostring, type, print, string, getmetatable, table, pcall =
pairs, tostring, type, print, string, getmetatable, table, pcall

local HybridScrollFrame_CreateButtons, HybridScrollFrame_GetOffset, HybridScrollFrame_Update =
HybridScrollFrame_CreateButtons, HybridScrollFrame_GetOffset, HybridScrollFrame_Update

-----------------------------------------------------------------------------------------------
-- ViragDevTool_Colors == ViragDevTool.colors
-----------------------------------------------------------------------------------------------

-- todo refactore this class

local ViragDevTool_Colors = {
    white = "|cFFFFFFFF",
    gray = "|cFFBEB9B5",
    lightblue = "|cFF96C0CE",
    red = "|cFFFF0000",
    green = "|cFF00FF00",
    darkred = "|cFFC25B56",
    parent = "|cFFBEB9B5",
    error = "|cFFFF0000",
    ok = "|cFF00FF00",
}

function ViragDevTool_Colors:forState(state)
    if state then return self.ok end
    return self.error
end

function ViragDevTool_Colors:stateStr(state)
    if state then return self.ok .. "OK" end
    return self.error .. "ERROR"
end

function ViragDevTool_Colors:errorText()
    return self:stateStr(false) .. self.white .. " function call failed"
end

function ViragDevTool_Colors:FNNameToString(name, args)
    -- Create function call string like myFunction(arg1, arg2, arg3)
    local fnNameWitArgs = ""
    local delimiter = ""
    local found = false
    for i = 10, 1, -1 do
        if args[i] ~= nil then found = true end

        if found then
            fnNameWitArgs = tostring(args[i]) .. delimiter .. fnNameWitArgs
            delimiter = ", "
        end
    end

    return name .. "(" .. fnNameWitArgs .. ")"
end

function ViragDevTool_Colors:functionStr(parent, name, args)
    local resultStr = self:FNNameToString(name, args)

    if parent then
        return self.parent .. parent.name .. ":" .. self.white .. resultStr
    else
        return self.white .. resultStr
    end
end

-----------------------------------------------------------------------------------------------
-- ViragDevToolLinkedList == ViragDevTool.list
-----------------------------------------------------------------------------------------------

--- Linked List
-- @field size
-- @field first
-- @field last
--
-- Each node has:
-- @field name - string name
-- @field value - any object
-- @field next - nil/next node
-- @field padding - int expanded level( when you click on table it expands  so padding = padding + 1)
-- @field parent - parent node after it expanded
-- @field expanded - true/false/nil


local ViragDevToolLinkedList = {}


function ViragDevToolLinkedList:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    self.size = 0
    return o
end

function ViragDevToolLinkedList:GetInfoAtPosition(position)
    if self.size < position or self.first == nil then
        return nil
    end

    local node = self.first
    while position > 0 do
        node = node.next
        position = position - 1
    end

    return node
end

function ViragDevToolLinkedList:AddNodesAfter(nodeList, parentNode)
    local tempNext = parentNode.next
    local currNode = parentNode;

    for _, node in pairs(nodeList) do
        currNode.next = node
        currNode = node
        self.size = self.size + 1;
    end

    currNode.next = tempNext

    if tempNext == nil then
        self.last = currNode
    end
end

function ViragDevToolLinkedList:AddNode(data, dataName)
    local node = self:NewNode(data, dataName)

    if self.first == nil then
        self.first = node
        self.last = node
    else
        if self.last ~= nil then
            self.last.next = node
        end
        self.last = node
    end

    self.size = self.size + 1;
end

function ViragDevToolLinkedList:NewNode(data, dataName, padding, parent)
    return {
        name = dataName,
        value = data,
        next = nil,
        padding = padding == nil and 0 or padding,
        parent = parent
    }
end

function ViragDevToolLinkedList:RemoveChildNodes(node)
    local currNode = node

    while true do

        currNode = currNode.next

        if currNode == nil then
            node.next = nil
            self.last = node
            break
        end

        if currNode.padding <= node.padding then
            node.next = currNode
            break
        end

        self.size = self.size - 1
    end
end

function ViragDevToolLinkedList:Clear()
    self.size = 0
    self.first = nil
    self.last = nil
end

-----------------------------------------------------------------------------------------------
-- ViragDevTool main
-----------------------------------------------------------------------------------------------

ViragDevTool.list = ViragDevToolLinkedList:new()
ViragDevTool.colors = ViragDevTool_Colors

---
-- Main (and the only) function you can use in ViragDevTool API
-- Will add data to the list so you can explore its values in UI list
-- @usage
-- Lets suppose you have MyModFN function in yours addon
-- function MyModFN()
-- local var = {}
-- ViragDevTool_AddData(var, "My local var in MyModFN")
-- end
-- This will add var as new var in our list
-- @param data (any type)- is object you would like to track.
-- Default behavior is shallow copy
-- @param dataName (string or nil) - name tag to show in UI for you variable.
-- Main purpose is to give readable names to objects you want to track.
function ViragDevTool_AddData(data, dataName)
    if dataName == nil then
        dataName = tostring(data)
    end

    ViragDevTool.list:AddNode(data, tostring(dataName))
    ViragDevTool:UpdateMainTableUI()
end

function ViragDevTool:AddDataFromString(msg, bAddToHistory)
    if msg == "" then
        msg = "_G"

    elseif #msg < 3 then
        self:print(msg .. " - too short, need str of size 2+")
        return
    end

    local msgs = self.split(msg, " ")

    local resultTable

    if #msgs > 1 then
        -- got search and not normal _g[msg]
        -- search can have find and prefix
        local firstArg = msgs[1]
        local secondArg = msgs[2]
        local thirdArg = msgs[3]

        local parent = _G

        if thirdArg then parent = self:FromStrToObject(thirdArg) end

        if string.lower(firstArg) == self.FIND_CMD_KEYWORD then
            resultTable = self:FindIn(parent, secondArg, string.match)
        elseif string.lower(firstArg) == self.STARTS_WITH_CMD_KEYWORD then
            resultTable = self:FindIn(parent, secondArg, self.starts)
        end

    else
        resultTable = self:FromStrToObject(msg)
        if not resultTable then
            self:print("_G." .. msg .. " == nil, so can't add")
        end
    end

    if resultTable then
        if bAddToHistory then
            ViragDevTool:AddToHistory(msg)
        end

        ViragDevTool_AddData(resultTable, msg)
    end
end

function ViragDevTool:FromStrToObject(str)
    local vars = self.split(str, ".") or {}

    local var = _G
    for _, name in pairs(vars) do
        if var then
            var = var[name]
        end
    end

    return var
end


function ViragDevTool:ClearData()
    self.list:Clear()
    self:UpdateMainTableUI()
end

function ViragDevTool:ExpandCell(info)

    local nodeList = {}
    local padding = info.padding + 1
    local couner = 1
    for k, v in pairs(info.value) do
        if type(v) ~= "userdata" then
            nodeList[couner] = self.list:NewNode(v, tostring(k), padding, info)
        else
            local mt = getmetatable(info.value)
            if mt then
                nodeList[couner] = self.list:NewNode(mt.__index, self.METATABLE_NAME, padding, info)
            end
        end
        couner = couner + 1
    end

    table.sort(nodeList, function(a, b)
        if a.name == "__index" then return true
        elseif b.name == "__index" then return false
        else return a.name < b.name
        end
    end)

    self.list:AddNodesAfter(nodeList, info)

    info.expanded = true

    ViragDevTool:UpdateMainTableUI()
end

function ViragDevTool:ColapseCell(info)
    self.list:RemoveChildNodes(info)
    info.expanded = nil
    self:UpdateMainTableUI()
end

-----------------------------------------------------------------------------------------------
-- UI
-----------------------------------------------------------------------------------------------
function ViragDevTool:UpdateMainTableUI()

    local scrollFrame = self.wndRef.scrollFrame
    self:MainTableScrollBar_AddChildren(scrollFrame)

    local buttons = scrollFrame.buttons;
    local offset = HybridScrollFrame_GetOffset(scrollFrame)
    local totalRowsCount = self.list.size
    local lineplusoffset;

    local nodeInfo = self.list:GetInfoAtPosition(offset)
    for k, view in pairs(buttons) do
        lineplusoffset = k + offset;
        if lineplusoffset <= totalRowsCount then
            self:UIUpdateMainTableButton(view, nodeInfo, lineplusoffset)
            nodeInfo = nodeInfo.next
            view:Show();
        else
            view:Hide();
        end
    end

    HybridScrollFrame_Update(scrollFrame, totalRowsCount * buttons[1]:GetHeight(), scrollFrame:GetHeight());
end

function ViragDevTool:UpdateSideBarUI()
    local scrollFrame = self.wndRef.sideFrame.sideScrollFrame

    local buttons = scrollFrame.buttons;
    local data = self.settings and self.settings.history or {}

    if not buttons then
        HybridScrollFrame_CreateButtons(scrollFrame, "ViragDevToolSideBarRowTemplate", 0, -2)
    end

    buttons = scrollFrame.buttons;
    local offset = HybridScrollFrame_GetOffset(scrollFrame)
    local lineplusoffset;
    local totalRowsCount = #data

    for k, view in pairs(buttons) do
        lineplusoffset = k + offset;
        if lineplusoffset <= totalRowsCount then
            local name = tostring(data[lineplusoffset])
            view:SetText(name)
            view:SetScript("OnMouseUp", function(this, button, down)
                self:AddDataFromString(name)
            end)
            view:Show();
        else
            view:Hide();
        end
    end

    HybridScrollFrame_Update(scrollFrame, totalRowsCount * buttons[1]:GetHeight(), scrollFrame:GetHeight());
end


function ViragDevTool:MainTableScrollBar_AddChildren(scrollFrame)
    if self.ScrollBarHeight == nil or scrollFrame:GetHeight() > self.ScrollBarHeight then
        self.ScrollBarHeight = scrollFrame:GetHeight()

        local scrollBarValue = scrollFrame.scrollBar:GetValue()
        HybridScrollFrame_CreateButtons(scrollFrame, "ViragDevToolEntryTemplate", 0, -2)
        scrollFrame.scrollBar:SetValue(scrollBarValue);
    end
end


function ViragDevTool:UIUpdateMainTableButton(node, info, id)
    local nameButton = node.nameButton;
    local typeButton = node.typeButton
    local valueButton = node.valueButton
    local rowNumberButton = node.rowNumberButton

    local value = info.value
    local name = info.name
    local padding = info.padding

    nameButton:SetPoint("LEFT", node.typeButton, "RIGHT", 20 * padding, 0)

    local valueType = type(value)

    valueButton:SetText(tostring(value))
    nameButton:SetText(tostring(name))
    typeButton:SetText(valueType)
    rowNumberButton:SetText(tostring(id))

    local color = "ViragDevToolBaseFont"
    if valueType == "table" then
        if name ~= self.METATABLE_NAME then
            local objectType = self:GetObjectTypeFromWoWAPI(value)
            if objectType then
                valueButton:SetText(objectType .. "  " .. tostring(value))
            end
            color = "ViragDevToolTableFont";
        else
            color = "ViragDevToolMetatableFont";
        end
        local resultStringName = tostring(name)
        local MAX_STRING_SIZE = 60
        if #resultStringName >= MAX_STRING_SIZE then
            resultStringName = string.sub(resultStringName, 0, MAX_STRING_SIZE) .. "..."
        end

        local function tablelength(T)
            local count = 0
            for _ in pairs(T) do count = count + 1
            end
            return count
        end

        nameButton:SetText(resultStringName .. "   (" .. tablelength(value) .. ") ");

    elseif valueType == "userdata" then
        color = "ViragDevToolTableFont";
    elseif valueType == "string" then
        valueButton:SetText(string.gsub(string.gsub(tostring(value), "|n", ""), "\n", ""))
        color = "ViragDevToolStringFont";
    elseif valueType == "number" then
        color = "ViragDevToolNumberFont";
    elseif valueType == "function" then
        color = "ViragDevToolFunctionFont";
        --todo add function args info and description from error msges or from some mapping file
    end

    nameButton:SetNormalFontObject(color)
    typeButton:SetNormalFontObject(color)
    valueButton:SetNormalFontObject(color)
    rowNumberButton:SetNormalFontObject(color)

    self:SetMainTableButtonScript(nameButton, info)
    self:SetMainTableButtonScript(valueButton, info)
end

-----------------------------------------------------------------------------------------------
-- Main table row button clicks setup
-----------------------------------------------------------------------------------------------
function ViragDevTool:SetMainTableButtonScript(button, info)
    local valueType = type(info.value)
    if valueType == "table" then
        button:SetScript("OnMouseUp", function(this, button, down)
            if info.expanded then
                self:ColapseCell(info)
            else
                self:ExpandCell(info)
            end
        end)
    elseif valueType == "function" then
        button:SetScript("OnMouseUp", function(this, button, down)
            self:TryCallFunction(info)
        end)
    else
        button:SetScript("OnMouseUp", nil)
    end
end

function ViragDevTool:TryCallFunction(info)
    -- info.value is just our function to call
    local parent, ok
    local fn = info.value
    local args = self:shallowcopyargs(self.tArgs)
    local results = {}

    -- lets try safe call first
    ok, results[1], results[2], results[3], results[4], results[5] = pcall(fn, unpack(args, 1, 10))

    if not ok then
        -- if safe call failed we probably could try to find self and call self:fn()
        parent = info.parent


        if parent and parent.value == _G then
            -- this fn is in global namespace so no parent
            parent = nil
        end

        if parent then

            if parent.name == self.METATABLE_NAME then
                -- metatable has real object 1 level higher
                parent = parent.parent
            end
            fn = parent.value[info.name]
            table.insert(args, 1, parent.value)
            ok, results[1], results[2], results[3], results[4], results[5] = pcall(fn, unpack(args, 1, 10))
        end
    end

    self:ProcessCallFunctionData(ok, info, parent, args, results)
end

-- this function is kinda hard to read but it just adds new items to list and prints log in chat.
-- will add 1 row for call result(ok or error) and 1 row for each return value
function ViragDevTool:ProcessCallFunctionData(ok, info, parent, args, results)
    local nodes = {}

    self:ColapseCell(info) -- if we already called this fn remove old results

    local C = self.colors
    local list = self.list
    local padding = info.padding + 1

    --constract full function call name
    local fnNameWitArgs = C:functionStr(parent, info.name, args)
    local returnFormatedStr = ""

    -- itterate backwords because we want to include every meaningfull nil result
    -- and with default itteration like pairs() we will just skip them so
    -- for example 1, 2, nil, 4 should return only this 4 values nothing more, nothing less.
    local found = false
    for i = 10, 1, -1 do
        if results[i] ~= nil then found = true
        end

        if found or i == 1 then -- if found some return or if return is nil
        nodes[i] = list:NewNode(results[i], string.format("  return: %d", i), padding)

        returnFormatedStr = string.format(" %s%s %s(%s)%s", C.white, tostring(results[i]),
            C.lightblue, type(results[i]), returnFormatedStr)
        end
    end

    -- create fist node of result info no need for now. will use debug
    table.insert(nodes, 1, list:NewNode(string.format("%s - %s", C:stateStr(ok), fnNameWitArgs), -- node value
        C.white .. date("%X") .. " function call results:", padding))


    -- adds call result to our UI list
    list:AddNodesAfter(nodes, info)
    self:UpdateMainTableUI()

    --print info to chat
    self:print(C:stateStr(ok) .. " " .. fnNameWitArgs .. C.gray .. " returns:" .. returnFormatedStr)
end

-----------------------------------------------------------------------------------------------
-- HISTORY
-----------------------------------------------------------------------------------------------
function ViragDevTool:AddToHistory(strValue)
    if self.settings and self.settings.history then
        local hist = self.settings.history
        table.insert(hist, 1, strValue)
        while #hist > 20 do -- can have only 10 values in history
        table.remove(hist, 20)
        end
        self:UpdateSideBarUI()
    end
end

-----------------------------------------------------------------------------------------------
-- EVENTS
-----------------------------------------------------------------------------------------------
function ViragDevTool:OnEvent(this, event, ...)
    if event == "ADDON_LOADED" then
        if not ViragDevTool_Settings then ViragDevTool_Settings = self.DEFAULT_SETTINGS end

        self.settings = ViragDevTool_Settings
    end
end

-----------------------------------------------------------------------------------------------
-- LIFECICLE
-----------------------------------------------------------------------------------------------
function ViragDevTool:OnLoad(mainFrame)
    self.wndRef = mainFrame

    mainFrame:RegisterEvent("ADDON_LOADED")
    mainFrame:SetScript("OnEvent", function(self, event, ...)
        ViragDevTool:OnEvent(self, event, ...); -- call one of the functions above
    end);
    --register update scrollFrame
    self.wndRef.scrollFrame.update = function()
        self:UpdateMainTableUI()
    end
    self:UpdateMainTableUI()

    self.wndRef.sideFrame.sideScrollFrame.update = function()
        self:UpdateSideBarUI()
    end
    self:UpdateSideBarUI()

    -- register slash cmd
    SLASH_VIRAGDEVTOOLS1 = '/vdt';
    function SlashCmdList.VIRAGDEVTOOLS(msg, editbox)
        if msg == "" or msg == nil then
            self:ToggleUI()
        else
            self:AddDataFromString(msg, true)
        end
    end
end

function ViragDevTool:ToggleSidebar()
    self:Toggle(self.wndRef.sideFrame)
    ViragDevTool:UpdateSideBarUI()
end

function ViragDevTool:ToggleUI()
    self:Toggle(self.wndRef)
end

function ViragDevTool:Toggle(view)
    if view then
        if view:IsVisible() then
            view:Hide()
        else
            view:Show()
        end
    end
end


-----------------------------------------------------------------------------------------------
-- UTILS
-----------------------------------------------------------------------------------------------
function ViragDevTool:print(strText)
    print(self.colors.darkred .. "[Virag's DT]: " .. self.colors.white .. strText)
end

function ViragDevTool:shallowcopyargs(orig)
    local copy = {}
    for k, v in pairs(orig) do copy[k] = orig[v]
    end
    return copy
end

function ViragDevTool:split(sep)
    local sep, fields = sep or ".", {}
    local pattern = string.format("([^%s]+)", sep)
    self:gsub(pattern, function(c) fields[#fields + 1] = c
    end)
    return fields
end

function ViragDevTool:GetObjectTypeFromWoWAPI(value)
    if value.GetObjectType and value.IsForbidden then
        local ok, forbidden = pcall(value.IsForbidden, value)
        if ok and not forbidden then
            local ok, result = pcall(value.GetObjectType, value)
            if ok then
                return result
            end
        end
    end
end