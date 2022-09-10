function widget:GetInfo()
	return {
		name      = "Teiserver Internal Clients",
		desc      = "Provides interface for Teiserver Internal Clients.",
		author    = "MasterBel2",
		date      = "September 2022",
		license   = "GNU GPL, v2.1 or later",
		layer     = -100000,
		enabled   = true  --  loaded by default?
	}
end

local charactersToEscape = {
    ["["] = true,
    ["]"] = true,
    ["{"] = true,
    ["}"] = true,
    ["#"] = true
}

local function escaped(stringToEscape, charactersToEscape, escapeChar)
    local escapedString = ""
    
    for stringIndex = 1, #stringToEscape do
        local character = stringToEscape:sub(stringIndex, stringIndex)
        if charactersToEscape[character] then
            escapedString = escapedString .. escapeChar .. character
        else
            escapedString = escapedString .. character
        end
    end
    return escapedString
end

local wordPattern = "[%w%[%]_]+"
local escapedWordPattern = escaped(wordPattern, charactersToEscape, "\\")

local CoordinatorIngestAPI = {
    LobbyStatusFlag = {
        pattern = "--------------------------- Lobby status ---------------------------",
        func = function()
        end
    },
    Locks = {
        pattern = "Locks: *",
        func = function(client, locks)
        end
    },
    Gatekeeper = {
        pattern = "Gatekeeper: {" .. escapedWordPattern .. "}",
        func = function(client, gatekeeper)
        end
    },
    PositionInQueue = {
        pattern = "You are at position # in the queue",
        func = function(client, position)
            client:SetQueuePosition(position)
        end
    },
    JoinQueue = {
        pattern = "Join queue: [{" .. escapedWordPattern .. "}(, )] (size: #)",
        func = function(client, joinQueue)
        end
    },
    PlayerCount = {
        pattern = "Currently # players",
        func = function(client, playerCount)
        end
    },
    TeamSizeAndCount = {
        pattern = "Team size and count are: # and #",
        func = function(client)
        end
    },
    NoBoss = {
        pattern = "Nobody is bossed",
        func = function(client)
        end
    },
    Boss = {
        pattern = "Host boss is: {" .. escapedWordPattern .. "}",
        func = function(client, boss)
        end
    },
    MaxPlayers = {
        pattern = "Maximum allowed number of players is # (Host = #, Coordinator = #)",
        func = function(client, maxPlayers, hostMaxPlayers, coordinatorMaxPlayers)
        end
    },

    JoinedQueue = {
        pattern = "You are now in the join-queue at position #. Use $status to check on the queue.",
        func = function(client, position)
            client:SetQueuePosition(position)
        end
    },
    LeftQueue = {
        pattern = "You have been removed from the join queue",
        func = function(client)
            client:SetQueuePosition(nil)
        end
    },
    BecamePlayer = {
        pattern = "{" .. escapedWordPattern .. "} You were at the front of the queue, you are now a player.",
        func = function(client)
            client:SetQueuePosition(nil)
        end
    }
}

local function patternDefinition(formatString, formatIndex, terminator)
    local escaped = false
    local pattern = ""

    while formatIndex <= #formatString do
        local character = formatString:sub(formatIndex, formatIndex)

        if escaped then
            escaped = false
            pattern = pattern .. character
        elseif character == terminator then
            return pattern, formatIndex
        elseif character == "\\" then 
            escaped = true
        else
            pattern = pattern .. character
        end
        
        formatIndex = formatIndex + 1
    end
end

local function arrayDefinition(formatString, formatIndex)
    local escaped = false

    local temp = ""

    if formatString:sub(formatIndex, formatIndex) ~= "{" then
        error("Array definition must begin with a format definition - {...}!")
    end

    local elementPattern, elementPatternTerminatorIndex = patternDefinition(formatString, formatIndex + 1, "}")
    if not elementPatternTerminatorIndex then
        error("Could not find closing brace (\"}\") for format definition!")
    end

    if formatString:sub(elementPatternTerminatorIndex + 1, elementPatternTerminatorIndex + 1) ~= "(" then
        error("Array definition must include a separator definition - (...)!")
    end

    local separator, separatorPatternTerminatorIndex = patternDefinition(formatString, elementPatternTerminatorIndex + 2, ")")
    if not separatorPatternTerminatorIndex then
        error("Could not find closing parenthesis (\")\") for separator definition!")
    end

    separator = formatString:sub(elementPatternTerminatorIndex + 2, separatorPatternTerminatorIndex - 1)

    if formatString:sub(separatorPatternTerminatorIndex + 1, separatorPatternTerminatorIndex + 1) ~= "]" then
        error("Could not find closing bracket (\"]\") for array definition!")
    end

    return elementPattern, separator, separatorPatternTerminatorIndex + 1
end

