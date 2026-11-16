-- Binds one authored Spire prefab. Sites share its layout and differ in generated names.
local lib = require("lib.mission_lib")
local rally = require("lib.public_events.rally")
local site_names = require("lib.public_events.site_names")
local c = require("lib.public_events.spire_integration.settings")

local site = {}

-- The prefab has three lanes, each with three capture-challenger squads.
local LANE_COUNT, CHALLENGERS_PER_LANE = 3, 3
-- Rows of the directive sensor by title and name hash: incoming, objective, heroic objective.
local INCOMING_ROW = {"SPIRE_INTEGRATION", 0x0C12E05C}
local OBJECTIVE_ROW = {"DISRUPT_VEX_CONSTRUCTION", 0x68E99712}
local HEROIC_ROW = {"HOLD_OFF_ELITE_VEX", 0xCF07C635}

---@class SpirePlacement
---@field tag string Object tag of the placement.
---@field root string Root prefab stem in key form; placements name it differently.
---@field area string[] Stems of the joining volumes; the first is the event centre.
---@field navpoint string|nil Prefab stem of the marker of a placement with no location point.
---@field rally string Object tag of the rally prefab paired with this site.
---@field rally_volume string|nil Stem of the rally's volume when the site names its own.

--- Resolves a placement's authored content into the Spire event definition.
---@param mission table Generated mission module.
---@param placement SpirePlacement
---@return table definition Input of the Spire encounter.
function site.bind(mission, placement)
    local Slot, Squad = mission.Slot, mission.Squad
    local object = site_names.object(mission, placement.tag, placement.root)
    local ids = {prefab = object.prefab, zone = object.zone, area = placement.area}
    local function row(name, sensor)
        return site_names.directive(mission, name[1], name[2], sensor)
    end
    local function squad(stem)
        return lib.one(Squad[ids.prefab(stem)], "vexblock squad " .. stem)
    end
    local function slot(stem) return lib.one(Slot[ids.prefab(stem)], "vexblock slot " .. stem) end
    --- A unit of the site; an objective makes its members walk the lane to the spire.
    local function unit(stem, objective, group)
        return {squad = squad(stem), slot = slot(stem), objective = objective, task_group = group}
    end

    local lanes = {}
    local barrier_props = {}
    local conflux_props = {}
    local plates = {}
    local monitors = {}
    local area = {}
    for _, stem in ipairs(ids.area) do
        area[#area + 1] = lib.one(Slot[ids.zone(stem)], "event area " .. stem)
    end
    for lane = 0, LANE_COUNT - 1 do
        local prefix = "PF_LANE_" .. lane .. "_"
        local objective_name = ids.prefab(prefix .. "OBJ_SACRIFICE")
        local objective = lib.one(Slot[objective_name], "vexblock objective " .. objective_name)
        local group = lib.one(mission.TaskGroup[objective_name],
            "vexblock task group " .. objective_name).GROUP_0
        local waves = {}
        for _, stem in ipairs({"SQ_GOBLINS", "SQ_HOBGOBLINS", "SQ_MINOTAURS", "SQ_MAJOR_GOBLINS",
            "SQ_HYDRA", "SQ_HEADLESS_GOBLINS_RUNNERS", "SQ_HEADLESS_MINOTAURS_RUNNERS",
            "SQ_MAJOR_MINOTAURS", "SQ_MAJOR_HYDRA"}) do
            waves[#waves + 1] = unit(prefix .. stem, objective, group)
        end
        local disruptors = {}
        for index = 1, CHALLENGERS_PER_LANE do
            disruptors[index] = unit(prefix .. "SQ_BARRIER_CHALLENGER" .. index)
        end
        local goblins = ids.prefab(prefix .. "SQ_GOBLINS")
        local sacrifice = lib.one(mission.ActorTemperament[goblins], "vexblock temperaments " .. goblins)
        barrier_props[#barrier_props + 1] = slot(prefix .. "BARRIER_O_BLOCK_BARRIER")
        conflux_props[#conflux_props + 1] = slot(prefix .. "BARRIER_O_CONFLUX")
        plates[#plates + 1] = slot(prefix .. "BARRIER_O_BARRIER_CAPTURABLE")
        for _, stem in ipairs({"BARRIER_PM_PROXIMITY", "BARRIER_PM_CONTROL_AREA"}) do
            monitors[#monitors + 1] = slot(prefix .. stem)
        end
        local lane_area = object.find(prefix .. "BARRIER_TV_ENGAGEMENT")
        if lane_area ~= nil then area[#area + 1] = Slot[lane_area] end
        lanes[lane + 1] = {
            waves = waves,
            disruptors = disruptors,
            objective = objective,
            sacrifice = lib.one(
                sacrifice[string.format("KEY_%08X", c.GOBLIN_SACRIFICE_TEMPERAMENT)],
                "sacrifice temperament " .. goblins),
            barrier = barrier_props[#barrier_props],
            stream = slot(prefix .. "BARRIER_HO_VEX_BUG_STREAM"),
            stream_filter = slot(prefix .. "BARRIER_OF_VEX_BUG_STREAM"),
            plate = plates[#plates],
            devices = {
                slot(prefix .. "BARRIER_D_CONFLUX"), slot(prefix .. "BARRIER_D_BLOCK_BARRIER"),
            },
        }
    end
    local directive_sensor = lib.one(Slot[ids.zone("M_DIRECTIVE_SENSOR")], "directive sensor")
    local heroic = {
        audio = slot("SEQ_VEX_BLOCK_HEROIC_START_AUDIO"),
        directive = row(HEROIC_ROW, directive_sensor),
        clouds = {},
        scenes = {},
        guards = {},
    }
    for _, side in ipairs({"LEFT", "MAIN", "RIGHT"}) do
        local stem = "PF_VEXBLOCK_HEROIC_"
        heroic.clouds[#heroic.clouds + 1] = slot(stem .. "OBJ_VEX_CLOUD_" .. side)
        heroic.scenes[#heroic.scenes + 1] = lib.one(
            mission.Scene[ids.prefab(stem .. "SCENE_VEX_CLOUD_" .. side)], "heroic scene " .. side)
        local objective_name = ids.prefab(stem .. "OBJ_GUARD_" .. side)
        heroic.guards[#heroic.guards + 1] = unit(stem .. "SQ_GUARD_" .. side,
            lib.one(Slot[objective_name], "heroic objective " .. side),
            lib.one(mission.TaskGroup[objective_name], "heroic task group " .. side).GROUP_0)
    end
    -- Placements author different numbers of covers around the spire; Exodus Black has none.
    local cover = {}
    for index, key in ipairs(object.numbered("O_VEX_COV_")) do cover[index] = Slot[key] end
    local directive = row(OBJECTIVE_ROW, directive_sensor)
    local incoming = row(INCOMING_ROW, directive_sensor)
    local navpoint = placement.navpoint ~= nil and ids.prefab(placement.navpoint)
        or ids.zone("LOCATION_POINT")
    return {
        -- Shared event definition.
        directive_sensor = directive_sensor,
        engagement = lib.one(Slot[ids.zone("M_ENGAGEMENT_SENSOR")], "engagement sensor"),
        engagement_volumes = area,
        -- Each site's sensor holds its own lines under the shared cue order.
        dialog = lib.one(Slot[ids.zone("M_DIALOG_SENSOR")], "dialog sensor"),
        music = lib.one(Slot[ids.zone("M_MUSIC_SENSOR")], "music sensor"),
        chest = slot("PF_REWARD_CHEST_TIER0_OBJECT"),
        rally = rally.bind_object(mission, placement.rally, placement.rally_volume),
        event_sensor = lib.one(Slot[ids.zone("M_PUBLIC_EVENT_SENSOR")], "public event sensor"),
        event_area = area[1],
        -- Spire mechanics and scenery.
        lanes = lanes,
        barrier_props = barrier_props,
        conflux_props = conflux_props,
        plates = plates,
        monitors = monitors,
        heroic = heroic,
        intro = slot("SEQ_INTRO_BEHAVIOR"),
        active = slot("SEQ_EVENT_ACTIVE_BEHAVIOR"),
        spire = slot("PF_VEXBLOCK_O_BLOCK"),
        beacon = slot("PF_VEXBLOCK_O_BEACON"),
        stream_target = slot("PF_VEXBLOCK_O_VEX_BUG_STREAM_TARGET"),
        cover = cover,
        opening = unit("SQ_INITIAL_VEX"),
        navpoint = lib.one(Slot[navpoint], "location point"),
        directive = directive,
        incoming = incoming,
    }
end

return site
