local site = require("lib.public_events.injection_rig.site")
local injection_rig = require("lib.public_events.injection_rig.encounter")

local events = {}

--- Generated names of the region 8 rig. The prefab has no location point, so the marker uses its
--- type-47 point. Rally 80F6BA4D is paired by volume position, 12 units from the rig. Cue 0 has no
--- lines; cue text: 5 and 6 the rig beaten, 7 and 8 it exploding.
local HELLAS_RIG = {
    suffix = "_80F6B2FD",
    navpoint = "PF_EVENT_CABAL_SPIRE_1_AP_CABAL_SPIRE",
    cues = {CUE_ALERT = 1, CUE_START = 2, CUE_VENTS = 3, CUE_FAILED = 4, CUE_SUCCESS = 5,
        CUE_HEROIC_SUCCESS = 7, CUE_HEROIC_FAILED = 4},
    psion_row = "INJECTION_RIG_DFFC1441",
    evacuate_row = "INJECTION_RIG_15417709",
    valus_row = "INJECTION_RIG_5DE0F6DF",
    final_row = "INJECTION_RIG_11C334A2",
    rally_key = "_80F6BA4D",
}

--- Builds the region 8 Injection Rig handler on the shared event skeleton.
function events.injection_rig(mission)
    local definition = site.bind(mission, HELLAS_RIG)
    -- Use the event area for rally membership; the spawn-override volume is a thin slab.
    definition.rally.engagement = definition.engagement
    definition.rally.volume = definition.engagement_volume
    return injection_rig.new(definition)
end

return events
