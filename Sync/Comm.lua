local ADDON_NAME, ns = ...

ns.Comm = {}

local peers = {}
local pingTicker = nil
local cleanupTicker = nil
local snapshotTicker = nil
local helloTimer = nil
local lastSnapshotSent = {}  -- [senderID] = timestamp

function ns.Comm.Initialize()
    if not ns.DB.settings.syncEnabled then
        ns.Debug("Sync is disabled")
        return
    end

    ns.RateLimiter.Initialize()

    -- Listen for addon messages from BN friends
    ns.Events.Register("BN_CHAT_MSG_ADDON", function(prefix, message, _, senderID)
        if prefix == ns.PREFIX then
            ns.Comm.OnMessageReceived(message, "BN", senderID)
        end
    end, "Comm")

    ns.Events.Register("CHAT_MSG_ADDON", function(prefix, message, channel, sender)
        if prefix == ns.PREFIX then
            ns.Comm.OnMessageReceived(message, channel, sender)
        end
    end, "Comm")

    -- Debounced hello on login and friend changes
    ns.Events.Register("BN_FRIEND_INFO_CHANGED", function()
        ns.Comm.DebouncedHello()
    end, "Comm")

    ns.Events.Register("PLAYER_ENTERING_WORLD", function()
        C_Timer.After(5, function() ns.Comm.DebouncedHello() end)
    end, "Comm")

    -- Send snapshot on logout
    ns.Events.Register("PLAYER_LOGOUT", function()
        ns.Comm.SendSnapshotToAllTrusted()
    end, "Comm")

    -- Periodic snapshot sync every 5 minutes
    snapshotTicker = C_Timer.NewTicker(300, function()
        ns.Comm.SendSnapshotToAllTrusted()
    end)

    -- Periodic ping every 5 minutes (offset from snapshot)
    pingTicker = C_Timer.NewTicker(300, function()
        ns.Comm.SendPingToAll()
    end)

    -- Cleanup stale peers/chunks every minute
    cleanupTicker = C_Timer.NewTicker(60, function()
        ns.Chunking.CleanupStale()
        ns.Comm.CleanupStalePeers()
    end)
end

-- Send a message to a specific BN friend
function ns.Comm.SendToBN(bnetAccountID, message)
    if not ns.DB.settings.syncEnabled then return end

    ns.RateLimiter.TrySend(function()
        BNSendGameData(bnetAccountID, ns.PREFIX, message)
    end)
end

-- Check if an account key is a trusted peer
function ns.Comm.IsTrustedPeer(accountKey)
    if not accountKey then return false end
    return ns.DB.settings.trustedPeers[accountKey] == true
end

-- Debounce hello broadcasts
function ns.Comm.DebouncedHello()
    if helloTimer then
        helloTimer:Cancel()
    end
    helloTimer = C_Timer.NewTimer(3, function()
        helloTimer = nil
        ns.Comm.BroadcastHello()
    end)
end

-- Broadcast HELLO only to BN friends whose addon responds (discovery)
-- We send hello to all, but only accept/sync with trusted peers
function ns.Comm.BroadcastHello()
    if not ns.DB.settings.syncEnabled then return end
    if ns.TableUtil.Count(ns.DB.settings.trustedPeers) == 0 then
        ns.Debug("No trusted peers configured — skipping hello broadcast")
        return
    end

    local numFriends = BNGetNumFriends()
    local hello = ns.Protocol.MakeHello()
    local sent = 0

    for i = 1, numFriends do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo and accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.isOnline then
            local gameAccountID = accountInfo.gameAccountInfo.gameAccountID
            if gameAccountID then
                ns.RateLimiter.TrySend(function()
                    BNSendGameData(gameAccountID, ns.PREFIX, hello)
                end)
                sent = sent + 1
            end
        end
    end

    ns.DB.syncState.lastBroadcast = time()
    ns.Debug("Hello broadcast sent to %d online BN friends", sent)
end

-- Handle incoming messages
function ns.Comm.OnMessageReceived(rawMessage, channel, senderID)
    local parsed, err = ns.Protocol.Parse(rawMessage)
    if not parsed then
        ns.Debug("Failed to parse message from %s: %s", tostring(senderID), err)
        return
    end

    local msgType = parsed.type
    local fields = parsed.fields

    if msgType == ns.Protocol.Types.HELLO then
        ns.Comm.HandleHello(fields, senderID, channel)
    elseif msgType == ns.Protocol.Types.HELLO_ACK then
        ns.Comm.HandleHelloAck(fields, senderID, channel)
    elseif msgType == ns.Protocol.Types.REQUEST_FULL_SYNC then
        ns.Comm.HandleRequestFullSync(fields, senderID, channel)
    elseif msgType == ns.Protocol.Types.SNAPSHOT_META then
        ns.Comm.HandleSnapshotMeta(fields, senderID)
    elseif msgType == ns.Protocol.Types.SNAPSHOT_CHUNK then
        ns.Comm.HandleSnapshotChunk(fields, senderID)
    elseif msgType == ns.Protocol.Types.SNAPSHOT_END then
        ns.Comm.HandleSnapshotEnd(fields, senderID)
    elseif msgType == ns.Protocol.Types.PING then
        ns.Comm.HandlePing(fields, senderID, channel)
    elseif msgType == ns.Protocol.Types.PONG then
        ns.Comm.HandlePong(fields, senderID)
    elseif msgType == ns.Protocol.Types.ERROR then
        ns.Comm.HandleError(fields, senderID)
    end
