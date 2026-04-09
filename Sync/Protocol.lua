local ADDON_NAME, ns = ...

ns.Protocol = {}

-- Message types
ns.Protocol.Types = {
    HELLO = "HELLO",
    HELLO_ACK = "HELLO_ACK",
    REQUEST_FULL_SYNC = "REQ_SYNC",
    SNAPSHOT_META = "SNAP_META",
    SNAPSHOT_CHUNK = "SNAP_CHUNK",
    SNAPSHOT_END = "SNAP_END",
    PING = "PING",
    PONG = "PONG",
    ERROR = "ERROR",
}

-- Delimiter for message fields
local FIELD_SEP = "\001"

-- Build a message string from type and payload fields
local function buildMessage(msgType, fields)
    local parts = {
        tostring(ns.Config.PROTOCOL_VERSION),
        msgType,
    }
    if fields then
        for _, v in ipairs(fields) do
            parts[#parts + 1] = tostring(v)
        end
    end
    return table.concat(parts, FIELD_SEP)
end

-- Parse a raw message string into type and fields
function ns.Protocol.Parse(rawMessage)
    if not rawMessage or #rawMessage == 0 then
        return nil, "empty message"
    end

    local fields = {}
    for field in rawMessage:gmatch("[^" .. FIELD_SEP .. "]+") do
        fields[#fields + 1] = field
    end

    if #fields < 2 then
        return nil, "malformed message"
    end

    local protocolVersion = tonumber(fields[1])
    if protocolVersion ~= ns.Config.PROTOCOL_VERSION then
        return nil, string.format("protocol version mismatch: got %s, expected %d",
            fields[1], ns.Config.PROTOCOL_VERSION)
    end

    return {
        protocolVersion = protocolVersion,
        type = fields[2],
        fields = fields,
    }
end

-- Message factory functions

function ns.Protocol.MakeHello()
    return buildMessage(ns.Protocol.Types.HELLO, {
        ns.DB.localAccount.accountKey,
        ns.CharacterScanner.GetCurrentCharacterKey() or "",
        ns.Config.ADDON_VERSION,
        tostring(time()),
    })
end

function ns.Protocol.MakeHelloAck()
    return buildMessage(ns.Protocol.Types.HELLO_ACK, {
        ns.DB.localAccount.accountKey,
        ns.CharacterScanner.GetCurrentCharacterKey() or "",
        ns.Config.ADDON_VERSION,
        tostring(time()),
    })
end

function ns.Protocol.MakeRequestFullSync()
    return buildMessage(ns.Protocol.Types.REQUEST_FULL_SYNC, {
        ns.DB.localAccount.accountKey,
        tostring(time()),
    })
end

function ns.Protocol.MakeSnapshotMeta(snapshotID, totalChunks, dataSize)
    return buildMessage(ns.Protocol.Types.SNAPSHOT_META, {
        ns.DB.localAccount.accountKey,
        snapshotID,
        tostring(totalChunks),
        tostring(dataSize),
        tostring(time()),
    })
end

function ns.Protocol.MakeSnapshotChunk(snapshotID, chunkIndex, totalChunks, chunkData)
    return buildMessage(ns.Protocol.Types.SNAPSHOT_CHUNK, {
        snapshotID,
        tostring(chunkIndex),
        tostring(totalChunks),
        chunkData,
    })
end

function ns.Protocol.MakeSnapshotEnd(snapshotID)
    return buildMessage(ns.Protocol.Types.SNAPSHOT_END, {
        ns.DB.localAccount.accountKey,
        snapshotID,
    })
end

function ns.Protocol.MakePing()
    return buildMessage(ns.Protocol.Types.PING, {
        ns.DB.localAccount.accountKey,
        tostring(time()),
    })
end

function ns.Protocol.MakePong()
    return buildMessage(ns.Protocol.Types.PONG, {
        ns.DB.localAccount.accountKey,
        tostring(time()),
    })
end

function ns.Protocol.MakeError(errorCode, errorMessage)
    return buildMessage(ns.Protocol.Types.ERROR, {
        ns.DB.localAccount.accountKey,
        tostring(errorCode),
        errorMessage or "",
    })
end
