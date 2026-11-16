local lib = require("lib.mission_lib")
local rally = require("lib.public_events.rally")
local site = require("lib.public_events.spire_integration.site")
local spire = require("lib.public_events.spire_integration.encounter")
local ether = require("lib.public_events.ether_resupply.encounter")
local injection_rig = require("lib.public_events.injection_rig.encounter")
local rig_site = require("lib.public_events.injection_rig.site")
local glimmer = require("lib.public_events.glimmer_extraction.encounter")
local glimmer_site = require("lib.public_events.glimmer_extraction.site")
local schedule = require("lib.public_events.schedule")

local events = {}

-- Watcher's Grave in the client's public-event schedule: the site roster keys of its two entries.
local SPIRE_SITE_KEY = 0x748A97BE
local ETHER_SITE_KEY = 0xAACE558D
-- Both entries share the one rally prefab of the zone.
local WATCHERS_GRAVE_RALLY = "_80C03220"

--- The Spire at Watcher's Grave: its object, its event-centre volume and its rally prefab.
local WATCHERS_GRAVE = {tag = "80C037B5", root = "PF_VEXBLOCK01", area = {"SLOT_0096"},
    rally = "80C03220"}

-- The other Spire placements of Nessus. Each names its object and root prefab, the one wide
-- volume at its centre, the rally prefab nearest it and its entry in the client's schedule.
-- The Tangle authors no flag beside its Spire; the nearest, 39 m away, is one of the extraction's.
local SPIRES = {
    {region = 24, tag = "80C0682F", root = "EVENT_VEXBLOCK_2", area = {"SLOT_0090"},
        rally = "80C03CF0", site_key = 0x5C01717F},
    {region = 64, tag = "80C07184", root = "PF_VEXBLOCK01", area = {"SLOT_0091"},
        rally = "80C06E5C", site_key = 0x46CEE7B0},
    {region = 240, tag = "80C09857", root = "EVENT_VEXBLOCK_1", area = {"SLOT_0099"},
        rally = "80C0929C", rally_volume = "RALLY_POINT_SPAWN_OVERRIDE_VOLUME_VEX_BLOCK",
        site_key = 0x8A984FD5},
    {region = 296, tag = "80C30173", root = "EVENT_VEXBLOCK_2", area = {"SLOT_0094"},
        rally = "80C0AA71", rally_volume = "RALLY_POINT_SPAWN_OVERRIDE_VOLUME1",
        site_key = 0x9F6C42EE},
}

--- Starts a site on the map's own clock: rally with the seconds left, or active at once. The zone
--- hands a slot picked for another site to that site by this key.
local function scheduled(handler, site_key)
    handler.site_key = site_key
    handler.schedule = function(context) return schedule.arrival(context, site_key) end
    return handler
end

--- Builds the Watcher's Grave Spire handler.
function events.watchers_grave(mission)
    local definition = site.bind(mission, WATCHERS_GRAVE)
    -- Preserve the native normal-state lifecycle; map nodes follow the separate schedule.
    definition.normal_event_state = true
    return scheduled(spire.new(definition), SPIRE_SITE_KEY)
end

--- Builds the Spire handler of every other placement, with the region and sensor it attaches to.
---@return table[] sites {region, sensor, handler} in the order of SPIRES.
function events.spires(mission)
    local sites = {}
    for index, placement in ipairs(SPIRES) do
        local definition = site.bind(mission, placement)
        definition.normal_event_state = true
        sites[index] = {region = placement.region, sensor = definition.event_sensor,
            handler = scheduled(spire.new(definition), placement.site_key)}
    end
    return sites
end