end

function ns.Comm.HandleHello(fields, senderID, channel)
    local accountKey = fields[3]
    local charKey = fields[4]
    local addonVersion = fields[5]

    if accountKey == ns.DB.localAccount.accountKey then return end

    -- Only respond to trusted peers
    if not ns.Comm.IsTrustedPeer(accountKey) then
        ns.Debug("HELLO from untrusted peer %s (%s) — ignoring", charKey or "?", accountKey or "?")
        return
    end

    ns.Debug("HELLO from trusted peer %s (%s)", charKey or "?", accountKey or "?")

    peers[senderID] = {
        accountKey = accountKey,
        characterKey = charKey,
        addonVersion = addonVersion,
        lastSeen = GetTime(),
        channel = channel,
    }

    -- Respond with ACK
    if channel == "BN" then
        ns.Comm.SendToBN(senderID, ns.Protocol.MakeHelloAck())
    end

    -- Send snapshot on first contact (not repeated)
    if not lastSnapshotSent[senderID] then
        C_Timer.After(2, function()
            ns.Comm.SendSnapshotTo(senderID)
        end)
    end
end

function ns.Comm.HandleHelloAck(fields, senderID, channel)
    local accountKey = fields[3]
    local charKey = fields[4]
    local addonVersion = fields[5]

    if accountKey == ns.DB.localAccount.accountKey then return end

    -- Only accept from trusted peers
    if not ns.Comm.IsTrustedPeer(accountKey) then
        ns.Debug("HELLO_ACK from untrusted peer %s — ignoring", accountKey or "?")
        return
    end

    ns.Debug("HELLO_ACK from trusted peer %s (%s)", charKey or "?", accountKey or "?")

    peers[senderID] = {
        accountKey = accountKey,
        characterKey = charKey,
        addonVersion = addonVersion,
        lastSeen = GetTime(),
        channel = channel,
    }

    -- Request their snapshot if we don't have one yet
    if not ns.DB.networkSnapshots[accountKey] then
        if channel == "BN" then
            ns.Comm.SendToBN(senderID, ns.Protocol.MakeRequestFullSync())
        end
    end
end

function ns.Comm.HandleRequestFullSync(fields, senderID, channel)
    -- Verify the requesting peer is trusted
    local peer = peers[senderID]
    if not peer or not ns.Comm.IsTrustedPeer(peer.accountKey) then
        ns.Debug("Sync request from untrusted sender — ignoring")
        return
    end
    ns.Debug("Full sync requested by %s", peer.characterKey or tostring(senderID))
    ns.Comm.SendSnapshotTo(senderID)
end

function ns.Comm.HandleSnapshotMeta(fields, senderID)
    local accountKey = fields[3]
    local snapshotID = fields[4]
    local totalChunks = tonumber(fields[5])
    local dataSize = tonumber(fields[6])

    ns.Debug("Snapshot meta from %s: %s (%d chunks, %d bytes)",
        accountKey or "?", snapshotID or "?", totalChunks or 0, dataSize or 0)
end

function ns.Comm.HandleSnapshotChunk(fields, senderID)
    local snapshotID = fields[3]
    local chunkIndex = tonumber(fields[4])
    local totalChunks = tonumber(fields[5])
    local chunkData = fields[6]

    if not snapshotID or not chunkIndex or not totalChunks or not chunkData then
        ns.Debug("Invalid snapshot chunk from %s", tostring(senderID))
        return
    end

    local fullData = ns.Chunking.ReceiveChunk(snapshotID, chunkIndex, totalChunks, chunkData)
    if fullData then
        local snapshot = ns.Serializer.Deserialize(fullData)
        if snapshot and snapshot.accountKey then
            ns.Comm.AcceptSnapshot(snapshot)
        else
            ns.Debug("Failed to deserialize snapshot %s", snapshotID)
        end
    end
end

function ns.Comm.HandleSnapshotEnd(fields, senderID)
    local accountKey = fields[3]
    local snapshotID = fields[4]
    ns.Debug("Snapshot end marker from %s: %s", accountKey or "?", snapshotID or "?")
