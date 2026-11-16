-- Binds one authored Cabal Excavation prefab. Placements share its layout and differ in root
-- prefab, registry tag and rally prefab.
local lib = require("lib.mission_lib")
local rally = require("lib.public_events.rally")
local site_names = require("lib.public_events.site_names")

local site = {}

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
-- Rows of the directive sensor by title and name hash.
local EXCAVATION_ROW = {"CABAL_EXCAVATION", 0x91CA8143}
local VALUS_ROW = {"DEFEAT_EXCAVATION_VALUS", 0xACE3C8C6}

---@class CabalPlacement
---@field tag string Object tag of the placement.
---@field root string Root prefab stem in key form; placements name it differently.
---@field rally string Object tag of the rally prefab paired with this site.
---@field rally_volume string|nil Stem of the rally's volume when the site names its own.

--- Resolves a placement's authored content into the excavation definition.
---@param mission table Generated mission module.
---@param placement CabalPlacement
---@return table definition Input of the Cabal Excavation encounter.
function site.bind(mission, placement)
    local Slot, Squad = mission.Slot, mission.Squad
    local object = site_names.object(mission, placement.tag, placement.root)
    local function slot(stem) return Slot[object.prefab(stem)] end
    local function zone_slot(stem) return Slot[object.zone(stem)] end
    local function slots(stems)
        local list = {}
        for _, stem in ipairs(stems) do list[#list + 1] = slot(stem) end
        return list
    end
    --- Binds an authored objective to its first task group, the squads' main firing area.
    local function task(stem)
        return {objective = slot(stem),
            group = lib.one(mission.TaskGroup[object.prefab(stem)],
                "cabal task group " .. stem).GROUP_0}
    end
    --- A squad with its pods and authored task; a group index names a pod group waves re-drop.
    local function unit(stem, pods, group, assigned)
        local result = {
            squad = lib.one(Squad[object.prefab(stem)], "cabal squad " .. stem),
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
    local directive_sensor = zone_slot("M_DIRECTIVE_SENSOR")
    local function row(name)
        return site_names.directive(mission, name[1], name[2], directive_sensor)
    end
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
        directive = row(EXCAVATION_ROW),
        heroic_directive = row(VALUS_ROW),
        -- The event object authors no type-47 slot; the rally prefab's point marks the site.
        navpoint = rally.location_point(mission, placement.rally),
        engagement = zone_slot("M_ENGAGEMENT_SENSOR"),
        engagement_volume = slot("ENGAGEMENT_VOLUME"),
        dialog = zone_slot("M_DIALOG_SENSOR"),
        music = zone_slot("M_MUSIC_SENSOR"),
        event_sensor = zone_slot("M_PUBLIC_EVENT_SENSOR"),
        event_area = slot("ENGAGEMENT_VOLUME"),
        rally = rally.bind_object(mission, placement.rally, placement.rally_volume),
    }
end

return site
