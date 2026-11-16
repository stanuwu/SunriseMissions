local lib = require("lib.mission_lib")
local rally = require("lib.public_events.rally")
local cabal = require("lib.public_events.cabal_excavation.encounter")
local cabal_site = require("lib.public_events.cabal_excavation.site")
local injection_rig = require("lib.public_events.injection_rig.encounter")
local rig_site = require("lib.public_events.injection_rig.site")
local glimmer = require("lib.public_events.glimmer_extraction.encounter")
local glimmer_site = require("lib.public_events.glimmer_extraction.site")
local ether = require("lib.public_events.ether_resupply.encounter")
local weapons = require("lib.public_events.weapons_exchange.encounter")
local site_names = require("lib.public_events.site_names")

local events = {}

-- The Winding Cove drill site: its object and the rally prefab 24 m from it.
local WINDING_COVE = {tag = "80BE4370", root = "CABAL_DRILL_CORE", rally = "80BE3F78"}

-- Ether Resupply placements: Outskirts and Firebase Hades.
local SERVITORS = {{region = 24, tag = "80BE2C5D"}, {region = 96, tag = "80BE58B2"}}
-- The objective row of the directive sensor by title and name hash.
local ETHER_ROW = {"ETHER_RESUPPLY", 0x186885A4}

--- Binds one Ether Resupply placement.
local function bind_ether_resupply(mission, placement)
    local Slot = mission.Slot
    local object = site_names.object(mission, placement.tag, "PF_EVENT_FALLEN_SERVITOR_1")
    local function slot(stem) return Slot[object.prefab(stem)] end
    local function zone_slot(stem) return Slot[object.zone(stem)] end
    local directive_sensor = zone_slot("M_DIRECTIVE_SENSOR")
    local area = slot("TV_OBJECTIVE_AND_ENGAGEMENT_BIND")
    local prime_squad = mission.Squad[object.prefab("SQ_ULTRA_SERVITOR")]
    return {
        -- The squad slot reports the Prime's death; the squad id places it.
        prime = {squad = lib.one(prime_squad, "prime squad"), slot = slot("SQ_ULTRA_SERVITOR")},
        chest = slot("PF_REWARD_CHEST_CHEST_TIER0_OBJECT"),
        directive_sensor = directive_sensor,
        directive = site_names.directive(mission, ETHER_ROW[1], ETHER_ROW[2], directive_sensor),
        engagement = zone_slot("M_ENGAGEMENT_SENSOR"),
        engagement_volume = area,
        dialog = zone_slot("M_DIALOG_SENSOR"),
        music = zone_slot("M_MUSIC_SENSOR"),
        event_sensor = zone_slot("M_PUBLIC_EVENT_SENSOR"),
        event_area = area,
    }
end

-- Weapons Exchange placements. Each names its object, the three unnamed volumes beside it and
-- the rally prefab nearest it; the first Outskirts flag stands 7.6 m from the site's props.
-- Sunken Isles authors a sky battle instead of the intro Ketch prefab.
local EXCHANGES = {
    {region = 24, tag = "80BE2ECB", volumes = {"SLOT_00D5", "SLOT_00E7", "SLOT_0104"},
        rally = "80BE26FE", rally_volume = "SPAWNOVERRIDEVOLUME"},
    {region = 24, tag = "80BE3148", volumes = {"SLOT_00D5", "SLOT_00E7", "SLOT_0104"},
        rally = "80BE26EE", rally_volume = "SPAWNOVERRIDEVOLUME"},
    {region = 312, tag = "80BE18EB", volumes = {"SLOT_00D1", "SLOT_00D8", "SLOT_0100"},
        rally = "80BE0B1A"},
}
local TANK_ROOT = "PF_EVENT_SPIDER_TANK"
-- Rows of the directive sensor by title and name hash.
local EXCHANGE_ROW = {"DISRUPT_WEAPONS_EXCHANGE", 0x82A993F5}
local WALKER_ROW = {"DESTROY_THE_ARSENAL_WALKER", 0xFA872386}
local WALKERS_ROW = {"DEMOLISH_THE_WALKERS", 0x78D5E31A}
-- Authored counts: three cache arrays, each with two receptacles and three barrier shields.
local ARRAY_COUNT, RECEPTACLE_COUNT, SHIELD_COUNT = 3, 2, 3
-- Roster order: opening squads, Walker drop, heroic drop, heroic escort. The cache guards use the
-- medium tier; the hard tier and the plain cache squads (no members) are never placed.
local TANK_ROSTER = {"SQ_INITIAL_SCORCH_CAPTAIN", "SQ_TANK_FODDER_CACHE_MEDIUM_1",
    "SQ_TANK_FODDER_CACHE_MEDIUM_2", "SQ_TANK_FODDER_CACHE_MEDIUM_3", "SQ_DROPSHIP_TANK",
    "SQ_TANK", "SQ_TANK_MINIONS", "SQ_DROPSHIP_HEROIC", "SQ_HEROIC_TANK",
    "SQ_TANK_MINIONS_HEROIC", "SQ_HEROIC_REGULAR", "SQ_HEROIC_ANCHOR"}