end

function ns.Comm.HandlePing(fields, senderID, channel)
    local accountKey = fields[3]
    if peers[senderID] then
        peers[senderID].lastSeen = GetTime()
    end
    if channel == "BN" and peers[senderID] then
        ns.Comm.SendToBN(senderID, ns.Protocol.MakePong())
    end
end

function ns.Comm.HandlePong(fields, senderID)
    if peers[senderID] then
        peers[senderID].lastSeen = GetTime()
    end
end

function ns.Comm.HandleError(fields, senderID)
    local accountKey = fields[3]
    local errorCode = fields[4]
    local errorMsg = fields[5]
    ns.Debug("Error from %s: [%s] %s", accountKey or "?", errorCode or "?", errorMsg or "?")
end

-- Build and send our local snapshot to a specific peer
function ns.Comm.SendSnapshotTo(senderID)
    if not ns.DB.settings.syncEnabled then return end

    local snapshot = {
        accountKey = ns.DB.localAccount.accountKey,
        addonVersion = ns.Config.ADDON_VERSION,
        snapshotVersion = ns.Config.PROTOCOL_VERSION,
        timestamp = time(),
        characters = ns.DB.localScans.characters,
    }

    local serialized = ns.Serializer.Serialize(snapshot)
    local snapshotID = ns.Chunking.NewSnapshotID()
    local chunks, totalChunks = ns.Chunking.Split(serialized)

    ns.Comm.SendToBN(senderID, ns.Protocol.MakeSnapshotMeta(snapshotID, totalChunks, #serialized))

    for i, chunkData in ipairs(chunks) do
        ns.RateLimiter.Enqueue(function()
            ns.Comm.SendToBN(senderID, ns.Protocol.MakeSnapshotChunk(snapshotID, i, totalChunks, chunkData))
        end)
    end

    ns.RateLimiter.Enqueue(function()
        ns.Comm.SendToBN(senderID, ns.Protocol.MakeSnapshotEnd(snapshotID))
    end)

    lastSnapshotSent[senderID] = time()
    ns.Debug("Sending snapshot %s to peer (%d chunks)", snapshotID, totalChunks)
end

-- Send snapshot to all connected trusted peers (called every 5 min + login/logout)
function ns.Comm.SendSnapshotToAllTrusted()
    if not ns.DB.settings.syncEnabled then return end

    for senderID, peer in pairs(peers) do
        if ns.Comm.IsTrustedPeer(peer.accountKey) then
            ns.Comm.SendSnapshotTo(senderID)
        end
    end
end

-- Accept and store a received snapshot — ONLY from trusted peers
function ns.Comm.AcceptSnapshot(snapshot)
    local accountKey = snapshot.accountKey
    if not accountKey or accountKey == ns.DB.localAccount.accountKey then return end

    if not ns.Comm.IsTrustedPeer(accountKey) then
        ns.Debug("Rejecting snapshot from untrusted peer: %s", accountKey)
        return
    end

    ns.DB.networkSnapshots[accountKey] = {
        sender = snapshot.characterKey or accountKey,
        snapshotVersion = snapshot.snapshotVersion or 1,
        addonVersion = snapshot.addonVersion or "unknown",
        lastReceived = time(),
        characters = snapshot.characters or {},
    }

    ns.Print("Received snapshot from %s", ns.ItemUtil.GetAccountDisplayName(accountKey))
    ns.Debug("Accepted snapshot from %s (%d characters)",
        accountKey, ns.TableUtil.Count(snapshot.characters or {}))
    ns.Events.Fire("PSC_SNAPSHOT_RECEIVED", accountKey)

    -- Trigger merge
    ns.Merge.RebuildIndex()
end

-- Send ping to all trusted peers
function ns.Comm.SendPingToAll()
    if not ns.DB.settings.syncEnabled then return end
    local ping = ns.Protocol.MakePing()
    for senderID, peer in pairs(peers) do
        if ns.Comm.IsTrustedPeer(peer.accountKey) then
            ns.Comm.SendToBN(senderID, ping)
        end
    end
end

-- Remove peers that haven't been seen recently
function ns.Comm.CleanupStalePeers()
    local now = GetTime()
    for senderID, peer in pairs(peers) do
        if now - peer.lastSeen > ns.Config.PEER_TIMEOUT then
            ns.Debug("Removing stale peer: %s (%s)", peer.characterKey or "?", peer.accountKey or "?")
            peers[senderID] = nil
            lastSnapshotSent[senderID] = nil
        end
    end
end

function ns.Comm.GetPeers()
    return peers
end

function ns.Comm.GetPeerCount()
    return ns.TableUtil.Count(peers)
end