-- Glimmer Extraction placements of Nessus. Each names its object and root prefab, the unnamed
-- volumes beside it, the rally prefab at its first drill site and its schedule entry. The
-- Tangle authors two; the first has five drill sites, and an audience holds eight volumes, so
-- it names only the drills' 64 m engagement volumes.
local EXTRACTIONS = {
    {region = 88, tag = "80C083E2", root = "FALLEN_MULTIPOINT_CORE",
        volumes = {"SLOT_0158", "SLOT_0176", "SLOT_018F", "SLOT_0196"}, rally = "80C080D1",
        rally_volume = "RALLY_POINT_SPAWN_OVERRIDE_VOLUME_COAST", site_key = 0x6D2C17FB},
    {region = 240, tag = "80C096EC", root = "PF_EVENT_MULTIPOINT_1",
        volumes = {"SLOT_015B", "SLOT_0175", "SLOT_0180", "SLOT_0192", "SLOT_0198"},
        rally = "80C092AC", rally_volume = "RALLY_POINT_SPAWN_OVERRIDE_VOLUME_BLOCKS",
        site_key = 0x0B32FC13},
    {region = 296, tag = "80C0B311", root = "PF_EVENT_MULTIPOINT_1",
        volumes = {"SLOT_021C", "SLOT_023F", "SLOT_027F", "SLOT_0297"},
        rally = "80C0AA71", rally_volume = "RALLY_POINT_SPAWN_OVERRIDE_VOLUME1",
        site_key = 0x757EF9A5},
    {region = 296, tag = "80C0BACC", root = "PF_EVENT_MULTIPOINT_2",
        volumes = {"SLOT_015B", "SLOT_0175", "SLOT_0180", "SLOT_0192", "SLOT_0198"},
        rally = "80C0A9B6", rally_volume = "RALLY_POINT_SPAWN_OVERRIDE_VOLUME1",
        site_key = 0x757EF9A6},
}

--- Builds the Glimmer Extraction handler of every placement, with its region and sensor.
---@return table[] sites {region, sensor, handler} in the order of EXTRACTIONS.
function events.extractions(mission)
    local sites = {}
    for index, placement in ipairs(EXTRACTIONS) do
        local definition = glimmer_site.bind(mission, placement)
        sites[index] = {region = placement.region, sensor = definition.event_sensor,
            handler = scheduled(glimmer.new(definition), placement.site_key)}
    end
    return sites
end

--- Generated names of the rig at The Cistern. Its dialogue sensor holds the cue hashes of the
--- EDZ rig in the same order, so the cue ordinals are the EDZ site's. Rally 80C080C1 is paired by
--- volume position, 13 m from the rig.
local CISTERN_RIG = {
    suffix = "_80C0806D",
    navpoint = "LOCATION_POINT_80C0806D",
    cues = {CUE_ALERT = 0, CUE_START = 1, CUE_VENTS = 2, CUE_FAILED = 3, CUE_SUCCESS = 4,
        CUE_HEROIC_SUCCESS = 6, CUE_HEROIC_FAILED = 3},
    psion_row = "INJECTION_RIG_DFFC1441",
    evacuate_row = "INJECTION_RIG_15417709",
    valus_row = "INJECTION_RIG_5DE0F6DF",
    final_row = "INJECTION_RIG",
    rally_key = "_80C080C1",
    rally_volume = "RALLY_POINT_SPAWN_OVERRIDE_VOLUME_ISLAND_80C080C1",
}
local CISTERN_RIG_SITE_KEY = 0x8DA5D073

--- Builds the Injection Rig handler of The Cistern.
function events.cistern_rig(mission)
    return scheduled(injection_rig.new(rig_site.bind(mission, CISTERN_RIG)), CISTERN_RIG_SITE_KEY)
end

-- Generated names of the Servitor site: prefab slots carry no registry suffix, zone sensors do.
local SERVITOR_PREFIX, SERVITOR_SUFFIX = "PF_EVENT_FALLEN_SERVITOR_1_", "_80C03459"
-- Authored counts: nine covers around the site, three Vandals on the skeleton-crew Skiff.
local SERVITOR_COVER_COUNT, SKELETON_CREW_COUNT = 9, 3