function attemptDecode(string, format)
    local escaped = false
    local stringIndex = 1
    local formatIndex = 1

    local args = {}

    while formatIndex < #format do
        local character = format:sub(formatIndex, formatIndex)

        if escaped then
            escaped = false
            if string:sub(stringIndex, stringIndex) ~= format:sub(formatIndex, formatIndex) then
                error("Mismatch at stringIndex: " .. stringIndex .. ", character: \"" .. string:sub(stringIndex, stringIndex) .. ", formatIndex: " .. formatIndex .. ", character: " .. format:sub(formatIndex, formatIndex))
                -- return false
            end
            stringIndex = stringIndex + 1
            formatIndex = formatIndex + 1
        elseif character == "[" then
            local elementPattern, separatorPattern, endIndex = arrayDefinition(format, formatIndex + 1)
            local x = {}

            while true do
                local startIndex, endIndex = string:find(elementPattern, stringIndex)
                if (not (startIndex and endIndex)) or stringIndex ~= startIndex then
                    if #x == 0 then
                        break
                    else
                        error("Expected value! (Index: " .. stringIndex .. ")")
                    end
                end
                stringIndex = endIndex + 1
                table.insert(x, string:sub(startIndex, endIndex))

                startIndex, endIndex = string:find(separatorPattern, stringIndex)
                if not (startIndex and endIndex) then
                    break
                end

                stringIndex = endIndex + 1
            end
                
            formatIndex = endIndex + 1

            table.insert(args, x)
        elseif character == "{" then
            local patternTerminatorIndex = patternDefinition(format, formatIndex + 1, "}")
            if not patternTerminatorIndex then
                error("Could not find closing brace (\"}\") for format definition!")
            end

            local pattern = format:sub(formatIndex + 1, patternTerminatorIndex - 1)
            formatIndex = patternTerminatorIndex + 1

            local valueStart, valueEnd = string:find(pattern, stringIndex)
            if valueStart ~= stringIndex then 
                error("Could not find value matching pattern at stringIndex " .. stringIndex .. "!")
            end
            table.insert(args, string:sub(valueStart, valueEnd))
            
            stringIndex = valueEnd + 1
        elseif character == "\\" then
            escaped = true
            formatIndex = formatIndex + 1
        elseif character == "#" then
            local numberStart, numberEnd = string:find("[%d%.]", stringIndex)
            if numberStart ~= stringIndex then 
                error("Expected number at index " .. stringIndex .. "!")
            end
            table.insert(args, tonumber(string:sub(numberStart, numberEnd)))

            stringIndex = numberEnd + 1
            formatIndex = formatIndex + 1
        else
            if string:sub(stringIndex, stringIndex) ~= format:sub(formatIndex, formatIndex) then
                error("Mismatch at stringIndex: " .. stringIndex .. ", character: \"" .. string:sub(stringIndex, stringIndex) .. "\", formatIndex: " .. formatIndex .. ", character: \"" .. format:sub(formatIndex, formatIndex) .. "\"")
                -- return false
            end
            stringIndex = stringIndex + 1
            formatIndex = formatIndex + 1
        end
    end

    return args
end

local teiserverInternalClients = {
    Coordinator = {
        JoinQueue = function(self)
            self:SendCommand("$joinq")
        end,
        LeaveQueue = function()
            self:SendCommand("$leaveq")
        end,
        GetBattleStatus = function()
            self:SendCommand("$status")
        end,
        SplitLobby = function()
            self:SendCommand("$splitlobby")
        end,
        JoinSplit = function()
            self:SendCommand("$y")
        end,
        LeaveSplit = function()
            self:SendCommand("$n")
        end,
        
        

        Incoming = CoordinatorIngestAPI,
        SetQueuePosition = function(self, position)
            self.myPositionInQueue = position
            self:CallListeners("SetQueuePosition", position)
        end
    },
    AccoladesBot = {

    },
    DiscordBridge = {

    }
}

for clientName, clientAPI in pairs(teiserverInternalClients) do
    function clientAPI:SendCommand(message)
        WG.LibLobby.lobby:Say(clientName, message)
    end

    function clientAPI:ReceiveCommand(message)
        for _, command in pairs(self.Incoming) do
            local success, value = pcall(attemptDecode, message, command.pattern)
            if success then
                command.func(self, unpack(value))
                return true
            end
        end
    end

    function clientAPI:AddListener(name, func)
        local listeners = self[name .. "Listeners"] or {}

        table.insert(listeners, func)

        self[name .. "Listeners"] = listeners
    end
    function clientAPI:RemoveListener(name, func)
        -- todo
    end
    function clientAPI:CallListeners(name, ...)
        local listeners = self[name .. "Listeners"] or {}
        for _, listener in ipairs(listeners) do
            listener(self, ...)
        end
    end
end

function widget:Initialize()
    local lobby = WG.LibLobby.lobby
    
    lobby:AddListener("OnAddUser", function(listener, username, userInfo)
        local client = teiserverInternalClients[username]
        if client and userInfo.lobbyID == "Teiserver Internal Client" then
            client.userInfo = userInfo
            userInfo.hideMessagesFromInterface = true
        end
    end)

    lobby:AddListener("OnSaidBattleEx", function(listener, username, message)
        local client = teiserverInternalClients[username]
        if client then
            client:ReceiveCommand(message)
        end
    end)
    lobby:AddListener("OnSaidPrivate", function(listener, username, message)
        local client = teiserverInternalClients[username]
        if client then
            client:ReceiveCommand(message)
        end
    end)
end

WG.TeiserverInternalClients = teiserverInternalClients