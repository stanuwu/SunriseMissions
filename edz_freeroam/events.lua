local lib = require("lib.mission_lib")
local rally = require("lib.public_events.rally")
local cabal = require("lib.public_events.cabal_excavation.encounter")
local injection_rig = require("lib.public_events.injection_rig.encounter")
local rig_site = require("lib.public_events.injection_rig.site")
local glimmer = require("lib.public_events.glimmer_extraction.encounter")
local glimmer_site = require("lib.public_events.glimmer_extraction.site")
local ether = require("lib.public_events.ether_resupply.encounter")
local weapons = require("lib.public_events.weapons_exchange.encounter")
local site_names = require("lib.public_events.site_names")

local events = {}

-- Eight authored cover pieces surround the drill; the two sniper covers stand apart.
local COVER_COUNT, SNIPER_COVER_COUNT = 8, 2
-- Each wave's authored spawn rule names one pod group as its spawn points.
local MAIN, SIDE = 1, 2
local MAIN_PODS = {"WAVE_DROP_POD_GROUP_0", "WAVE_DROP_POD_GROUP_1", "WAVE_DROP_POD_GROUP_2"}
local SIDE_PODS = {"WAVE_DROP_POD_SIDE_GROUP_0", "WAVE_DROP_POD_SIDE_GROUP_1",
    "WAVE_DROP_POD_SIDE_GROUP_2"}
local WAVES = {
    {squad = "EASY_WAVE01_SQUAD", group = MAIN}, {squad = "EASY_WAVE02_SQUAD", group = SIDE},
    {squad = "MEDIUM_WAVE01_SQUAD", group = SIDE}, {squad = "MEDIUM_WAVE02_SQUAD", group = MAIN},
    {squad = "HARD_WAVE01_SQUAD", group = MAIN}, {squad = "HARD_WAVE02_SQUAD", group = MAIN},
}
-- Heroic reinforcements share the main pods; the Valus has its own pod.
local HEROIC_WAVES = {"HEROIC_MELEE_SQUAD", "HEROIC_HEAVY_SQUAD", "HEROIC_FODDER_SQUAD"}
-- Three authored aircraft squads; their anchors are the automatic placements, not pods.
local THRESHER_COUNT = 3
-- The first authored barrage group lands six artillery objects inside the artillery area.
local BARRAGE, BARRAGE_SIZE = 0, 6

