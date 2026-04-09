local ADDON_NAME, ns = ...

ns.Chunking = {}

local reassemblyBuffers = {}
local snapshotCounter = 0

-- Split data into chunks
function ns.Chunking.Split(data, chunkSize)
    chunkSize = chunkSize or ns.Config.CHUNK_SIZE
    local chunks = {}
    local dataLen = #data

    if dataLen <= chunkSize then
        return { data }, 1
    end

    local totalChunks = math.ceil(dataLen / chunkSize)
    for i = 1, totalChunks do
        local startIdx = (i - 1) * chunkSize + 1
        local endIdx = math.min(i * chunkSize, dataLen)
        chunks[i] = data:sub(startIdx, endIdx)
    end

    return chunks, totalChunks
end

-- Generate a unique snapshot ID for this session
function ns.Chunking.NewSnapshotID()
    snapshotCounter = snapshotCounter + 1
    return string.format("%s_%d_%d", ns.DB.localAccount.accountKey, time(), snapshotCounter)
end

-- Receive a chunk and attempt reassembly
-- Returns the full data if all chunks received, nil otherwise
function ns.Chunking.ReceiveChunk(snapshotID, chunkIndex, totalChunks, chunkData)
    if not reassemblyBuffers[snapshotID] then
        reassemblyBuffers[snapshotID] = {
            chunks = {},
            totalChunks = totalChunks,
            receivedCount = 0,
            startTime = GetTime(),
        }
    end

    local buffer = reassemblyBuffers[snapshotID]

    -- Validate consistency
    if buffer.totalChunks ~= totalChunks then
        ns.Debug("Chunk count mismatch for snapshot %s: expected %d, got %d",
            snapshotID, buffer.totalChunks, totalChunks)
        return nil
    end

    -- Store chunk if not already received
    if not buffer.chunks[chunkIndex] then
        buffer.chunks[chunkIndex] = chunkData
        buffer.receivedCount = buffer.receivedCount + 1
    end

    ns.Debug("Chunk %d/%d received for snapshot %s", chunkIndex, totalChunks, snapshotID)

    -- Check if complete
    if buffer.receivedCount == buffer.totalChunks then
        -- Reassemble
        local parts = {}
        for i = 1, buffer.totalChunks do
            parts[i] = buffer.chunks[i]
        end
        local fullData = table.concat(parts)

        -- Clean up buffer
        reassemblyBuffers[snapshotID] = nil

        ns.Debug("Snapshot %s fully reassembled (%d bytes)", snapshotID, #fullData)
        return fullData
    end

    return nil
end

-- Clean up timed-out reassembly buffers
function ns.Chunking.CleanupStale()
    local now = GetTime()
    local timeout = ns.Config.CHUNK_TIMEOUT

    for snapshotID, buffer in pairs(reassemblyBuffers) do
        if now - buffer.startTime > timeout then
            ns.Debug("Discarding stale snapshot %s (%d/%d chunks received)",
                snapshotID, buffer.receivedCount, buffer.totalChunks)
            reassemblyBuffers[snapshotID] = nil
        end
    end
end

function ns.Chunking.GetPendingSnapshots()
    local pending = {}
    for snapshotID, buffer in pairs(reassemblyBuffers) do
        pending[snapshotID] = {
            received = buffer.receivedCount,
            total = buffer.totalChunks,
            age = GetTime() - buffer.startTime,
        }
    end
    return pending
end
