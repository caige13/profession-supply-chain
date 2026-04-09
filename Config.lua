local ADDON_NAME, ns = ...

ns.Config = {}

-- Protocol
ns.Config.PROTOCOL_VERSION = 1
ns.Config.ADDON_VERSION = "0.1.0"
ns.Config.ADDON_PREFIX = "PSC"

-- Freshness thresholds (seconds)
ns.Config.FRESH_THRESHOLD = 6 * 3600       -- 6 hours
ns.Config.AGING_THRESHOLD = 24 * 3600      -- 24 hours
ns.Config.STALE_THRESHOLD = 72 * 3600      -- 72 hours

-- Sync / rate limiting
ns.Config.MAX_MESSAGES_PER_SECOND = 5
ns.Config.MAX_BURST = 10
ns.Config.CHUNK_SIZE = 245                  -- bytes per BN message chunk
ns.Config.CHUNK_TIMEOUT = 30                -- seconds before discarding incomplete snapshot
ns.Config.PING_INTERVAL = 300               -- 5 minutes
ns.Config.PEER_TIMEOUT = 600                -- 10 minutes without ping = stale peer

-- Mail helper
ns.Config.MAX_MAIL_ATTACHMENTS = 12         -- ATTACHMENTS_MAX_SEND

-- Scanner delays
ns.Config.BAG_SCAN_DELAY = 0.5             -- seconds after BAG_UPDATE_DELAYED
ns.Config.PROFESSION_SCAN_DELAY = 0.3      -- seconds after TRADE_SKILL events

-- Default settings
ns.Config.DEFAULT_SETTINGS = {
    trustedPeers = {},
    enableTSM = true,
    enableCraftSim = true,
    debug = false,
    maxSnapshotAgeHours = 72,
    syncEnabled = true,
}