--- Binds the Winding Cove drill site.
local function bind_winding_cove(mission)
    local Slot, Squad = mission.Slot, mission.Squad
    local function slot(stem)
        return lib.one(Slot["CABAL_DRILL_CORE_" .. stem], "cabal slot " .. stem)
    end
    local function slots(stems)
        local list = {}
        for _, stem in ipairs(stems) do list[#list + 1] = slot(stem) end
        return list
    end
    --- Binds an authored objective to its first task group, the squads' main firing area.
    local function task(stem)
        local name = "CABAL_DRILL_CORE_" .. stem
        return {objective = slot(stem),
            group = lib.one(mission.TaskGroup[name], "cabal task group " .. stem).GROUP_0}
    end
    --- A squad with its pods and authored task; a group index names a pod group waves re-drop.
    local function unit(stem, pods, group, assigned)
        local result = {
            squad = lib.one(Squad["CABAL_DRILL_CORE_" .. stem], "cabal squad " .. stem),
            slot = slot(stem), pods = pods, group = group}
        if assigned ~= nil then
            result.objective, result.task_group = assigned.objective, assigned.group
        end
        return result
    end

    local pod_groups = {[MAIN] = slots(MAIN_PODS), [SIDE] = slots(SIDE_PODS)}
    local drill_task, heroic_task = task("DRILL_OBJECTIVE"), task("HEROIC_OBJECTIVE")
    local waves = {}
    for index, wave in ipairs(WAVES) do
        waves[index] = unit(wave.squad, pod_groups[wave.group], wave.group, drill_task)
    end
    local heroic_waves = {}
    for _, stem in ipairs(HEROIC_WAVES) do
        heroic_waves[#heroic_waves + 1] = unit(stem, pod_groups[MAIN], MAIN, heroic_task)
    end
    local threshers = {}
    for index = 1, THRESHER_COUNT do
        threshers[index] = unit("MOSQUITO0" .. index .. "_SQUAD", {})
        threshers[index].pilot = slot("MOSQUITO0" .. index .. "_SQUAD_PILOT")
    end
    local artillery = {slot("ARTILLERY_AREA_OBJECT")}
    for index = 0, BARRAGE_SIZE - 1 do
        artillery[#artillery + 1] =
            slot("ARTILLERY_BARRAGE_" .. BARRAGE .. "_ARTILLERY_OBJECT_" .. index)
    end
    local sniper_pod = slots({"SNIPER_DROP_POD_OBJECT"})
    local ultra_pod = slots({"ULTRA_DROP_POD_OBJECT"})
    local pods = {}
    for _, group in ipairs({pod_groups[MAIN], pod_groups[SIDE], sniper_pod, ultra_pod}) do
        for _, pod in ipairs(group) do pods[#pods + 1] = pod end
    end
    local cover = {}
    for index = 0, COVER_COUNT - 1 do
        cover[#cover + 1] = slot("COVER_OBJECT_" .. index)
    end
    for index = 0, SNIPER_COVER_COUNT - 1 do
        cover[#cover + 1] = slot("SNIPER_COVER_OBJECT_" .. index)
    end
    local directive_sensor = lib.one(Slot.M_DIRECTIVE_SENSOR_80BE4370, "directive sensor")
    local directive = lib.one(mission.Directive.CABAL_EXCAVATION, "override directive")
    local heroic_directive = lib.one(mission.Directive.DEFEAT_EXCAVATION_VALUS, "heroic directive")
    assert(directive.sensor == directive_sensor,
        "override directive belongs to another sensor: " .. directive.id)
    assert(heroic_directive.sensor == directive_sensor,
        "heroic directive belongs to another sensor: " .. heroic_directive.id)
    local rally_sensor = lib.one(Slot.M_DIRECTIVE_SENSOR_80BE3F78, "rally directive sensor")
    return {
        lander = {object = slot("CABAL_DRILL_OBJECT"), device = slot("CABAL_DRILL_DEVICE")},
        ship = {object = slot("CABAL_ASSAULT_SHIP_OBJECT"),
            device = slot("CABAL_ASSAULT_SHIP_DEVICE")},
        zone = slot("COUNTDOWN_ZONE_OBJECT"),
        ring = slot("CAPTURE_RING_OBJECT"),
        cover = cover,
        chest = slot("CHEST_PREFAB_CHEST_TIER0_OBJECT"),
        intro = slot("INTRO_BEHAVIOR_SEQUENCE"),
        active = slot("SEQ_EVENT_ACTIVE_BEHAVIOR"),
        waves = waves,
        heroic_waves = heroic_waves,
        threshers = threshers,
        thresher_path = slot("MOSQUITO_ENTRANCE_PATH"),
        artillery = artillery,
        sniper = unit("PSION_SNIPER_SQUAD", sniper_pod, nil, task("SNIPER_OBJECTIVE")),
        valus = unit("ULTRA_BOSS_SQUAD", ultra_pod, nil, heroic_task),
        pod_groups = pod_groups,
        pods = pods,
        directive_sensor = directive_sensor,
        directive = directive,
        heroic_directive = heroic_directive,
        -- The event registry authors no type-47 slot; the rally prefab's point marks the site.
        navpoint = lib.one(Slot.EVENT_RALLY_POINT_LOCATION_POINT, "location point"),
        engagement = lib.one(Slot.M_ENGAGEMENT_SENSOR_80BE4370, "engagement sensor"),
        engagement_volume = slot("ENGAGEMENT_VOLUME"),
        dialog = lib.one(Slot.M_DIALOG_SENSOR_80BE4370, "dialog sensor"),
        music = lib.one(Slot.M_MUSIC_SENSOR_80BE4370, "music sensor"),
        event_sensor = lib.one(Slot.M_PUBLIC_EVENT_SENSOR_80BE4370, "public event sensor"),
        event_area = slot("ENGAGEMENT_VOLUME"),
        rally = {
            flag = lib.one(Slot.EVENT_RALLY_POINT_RALLY_FLAG, "rally flag"),
            device = lib.one(Slot.EVENT_RALLY_POINT_RALLY_FLAG_DEVICE, "flag device"),
            sensor = rally_sensor,
            engagement = lib.one(Slot.M_ENGAGEMENT_SENSOR_80BE3F78, "rally engagement sensor"),
            volume = lib.one(Slot.RALLY_POINT_SPAWN_OVERRIDE_VOLUME_80BE3F78, "rally volume"),
            directive = rally.find_directive(mission, rally_sensor),
            incident_target = rally.FLAG_INCIDENT,
        },
    }
end

--- Binds the region 24 Ether Resupply site.
local function bind_ether_resupply(mission)
    local Slot = mission.Slot
    local function slot(stem)
        return lib.one(Slot["PF_EVENT_FALLEN_SERVITOR_1_" .. stem .. "_80BE2C5D"],
            "ether slot " .. stem)
    end
    local directive_sensor = lib.one(Slot.M_DIRECTIVE_SENSOR_80BE2C5D, "directive sensor")
    local directive = lib.one(mission.Directive.ETHER_RESUPPLY, "directive")
    assert(directive.sensor == directive_sensor,
        "directive belongs to another sensor: " .. directive.id)
    local area = slot("TV_OBJECTIVE_AND_ENGAGEMENT_BIND")
    local prime_squad = mission.Squad.PF_EVENT_FALLEN_SERVITOR_1_SQ_ULTRA_SERVITOR_80BE2C5D
    return {
        -- The squad slot reports the Prime's death; the squad id places it.
        prime = {squad = lib.one(prime_squad, "prime squad"), slot = slot("SQ_ULTRA_SERVITOR")},
        chest = slot("PF_REWARD_CHEST_CHEST_TIER0_OBJECT"),
        directive_sensor = directive_sensor,
        directive = directive,
        engagement = lib.one(Slot.M_ENGAGEMENT_SENSOR_80BE2C5D, "engagement sensor"),
        engagement_volume = area,
        dialog = lib.one(Slot.M_DIALOG_SENSOR_80BE2C5D, "dialog sensor"),
        music = lib.one(Slot.M_MUSIC_SENSOR_80BE2C5D, "music sensor"),
        event_sensor = lib.one(Slot.M_PUBLIC_EVENT_SENSOR_80BE2C5D, "public event sensor"),
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
    return cabal.new(bind_winding_cove(mission))
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

--- Builds the region 24 Ether Resupply handler.
function events.ether_resupply(mission)
    return ether.new(bind_ether_resupply(mission))
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
