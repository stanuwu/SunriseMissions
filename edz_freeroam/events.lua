local lib = require("lib.mission_lib")
local rally = require("lib.public_events.rally")
local cabal = require("lib.public_events.cabal_excavation.encounter")
local injection_rig = require("lib.public_events.injection_rig.encounter")
local rig_site = require("lib.public_events.injection_rig.site")
local glimmer = require("lib.public_events.glimmer_extraction.encounter")
local ether = require("lib.public_events.ether_resupply.encounter")
local weapons = require("lib.public_events.weapons_exchange.encounter")

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

--- Binds the Winding Cove drill site; other sites require their own verified identities.
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

--- Binds the region 24 Ether Resupply site; other sites require their own verified identities.
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

-- The prefab tree of this registry; its flag stands 7.6 m from the site's props.
local TANK, TANK_TAG, TANK_RALLY = "PF_EVENT_SPIDER_TANK_", "_80BE2ECB", "80BE26FE"
-- Authored counts: three cache arrays, each with two receptacles and three barrier shields.
local ARRAY_COUNT, RECEPTACLE_COUNT, SHIELD_COUNT = 3, 2, 3
-- Roster order: opening squads, Walker drop, heroic drop, heroic escort. The cache guards use the
-- medium tier; the hard tier and the plain cache squads (no members) are never placed.
local TANK_ROSTER = {"SQ_INITIAL_SCORCH_CAPTAIN", "SQ_TANK_FODDER_CACHE_MEDIUM_1",
    "SQ_TANK_FODDER_CACHE_MEDIUM_2", "SQ_TANK_FODDER_CACHE_MEDIUM_3", "SQ_DROPSHIP_TANK",
    "SQ_TANK", "SQ_TANK_MINIONS", "SQ_DROPSHIP_HEROIC", "SQ_HEROIC_TANK",
    "SQ_TANK_MINIONS_HEROIC", "SQ_HEROIC_REGULAR", "SQ_HEROIC_ANCHOR"}

--- Binds the region 24 Weapons Exchange site; other sites require their own verified identities.
local function bind_weapons_exchange(mission)
    local Slot, Squad = mission.Slot, mission.Squad
    local function slot(stem)
        return lib.one(Slot[TANK .. stem .. TANK_TAG], "weapons exchange slot " .. stem)
    end
    local function slots(stems)
        local list = {}
        for _, stem in ipairs(stems) do list[#list + 1] = slot(stem) end
        return list
    end
    local roster = {}
    for index, stem in ipairs(TANK_ROSTER) do
        roster[index] = {slot = slot(stem),
            squad = lib.one(Squad[TANK .. stem .. TANK_TAG], "weapons squad " .. stem)}
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
    local directive_sensor = lib.one(Slot["M_DIRECTIVE_SENSOR" .. TANK_TAG], "directive sensor")
    local function row(name)
        local directive = lib.one(mission.Directive[name], "weapons exchange directive " .. name)
        assert(directive.sensor == directive_sensor,
            "directive belongs to another sensor: " .. directive.id)
        return directive
    end
    local rally_tag = "_" .. TANK_RALLY
    local rally_sensor = lib.one(Slot["M_DIRECTIVE_SENSOR" .. rally_tag], "rally directive sensor")
    local rally_row = lib.one(rally.find_directive(mission, rally_sensor),
        "rally directive")
    assert(rally_row.sensor == rally_sensor, "rally directive belongs to another sensor")
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
        ketch = lib.one(Slot["KETCH_INTRO_PREFAB_1_O_KETCH_INTRO" .. TANK_TAG], "ketch"),
        sequences = {
            intro = slot("SEQ_INTRO_BEHAVIOR"), active = slot("SEQ_EVENT_ACTIVE_BEHAVIOR"),
            inbound = slot("SEQ_SUPER_SPIDER_TANK_INBOUND"), heroic = slot("SEQ_HEROIC_TRIGGERED"),
        },
        chest = slot("CHEST_PREFAB_CHEST_TIER0_OBJECT"),
        navpoint = lib.one(Slot["LOCATION_POINT" .. TANK_TAG], "location point"),
        directive_sensor = directive_sensor,
        directive = row("DISRUPT_WEAPONS_EXCHANGE_82A993F5"),
        walker_directive = row("DESTROY_THE_ARSENAL_WALKER_FA872386"),
        heroic_directive = row("DEMOLISH_THE_WALKERS_78D5E31A"),
        engagement = lib.one(Slot["M_ENGAGEMENT_SENSOR" .. TANK_TAG], "engagement sensor"),
        -- Content names no engagement volume; the four authored volumes are the event area.
        engagement_volumes = {slot("EVENT_SPIDER_TANK_COMM_ARRAY_1_TV_WEAPON_CACHE"),
            lib.one(Slot["SLOT_00D5" .. TANK_TAG], "volume 00D5"),
            lib.one(Slot["SLOT_00E7" .. TANK_TAG], "volume 00E7"),
            lib.one(Slot["SLOT_0104" .. TANK_TAG], "volume 0104")},
        dialog = lib.one(Slot["M_DIALOG_SENSOR" .. TANK_TAG], "dialog sensor"),
        music = lib.one(Slot["M_MUSIC_SENSOR" .. TANK_TAG], "music sensor"),
        rally = {
            flag = lib.one(Slot["PF_PUBLIC_EVENT_RALLY_POINT_RALLY_FLAG" .. rally_tag],
                "rally flag"),
            device = lib.one(Slot["PF_PUBLIC_EVENT_RALLY_POINT_RALLY_FLAG_DEVICE" .. rally_tag],
                "flag device"),
            sensor = rally_sensor,
            engagement = lib.one(Slot["M_ENGAGEMENT_SENSOR" .. rally_tag],
                "rally engagement sensor"),
            volume = lib.one(Slot["SPAWNOVERRIDEVOLUME" .. rally_tag], "rally volume"),
            directive = rally_row,
            incident_target = rally.FLAG_INCIDENT,
        },
    }