--- Resolves the Servitor site's content into the Ether Resupply definition.
local function bind_ether_resupply(mission)
    local Slot = mission.Slot
    local function slot(stem)
        return lib.one(Slot[SERVITOR_PREFIX .. stem], "servitor slot " .. stem)
    end
    local function sensor(stem)
        return lib.one(Slot[stem .. SERVITOR_SUFFIX], "servitor sensor " .. stem)
    end
    --- A unit of the site: the squad id places it, the squad slot reports its deaths.
    local function unit(stem)
        return {squad = lib.one(mission.Squad[SERVITOR_PREFIX .. stem], "servitor squad " .. stem),
            slot = slot(stem)}
    end
    local directive_sensor = sensor("M_DIRECTIVE_SENSOR")
    local directive = lib.one(mission.Directive.ETHER_RESUPPLY, "directive")
    assert(directive.sensor == directive_sensor,
        "directive belongs to another sensor: " .. directive.id)
    local area = slot("TV_OBJECTIVE_AND_ENGAGEMENT_BIND")
    -- The Prime takes its authored boss objective.
    local boss_objective = slot("OBJ_BOSS")
    local prime = unit("SQ_ULTRA_SERVITOR")
    prime.member = slot("SQ_ULTRA_SERVITOR_BOSS")
    prime.objective = boss_objective
    prime.task_group =
        lib.one(mission.TaskGroup[SERVITOR_PREFIX .. "OBJ_BOSS"], "boss task group").GROUP_0
    local skiff = unit("PF_FALLEN_SKIFF_SKELETON_CREW_SQ_DROPSHIP")
    local crew, cover = {}, {}
    for index = 1, SKELETON_CREW_COUNT do
        crew[index] = unit("SQ_SKELETON_CREW_VANDAL_" .. index)
    end
    for index = 0, SERVITOR_COVER_COUNT - 1 do cover[#cover + 1] = slot("O_COVER_" .. index) end
    return {
        prime = prime,
        resupply = {
            shield = slot("HO_INVINCIBLE_ULTRA"),
            filter = slot("OF_ULTRA_SERVITOR"),
            lone = unit("SQ_CELLKEEPER_SHIELD"),
            trio = {unit("SQ_CELLKEEPER_SERVITOR_1"), unit("SQ_CELLKEEPER_SERVITOR_2"),
                unit("SQ_CELLKEEPER_SERVITOR_3")},
            support = {
                {unit("SQ_SUPPORT_BASE_1"), unit("SQ_SUPPORT_MAJOR_1_TIER_1")},
                {unit("SQ_SUPPORT_BASE_2"), unit("SQ_SUPPORT_MAJOR_2_TIER_1")},
                {unit("SQ_SUPPORT_BASE_3"), unit("SQ_SCORCH_CAPTAIN")},
            },
            heroic_support = unit("SQ_MELEE_FODDER_TIER_2"),
            heroic_teleporter = slot("O_HEROIC_PLAYER_TELEPORTER"),
            enrage = slot("SEQ_BOSS_ENRAGE_CUE"),
            charge_end = slot("SEQ_BOSS_HEROIC_CHARGE_END"),
        },
        intro = {
            ketch = lib.one(Slot.KETCH_INTRO_PREFAB_1_O_KETCH_INTRO, "ketch intro"),
            sequence = slot("SEQ_INTRO_BEHAVIOR"),
            active = slot("SEQ_EVENT_ACTIVE_BEHAVIOR"),
            communion = lib.one(mission.Scene[SERVITOR_PREFIX .. "SCN_INTRO_ETHER_COMMUNION"],
                "communion scene"),
            beam = slot("O_SKY_BEAM"),
            cover = cover,
            skiff = skiff,
            crew = crew,
        },
        chest = slot("PF_REWARD_CHEST_CHEST_TIER0_OBJECT"),
        directive_sensor = directive_sensor,
        directive = directive,
        engagement = sensor("M_ENGAGEMENT_SENSOR"),
        engagement_volume = area,
        dialog = sensor("M_DIALOG_SENSOR"),
        music = sensor("M_MUSIC_SENSOR"),
        event_sensor = sensor("M_PUBLIC_EVENT_SENSOR"),
        event_area = area,
        navpoint = sensor("LOCATION_POINT"),
        rally = rally.bind(mission, WATCHERS_GRAVE_RALLY),
    }
end

--- Builds the Watcher's Grave Ether Resupply handler.
function events.watchers_grave_ether(mission)
    return scheduled(ether.new(bind_ether_resupply(mission)), ETHER_SITE_KEY)
end

return events