--- Binds one Weapons Exchange placement. The definition leaves the map sensor out, as the
--- family sends it no state; it is returned beside the definition for the zone to attach by.
local function bind_weapons_exchange(mission, placement)
    local Slot, Squad = mission.Slot, mission.Squad
    local object = site_names.object(mission, placement.tag, TANK_ROOT)
    local function slot(stem) return Slot[object.prefab(stem)] end
    local function zone_slot(stem) return Slot[object.zone(stem)] end
    local function slots(stems)
        local list = {}
        for _, stem in ipairs(stems) do list[#list + 1] = slot(stem) end
        return list
    end
    local roster = {}
    for index, stem in ipairs(TANK_ROSTER) do
        roster[index] = {slot = slot(stem),
            squad = lib.one(Squad[object.prefab(stem)], "weapons squad " .. stem)}
    end
    -- The Host sends a flight program only to an actor it holds a body for, so each carrier's
    -- pilot is bound to its squad when the carrier is placed.
    local CARRIER_PILOTS = {SQ_DROPSHIP_TANK = "SQ_DROPSHIP_TANK_PILOT",
        SQ_DROPSHIP_HEROIC = "SQ_DROPSHIP_HEROIC_PILOT"}
    for index, stem in ipairs(TANK_ROSTER) do
        if CARRIER_PILOTS[stem] ~= nil then roster[index].member = slot(CARRIER_PILOTS[stem]) end
    end
    local arrays = {}
    for index = 0, ARRAY_COUNT - 1 do
        local stem = "EVENT_SPIDER_TANK_COMM_ARRAY_" .. index .. "_"
        local shields, receptacles = {slot(stem .. "O_SHIELD")}, {}
        for shield = 1, SHIELD_COUNT - 1 do
            shields[#shields + 1] = slot(stem .. "O_SHIELD_" .. shield)
        end
        for receptacle = 0, RECEPTACLE_COUNT - 1 do
            receptacles[#receptacles + 1] = slot(stem .. "O_RECEPTACLES_" .. receptacle)
        end
        local props = slots({stem .. "O_PEDESTAL", stem .. "O_AVOIDANCE",
            stem .. "O_PLAYER_PHYSICS_BUMP"})
        for _, list in ipairs({shields, receptacles}) do
            for _, object in ipairs(list) do props[#props + 1] = object end
        end
        arrays[index + 1] = {shields = shields, receptacles = receptacles, props = props}
    end
    -- Roles index TANK_ROSTER; these dependencies are site policy, not wire ordinals.
    local CAPTAIN, CACHE_1, CACHE_2, CACHE_3 = 1, 2, 3, 4
    local NORMAL_CARRIER, NORMAL_WALKER, NORMAL_MINIONS = 5, 6, 7
    local HEROIC_CARRIER, HEROIC_WALKER, HEROIC_MINIONS = 8, 9, 10
    local HEROIC_ESCORT_1, HEROIC_ESCORT_2 = 11, 12
    local NORMAL_DROP, HEROIC_DROP = 1, 2
    local directive_sensor = zone_slot("M_DIRECTIVE_SENSOR")
    local function row(name)
        return site_names.directive(mission, name[1], name[2], directive_sensor)
    end
    local ketch = object.find_zone("KETCH_INTRO_PREFAB_1_O_KETCH_INTRO")
    local navpoint = object.find_zone("LOCATION_POINT")
    local volumes = {slot("EVENT_SPIDER_TANK_COMM_ARRAY_1_TV_WEAPON_CACHE")}
    for _, stem in ipairs(placement.volumes) do volumes[#volumes + 1] = zone_slot(stem) end
    return {
        roster = roster,
        opening = {CAPTAIN, CACHE_1, CACHE_2, CACHE_3},
        -- Squads whose refusal aborts the event: the captain and both Walkers with their ships.
        critical = {CAPTAIN, NORMAL_CARRIER, NORMAL_WALKER, HEROIC_CARRIER, HEROIC_WALKER},
        drops = {
            {carrier = NORMAL_CARRIER, walker = NORMAL_WALKER, minions = NORMAL_MINIONS,
                pilot = slot("SQ_DROPSHIP_TANK_PILOT"),
                path = slot("TANK_DROPSHIP_ENTER")},
            {carrier = HEROIC_CARRIER, walker = HEROIC_WALKER, minions = HEROIC_MINIONS,
                pilot = slot("SQ_DROPSHIP_HEROIC_PILOT"),
                path = slot("HEROIC_DROPSHIP_ENTER")},
        },
        walker_drop = NORMAL_DROP,
        heroic_drop = HEROIC_DROP,
        heroic_escort = {HEROIC_ESCORT_1, HEROIC_ESCORT_2},
        arrays = arrays,
        ketch = ketch ~= nil and Slot[ketch] or nil,
        sequences = {
            intro = slot("SEQ_INTRO_BEHAVIOR"), active = slot("SEQ_EVENT_ACTIVE_BEHAVIOR"),
            inbound = slot("SEQ_SUPER_SPIDER_TANK_INBOUND"), heroic = slot("SEQ_HEROIC_TRIGGERED"),
        },
        chest = slot("CHEST_PREFAB_CHEST_TIER0_OBJECT"),
        navpoint = navpoint ~= nil and Slot[navpoint] or nil,
        directive_sensor = directive_sensor,
        directive = row(EXCHANGE_ROW),
        walker_directive = row(WALKER_ROW),
        heroic_directive = row(WALKERS_ROW),
        engagement = zone_slot("M_ENGAGEMENT_SENSOR"),
        -- Content names no engagement volume; the four authored volumes are the event area.
        engagement_volumes = volumes,
        dialog = zone_slot("M_DIALOG_SENSOR"),
        music = zone_slot("M_MUSIC_SENSOR"),
        rally = rally.bind_object(mission, placement.rally, placement.rally_volume),
    }, zone_slot("M_PUBLIC_EVENT_SENSOR")
end

--- Builds the Winding Cove Cabal Excavation handler.
function events.winding_cove(mission)
    return cabal.new(cabal_site.bind(mission, WINDING_COVE))
end

-- Glimmer Extraction placements. Each names its object and root prefab, the unnamed volumes
-- beside it and the rally prefab at its first drill site (paired by volume position).
local EXTRACTIONS = {
    -- Firebase Hades.
    {region = 96, tag = "80BE5D9B", root = "PF_EVENT_MULTIPOINT",
        volumes = {"SLOT_015B", "SLOT_0175", "SLOT_0192", "SLOT_0198"}, rally = "80BE4DC4"},
    -- The Gulch.
    {region = 280, tag = "80BE7652", root = "FALLEN_MULTIPOINT_CORE",
        volumes = {"SLOT_0159", "SLOT_0173", "SLOT_0190", "SLOT_0196"}, rally = "80BE6B63",
        rally_volume = "RALLY_POINT_SPAWN_OVERRIDE_VOLUME_HILL"},
    -- Trostland.
    {region = 408, tag = "80BE91F7", root = "PF_EVENT_MULTIPOINT",
        volumes = {"SLOT_015B", "SLOT_0175", "SLOT_0192", "SLOT_0198"}, rally = "80BE8CE9",
        rally_volume = "MULTIPOINT_OVERRIDE_VOLUME_1"},
    -- The Sludge; it authors four drill sites.
    {region = 448, tag = "80C26607", root = "FALLEN_MULTIPOINT_CORE",
        volumes = {"SLOT_01DF", "SLOT_01E9", "SLOT_0205", "SLOT_020B", "SLOT_0228", "SLOT_022E"},
        rally = "80BE9CF9", rally_volume = "MULTIPOINT_RALLY_SPAWN_OVERRIDE_VOLUME1"},
}

--- Builds the Glimmer Extraction handler of every placement, with its region and sensor.
---@return table[] sites {region, sensor, handler} in the order of EXTRACTIONS.
function events.extractions(mission)
    local sites = {}
    for index, placement in ipairs(EXTRACTIONS) do
        local definition = glimmer_site.bind(mission, placement)
        sites[index] = {region = placement.region, sensor = definition.event_sensor,
            handler = glimmer.new(definition)}
    end
    return sites
end

--- Builds the Ether Resupply handler of every placement, with its region and sensor.
---@return table[] sites {region, sensor, handler} in the order of SERVITORS.
function events.ether_resupplies(mission)
    local sites = {}
    for index, placement in ipairs(SERVITORS) do
        local definition = bind_ether_resupply(mission, placement)
        sites[index] = {region = placement.region, sensor = definition.event_sensor,
            handler = ether.new(definition)}
    end
    return sites
end

--- Generated names of the region 312 rig. Cue text: 4 and 5 the rig leaving, 6 and 7 it exploding.
local RIG_SITE = {
    suffix = "_80BE140D",
    navpoint = "LOCATION_POINT_80BE140D",
    cues = {CUE_ALERT = 0, CUE_START = 1, CUE_VENTS = 2, CUE_FAILED = 3, CUE_SUCCESS = 4,
        CUE_HEROIC_SUCCESS = 6, CUE_HEROIC_FAILED = 3},
    psion_row = "INJECTION_RIG_DFFC1441",
    evacuate_row = "INJECTION_RIG_15417709",
    valus_row = "INJECTION_RIG_5DE0F6DF",
    final_row = "INJECTION_RIG",
}

--- Builds the region 312 Injection Rig handler.
function events.injection_rig(mission)
    return injection_rig.new(rig_site.bind(mission, RIG_SITE))
end

--- Builds the Weapons Exchange handler of every placement, with its region and sensor.
---@return table[] sites {region, sensor, handler} in the order of EXCHANGES.
function events.weapons_exchanges(mission)
    local sites = {}
    for index, placement in ipairs(EXCHANGES) do
        local definition, sensor = bind_weapons_exchange(mission, placement)
        sites[index] = {region = placement.region, sensor = sensor,
            handler = weapons.new(definition)}
    end
    return sites
end

return events