end

--- Builds the Winding Cove Cabal Excavation handler on the shared event skeleton.
function events.winding_cove(mission)
    return cabal.new(bind_winding_cove(mission))
end

-- The prefab tree of this registry; its first placement stands beside this rally flag.
local MULTIPOINT, TAG, MULTIPOINT_RALLY = "PF_EVENT_MULTIPOINT_", "_80BE5D9B", "80BE4DC4"
-- Authored site order; the flag distances of 86 m and 176 m match the reference's two moves.
local SITE_COUNT = 3
-- Radial covers around each drill.
local RADIAL_COVER_COUNT = 4
-- Every authored volume of the registry; the third site's own engagement volume is unnamed, so
-- the event area is their union and may reach past the three sites.
local MULTIPOINT_VOLUMES = {MULTIPOINT .. "PF_PLACEMENT_0_PF_FALLEN_DRILL_TV_ENGAGEMENT",
    MULTIPOINT .. "PF_PLACEMENT_1_PF_FALLEN_DRILL_TV_ENGAGEMENT", "SLOT_015B", "SLOT_0175",
    "SLOT_0192", "SLOT_0198"}
-- Authored heroic waves in escalating order; the finale boss comes with the last wave.
local GLIMMER_WAVES = {"SQ_HEROIC_INITIAL_LIGHT_WAVE", "SQ_HEROIC_STEALTH_MELEE_WAVE",
    "SQ_HEROIC_HEAVY_WAVE", "SQ_HEROIC_FINALE_WAVE", "SQ_HEROIC_FINALE_BOSS"}

