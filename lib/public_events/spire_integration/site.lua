-- Binds one authored Spire prefab. Sites share its layout and differ in generated names.
local lib = require("lib.mission_lib")
local rally = require("lib.public_events.rally")
local c = require("lib.public_events.spire_integration.settings")

local site = {}

-- The prefab has three lanes, each with three capture-challenger squads.
local LANE_COUNT, CHALLENGERS_PER_LANE = 3, 3
-- Five outer covers accompany cover zero inside the prefab.
local OUTER_COVER_COUNT = 5

---@class SpireSiteNames
---@field prefab fun(stem: string): string Generated name of a slot inside the prefab.
---@field zone fun(stem: string): string Generated name of a sensor beside the prefab.
---@field cover fun(index: integer): string Generated name of one outer cover.
---@field area string[] Zone stems of the joining volumes; the first is the event centre.
---@field navpoint string Generated name of the passive marker slot.
---@field rally_key string Generated suffix of the rally prefab paired with this site.
---@field rally_volume string|nil Exact volume key for a prefab with an exceptional stem.

--- Resolves a site's authored content into the Spire event definition.
---@param mission table Generated mission module.
---@param ids SpireSiteNames
---@return table definition Input of the Spire encounter.
function site.bind(mission, ids)
    local Slot, Squad = mission.Slot, mission.Squad
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
        local lane_area = Slot[ids.prefab(prefix .. "BARRIER_TV_ENGAGEMENT")]
        if lane_area ~= nil then area[#area + 1] = lane_area end
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
    local heroic = {
        audio = slot("SEQ_VEX_BLOCK_HEROIC_START_AUDIO"),
        directive = lib.one(mission.Directive.HOLD_OFF_ELITE_VEX_CF07C635, "heroic directive"),
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
    local cover = {slot("O_VEX_COV_0")}
    for index = 1, OUTER_COVER_COUNT do
        cover[#cover + 1] = lib.one(Slot[ids.cover(index)], "vex cover " .. index)
    end
    local directive = lib.one(mission.Directive.DISRUPT_VEX_CONSTRUCTION, "directive")
    local incoming = lib.one(mission.Directive.SPIRE_INTEGRATION, "incoming directive")
    assert(heroic.directive.slot_row == directive.slot_row,
        "heroic directive belongs to another sensor: " .. heroic.directive.id)
    assert(incoming.slot_row == directive.slot_row,
        "incoming directive belongs to another sensor: " .. incoming.id)
    return {
        -- Shared event definition.
        directive_sensor = lib.one(Slot[ids.zone("M_DIRECTIVE_SENSOR")], "directive sensor"),
        engagement = lib.one(Slot[ids.zone("M_ENGAGEMENT_SENSOR")], "engagement sensor"),
        engagement_volumes = area,
        -- Each site's sensor holds its own lines under the shared cue order.
        dialog = lib.one(Slot[ids.zone("M_DIALOG_SENSOR")], "dialog sensor"),
        music = lib.one(Slot[ids.zone("M_MUSIC_SENSOR")], "music sensor"),
        chest = slot("PF_REWARD_CHEST_TIER0_OBJECT"),
        rally = rally.bind(mission, ids.rally_key, ids.rally_volume),
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
        navpoint = lib.one(Slot[ids.navpoint], "location point"),
        directive = directive,
        incoming = incoming,
    }
end

return site