--- Binds the region 96 extraction site; other sites require their own verified identities.
local function bind_multipoint(mission)
    local Slot, Squad = mission.Slot, mission.Squad
    local function slot(stem)
        return lib.one(Slot[MULTIPOINT .. stem .. TAG], "glimmer slot " .. stem)
    end
    local function unit(stem)
        return {squad = lib.one(Squad[MULTIPOINT .. stem .. TAG], "glimmer squad " .. stem),
            slot = slot(stem)}
    end
    local captains = {"SQ_DEFENDER_BOSS", "SQ_DEFENDER_BOSS_1", "SQ_DEFENDER_BOSS_2"}
    local sites = {}
    for index = 1, SITE_COUNT do
        local prefix = "PF_PLACEMENT_" .. (index - 1) .. "_"
        local drill = prefix .. "PF_FALLEN_DRILL_"
        local deco = drill .. "PF_FALLEN_DRILL_DECO_"
        local objective = MULTIPOINT .. drill .. "OBJ_DRILL_DEFENSE" .. TAG
        local group = lib.one(mission.TaskGroup[objective], "drill task group " .. index).GROUP_0
        local function fighters(stem)
            local fighter = unit(stem)
            fighter.objective = lib.one(Slot[objective], "drill objective " .. index)
            fighter.task_group = group
            fighter.spawn_rule = slot(drill .. "SR_DRILL_NEAR")
            return fighter
        end
        local dropship = unit(drill .. "SQ_DROPSHIP")
        dropship.spawn_rule = slot(drill .. "SR_DROPSHIP")
        local equipment = {slot(deco .. "O_DRILL"), slot(deco .. "O_DRILL_BEACON")}
        for cover = 0, RADIAL_COVER_COUNT - 1 do
            equipment[#equipment + 1] = slot(deco .. "O_RADIAL_COV_" .. cover)
        end
        sites[index] = {
            equipment = equipment,
            machine = slot(prefix .. "PF_EVENT_MULTIPOINT_GENERATOR_"
                .. glimmer.MACHINE_SLOT .. "_O_GENERATOR"),
            dropship = dropship,
            crew = fighters("SQ_DEFENDERS_" .. (index - 1)),
            extractors = fighters("SQ_DEFENDER_ANCHORS_" .. (index - 1)),
            captain = fighters(captains[index]),
        }
    end
    local volumes = {}
    for index, stem in ipairs(MULTIPOINT_VOLUMES) do
        volumes[index] = lib.one(Slot[stem .. TAG], "glimmer volume " .. stem)
    end
    local final = "PF_PLACEMENT_" .. (SITE_COUNT - 1) .. "_"
    local heroic_rule = slot(final .. "PF_FALLEN_DRILL_SR_DRILL_HEROIC")
    local heroic_waves = {}
    for index, stem in ipairs(GLIMMER_WAVES) do
        heroic_waves[index] = unit(stem)
        heroic_waves[index].spawn_rule = heroic_rule
    end
    local directive_sensor = lib.one(Slot["M_DIRECTIVE_SENSOR" .. TAG], "directive sensor")
    local directive = lib.one(mission.Directive.GLIMMER_EXTRACTION, "extraction directive")
    local pursue = lib.one(mission.Directive.PURSUE_THE_FALLEN, "pursue directive")
    local heroic_directive = lib.one(mission.Directive.DEFEND_GLIMMER, "defend directive")
    for _, row in ipairs({directive, pursue, heroic_directive}) do
        assert(row.sensor == directive_sensor, "directive belongs to another sensor: " .. row.id)
    end
    local rally_tag = "_" .. MULTIPOINT_RALLY
    local rally_sensor = lib.one(Slot["M_DIRECTIVE_SENSOR" .. rally_tag], "rally directive sensor")
    return {
        sites = sites,
        heroic_waves = heroic_waves,
        ketch = slot("PF_INTRO_FLIGHT_KETCH_O_KETCH"),
        intro = slot("SEQ_INTRO"),
        active = slot("SEQ_EVENT_ACTIVE_BEHAVIOR"),
        zone = slot(final .. "O_COUNTDOWN_ZONE"),
        ring = slot(final .. "O_CAPTURE_RING"),
        pile = slot(final .. "O_GLIMMER_0"),
        chest = slot(final .. "CHEST_PREFAB_CHEST_TIER0_OBJECT"),
        directive_sensor = directive_sensor,
        directive = directive,
        pursue = pursue,
        heroic_directive = heroic_directive,
        engagement = lib.one(Slot["M_ENGAGEMENT_SENSOR" .. TAG], "engagement sensor"),
        engagement_volumes = volumes,
        dialog = lib.one(Slot["M_DIALOG_SENSOR" .. TAG], "dialog sensor"),
        music = lib.one(Slot["M_MUSIC_SENSOR" .. TAG], "music sensor"),
        event_sensor = lib.one(Slot["M_PUBLIC_EVENT_SENSOR" .. TAG], "public event sensor"),
        event_area = volumes[1],
        navpoint = lib.one(Slot["LOCATION_POINT" .. TAG], "location point"),
        rally = {
            flag = lib.one(Slot["PF_PUBLIC_EVENT_RALLY_POINT_RALLY_FLAG" .. rally_tag],
                "rally flag"),
            device = lib.one(Slot["PF_PUBLIC_EVENT_RALLY_POINT_RALLY_FLAG_DEVICE" .. rally_tag],
                "flag device"),
            sensor = rally_sensor,
            engagement = lib.one(Slot["M_ENGAGEMENT_SENSOR" .. rally_tag],
                "rally engagement sensor"),
            volume = lib.one(Slot["RALLY_POINT_SPAWN_OVERRIDE_VOLUME" .. rally_tag],
                "rally volume"),
            directive = rally.find_directive(mission, rally_sensor),
            incident_target = rally.FLAG_INCIDENT,
        },
    }
end

--- Builds the region 96 Glimmer Extraction handler on the shared event skeleton.
function events.multipoint_extraction(mission)
    return glimmer.new(bind_multipoint(mission))
end

--- Builds the region 24 Ether Resupply handler on the shared event skeleton.
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

--- Builds the region 312 Injection Rig handler on the shared event skeleton.
function events.injection_rig(mission)
    return injection_rig.new(rig_site.bind(mission, RIG_SITE))
end

--- Builds the region 24 Weapons Exchange handler on the shared event skeleton.
function events.weapons_exchange(mission)
    return weapons.new(bind_weapons_exchange(mission))
end

return events
