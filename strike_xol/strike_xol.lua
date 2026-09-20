-- Will of the Thousands (strike_xol) -- single-file mission script.
--
-- This was ten files under scripts/strike_xol/. It is one file now because that is how the
-- other released strikes are shipped. Nothing about the behaviour changed in the merge: each
-- former module is wrapped verbatim in an immediately-invoked function below, in dependency
-- order, and the only edits were removing the long explanatory comment blocks (the original
-- carried ~95 KB of them, and the runtime caps a main script at 128 KiB).
--
--   combat_ai  encounter  roster  music  support  boss  probe  triggers  route  wipe  entry
--
-- ---------------------------------------------------------------------------------------
-- WHAT WORKS, AND THE ONE THING THAT DOES NOT
-- ---------------------------------------------------------------------------------------
-- The mission plays start to finish. The open problem is Xol himself: he can be made to
-- EXIST, but nothing found so far can make him act or move. If you are picking this up, the
-- notes below are the dead ends, so you do not have to re-walk them.
--
-- WHAT IS ESTABLISHED, with evidence:
--
--  * There are two authored Xols. SQ_XOL_80F76A45 belongs to package 80f76a45 = bubble 11,
--    and SCENE_XOL_SURPRISE -- the authored bridge burst -- is symbol/.../000b/... in that
--    same bubble. The fireteam holds region 96 = bubble 12 on the bridge (measured at
--    runtime, xol.bridge.region). A scene cannot place a cast into a package the client does
--    not hold, so that content is unreachable. The bridge burst as authored cannot play.
--
--  * SQ_XOL_80F76B80 (bubble 12) is the one that can be reached. squad:place{} does create
--    him -- it is the only thing that ever has -- but his squad has exactly one authored
--    anchor, at (-243.7, -945.0, 3.6), while the arena volume is x -502..-405, y -770..-675,
--    z 22.8..37.8. So he spawns ~260 units away and ~19 below the floor. That is also the
--    long-standing "he is under the map" observation.
--
--  * Moving him with atoms is closed. snap_to / face / move_to all run atom_point_parameter,
--    which calls resolveActorAbilityTarget and raises "atom target has no such authored point
--    parameter" unless the target slot is in the catalog's actor_ability_targets with that
--    point index. All eighteen type-48 point slots in the arena package plus XOL_CAMERA_DUMMY
--    were swept: none is legal (xol.snap = "no legal point target in 19").
--
--  * play_actor_action is now a one-atom run_atoms whose ability goes through
--    actor_ability::resolve, which accepts only a group/request pair the exact actor owns.
--    The pre-migration call used group = FNV-1("") = 0x811C9DC5 and action =
--    FNV-1("xol_summon") = 0x0D4730FC. Neither hash appears anywhere in this scenario's
--    catalog, so that call was never addressing anything and cannot be revived.
--
--  * mission.TaskGroup lists 86 objectives with authored task groups. XOL_OBJECTIVE is not
--    one of them (XOL_ATTACK_ADDS_OBJECTIVE is), so the combat director has no task targets
--    for him and no assignment can path him.
--
-- WHAT IS STILL OPEN, and where I would look next:
--
--  * His eighteen authored abilities (mission.ActorAbility.SQ_XOL_XOL, all in group
--    0xAFB11A12). A bare ability takes no target, so it escapes the point-parameter check
--    that closed the movement atoms. The heartbeat fires one per tick from the bridge onward
--    and records each result in xol.ab.<n>; that sweep is the live experiment.
--
--  * The fight is authored as SCENES, in bubble 12, and their names describe it exactly:
--    ARRIVE_1..4 / ARRIVE_4_TOWER / ARRIVE_FINALE, BREACH_1_3 / 1_4 / 2_3 / 2_4 / 3_1 / 3_2 /
--    4_1 / 4_2 (eight transitions between four positions), BREACH_TELL_1..5, BREACH_FINALE,
--    FLOOR_RUPTURE_*, and DEBUG_SET_HEALTH_THRESHOLD_PHASE1 / PHASE2 / FINALE. If he cannot
--    be puppeted, building the fight out of those scenes plus the add waves is probably the
--    real answer, and the sequencing is already named in the data.
--
-- ---------------------------------------------------------------------------------------
-- THINGS THAT WILL LOOK WRONG BUT ARE DELIBERATE
-- ---------------------------------------------------------------------------------------
--  * Interaction rows are sent as {active = true} and never {used = true}. Per
--    interactable_object_auth.h, `used` sends the row already latched at revision one -- "the
--    state after a first use" -- so used = true hands the player a button that is already
--    spent. Every console in the strike was invisible because of this.
--
--  * Unlocking a door is not opening it. Every gate here is authored open and held shut by
--    locking, so `drive` touches lock and power only. POSITION_DRIVEN is the short list of
--    exceptions (the airlock, the Zavala proxy, the cave barrier, the core exit).
--
--  * There are no completion timers anywhere. No charge fallback, no spear lifetime, no hold
--    release. A beat that was skipped is not done; the fireteam walks back and does it.
--
--  * Nothing is performed on the way out of a beat. `bail` is gone for the same reason.
--
--  * A Ghost scan is two reports -- active with progress > 0, then active == false. Arming
--    the link emits a report of its own, and reading that as a completed scan is what used to
--    spawn the control room's first wave off the arming call.

-- ============================================================================
-- combat_ai.lua
-- Native task-group selection. XOL_OBJECTIVE has no authored groups, so for the
-- boss this reports that fact and does nothing else.
-- ============================================================================
local MOD_combat_ai = (function()
local AI = {}

function AI.assign(context, sensor, objective, group, options)
    options = options or {}
    return context:slot(sensor):assign_combat_objective{
        objective = context:slot(objective),
        task_group = group,
        reconsider = options.reconsider or false,
        reserved = options.reserved,
        refresh_player_awareness = options.refresh_awareness or false,
    }
end

function AI.groups(mission, objective_key)
    return mission.TaskGroup and mission.TaskGroup[objective_key]
end

function AI.update(context, state, sensor, objective, groups, event)
    if groups == nil or #groups == 0 then return end
    local slot = context:slot(objective)
    local current, assigned = event:task_group{objective = slot}
    if not assigned then return end
    local best, bestCost = nil, nil
    for index = 1, #groups do
        local cost, known = event:task_cost{group = groups[index]}
        if known and cost ~= nil and (bestCost == nil or cost < bestCost) then
            best, bestCost = groups[index], cost
        end
    end
    if best == nil then return end
    if current ~= nil and current == best then return end
    AI.assign(context, sensor, objective, best)
    context:set_variable("xol.ai.assigns", (state:variable("xol.ai.assigns") or 0) + 1)
    context:set_variable("xol.ai.last", "cost " .. tostring(bestCost))
end

return AI
end)()

-- ============================================================================
-- encounter.lua
-- One encounter's placement and clear accounting. `actor_owned` squads are tracked
-- but never placed by the encounter itself.
-- ============================================================================
local MOD_encounter = (function()
local AI = MOD_combat_ai
local Encounter = {}
Encounter.__index = Encounter

function Encounter.new(tag, squads, cleared, reserved)
    assert(#squads > 0 and #squads <= 30, "encounter needs 1..30 squads")
    return setmetatable({tag = tag, squads = squads, cleared = cleared,
                         full = (1 << #squads) - 1, reserved = reserved or false}, Encounter)
end

function Encounter:phase(state)
    return state:variable(self.tag .. ".phase") or 0
end

function Encounter:enter(context, state)
    if self:phase(state) ~= 0 then
        return false
    end
    local handles = {}
    for index, squad in ipairs(self.squads) do
        handles[index] = context:squad(squad.id)
        local count = 0
        for _, value in ipairs(handles[index].default_counts) do
            assert(value >= 0, "squad has unresolved authored counts: " .. squad.name)
            count = count + value
        end
        assert(count > 0, "encounter squad has no authored members: " .. squad.name)
    end
    context:set_variable(self.tag .. ".seen", 0)
    context:set_variable(self.tag .. ".alive", 0)
    context:set_variable(self.tag .. ".phase", 1)
    for index, handle in ipairs(handles) do
        local squad = self.squads[index]
        if not squad.actor_owned then
            handle:place{mode = self.reserved and context.sdk.squad_modes.reserve
                             or context.sdk.squad_modes.replace}
        end
        if squad.objective then
            AI.assign(context, squad.sensor, squad.objective, nil,
                      {reserved = self.reserved, reconsider = true})
        end
    end
    return true
end

function Encounter:on_squad_state(context, state, event)
    if self:phase(state) ~= 1 then
        return
    end
    local bit, matched
    for index, squad in ipairs(self.squads) do
        local slot = context:slot(squad.sensor)
        if event.registry_key == slot.registry_key and event.slot_type == slot.slot_type
            and event.slot_index == slot.slot_index then
            bit = 1 << (index - 1)
            matched = squad
            if squad.objective and squad.groups then
                AI.update(context, state, squad.sensor, squad.objective, squad.groups, event)
            end
            break
        end
    end
    if bit == nil or event.alive_count == nil then
        return
    end
    local seen = state:variable(self.tag .. ".seen") or 0
    local alive = state:variable(self.tag .. ".alive") or 0
    if event.alive_count > 0 or (event.previous_alive_count or 0) > 0 then
        seen = seen | bit
    end
    local accounted = event.slot_counts ~= nil
    for index, requested in ipairs(context:squad(matched.id).default_counts) do
        if not event.slot_counts or (event.slot_counts[index] or -1) < requested then
            accounted = false
        end
    end
    if event.alive_count > 0 or not accounted then
        alive = alive | bit
    else
        alive = alive & ~bit
    end
    context:set_variable(self.tag .. ".seen", seen)
    context:set_variable(self.tag .. ".alive", alive)
    if seen == self.full and alive == 0 then
        context:set_variable(self.tag .. ".phase", 2)
        self:retire(context)
        if self.cleared then self.cleared(context, state) end
    end
end

function Encounter:abandon(context, state)
    if self:phase(state) ~= 1 then return false end
    self:retire(context)
    context:set_variable(self.tag .. ".phase", 3)
    return true
end

function Encounter:replace(context)
    for index, squad in ipairs(self.squads) do
        if not squad.actor_owned then
            context:squad(squad.id):place{mode = self.reserved and context.sdk.squad_modes.reserve
                                              or context.sdk.squad_modes.replace}
        end
        if squad.objective then
            AI.assign(context, squad.sensor, squad.objective, nil,
                      {reserved = self.reserved, reconsider = true})
        end
    end
end

function Encounter:retire(context)
    for _, squad in ipairs(self.squads) do
        if not squad.actor_owned then
            local handle = context:squad(squad.id)
            local counts = handle:counts()
            for index = 1, #handle.default_counts do counts:set(index, 0) end
            handle:place{counts = counts,
                mode = self.reserved and context.sdk.squad_modes.reserve
                    or context.sdk.squad_modes.replace}
        end
    end
end

function Encounter:reset(context)
    self:retire(context)
    context:clear_variable(self.tag .. ".phase")
    context:clear_variable(self.tag .. ".seen")
    context:clear_variable(self.tag .. ".alive")
end

return Encounter
end)()

-- ============================================================================
-- roster.lua
-- Every authored squad the route places, grouped by beat.
-- ============================================================================
local MOD_roster = (function()
return {
    {name = "control_initial", objective = "CONTROL_MAIN_OBJECTIVE", squads = {
        "CONTROL_INITIAL_KNIGHT_SQUAD", "CONTROL_INITIAL_ACOLYTE_SQUAD",
        "CONTROL_INITIAL_ACOLYTE_SQUAD_1"}},
    {name = "control_wave1", objective = "CONTROL_MAIN_OBJECTIVE", squads = {
        "WAVE1_SUPPORT_SQUAD_1", "WAVE1_SUPPORT_SQUAD_2"}},
    {name = "control_wave2", objective = "CONTROL_MAIN_OBJECTIVE", squads = {
        "WAVE2_RIGHT_KNIGHT_SQUAD_1", "WAVE2_RIGHT_SUPPORT_SQUAD_1",
        "WAVE2_RIGHT_SUPPORT_SQUAD_2"}},
    {name = "control_wave3", objective = "CONTROL_MAIN_OBJECTIVE", squads = {
        "WAVE3_RIGHT_KNIGHT_SQUAD", "WAVE3_LEFT_KNIGHT_SQUAD",
        "WAVE3_MID_SUPPORT_SQUAD_1", "WAVE3_MID_SUPPORT_SQUAD_2", "WAVE3_MID_SUPPORT_SQUAD_3"}},
    {name = "control_wizard", objective = "CONTROL_MAIN_OBJECTIVE", squads = {
        "WAVE3_MID_WIZARD_SQUAD"}},
    {name = "cooling", objective = "COOLING_MAIN_OBJECTIVE", squads = {
        "COOLING_ANCHOR_SQUAD", "COOLING_ACOLYTE_SQUAD_2", "COOLING_THRALL_SQUAD_1"}},

    {name = "energy3_entry", objective = "MAIN_OBJECTIVE_80F762FD", squads = {
        "TROOPER_SQUAD_ENTRANCE", "TROOPER_SQUAD_FRONT", "THRALL_SQUAD_FRONT"}},
    {name = "energy3_back", objective = "MAIN_OBJECTIVE_80F762FD", squads = {
        "ANCHOR_KNIGHT_SQUAD_BACK", "TROOPER_SQUAD_BACK", "TROOPER_SQUAD_BACK_RIGHT",
        "TROOPER_SQUAD_BACK_1", "TROOPER_SQUAD_BACK_2"}},
    {name = "energy3_thralls", objective = "MAIN_OBJECTIVE_80F762FD", squads = {
        "THRALL_SQUAD_A", "THRALL_SQUAD_B", "THRALL_SQUAD_C"}},
    {name = "energy3_shrieker", objective = "MAIN_OBJECTIVE_80F762FD", squads = {
        "ENERGY3_SHRIEKER_SQUAD"}},

    {name = "arena_wave1", objective = "MAIN_OBJECTIVE_80F7619E", squads = {
        "INTRO_ACOLYTE_BOTTOM_SQUAD", "INTRO_ACOLYTE_TOP_SQUAD",
        "WAVE1_ACOLYTE_SQUAD_A", "WAVE1_ACOLYTE_SQUAD_B", "WAVE1_KNIGHT_SQUAD_A",
        "WAVE1_ACOLYTE_TOP_SQUAD_A", "WAVE1_ACOLYTE_TOP_SQUAD_B"}},
    {name = "arena_wave2", objective = "MAIN_OBJECTIVE_80F7619E", squads = {
        "WAVE2_CRUSADER_SQUAD_A", "WAVE2_ACOLYTE_SQUAD_A", "WAVE2_ACOLYTE_SQUAD_B",
        "WAVE2_ACOLYTE_TOP_SQUAD_A", "WAVE2_ACOLYTE_TOP_SQUAD_B"}},
    {name = "arena_wave3", objective = "MAIN_OBJECTIVE_80F7619E", squads = {
        "WAVE3_CRUSADER_SQUAD_A", "WAVE3_THRALL_SQUAD_A"}},
    {name = "arena_wizard", objective = "MAIN_OBJECTIVE_80F7619E", squads = {
        "MAIN_ANCHOR_WIZARD_SQUAD"}},
    {name = "arena_ogre", objective = "MAIN_OBJECTIVE_80F7619E", squads = {
        "MAIN_ANCHOR_OGRE_SQUAD"}},

    {name = "postcore", objective = "POSTCORE_MAIN_OBJECTIVE", squads = {
        "POSTCORE_KNIGHT_SQUAD_A", "POSTCORE_KNIGHT_SQUAD_B", "POSTCORE_THRALL_SQUAD",
        "POSTCORE_TROOPER_SQUAD_A", "POSTCORE_TROOPER_SQUAD_B"}},

    {name = "pit_front", objective = "ENTRANCE_MAIN_OBJECTIVE", squads = {
        "FRONT_ANCHOR_KNIGHT_SQUAD", "FRONT_ACOLYTE_SQUAD_A", "FRONT_ACOLYTE_SQUAD_B"}},
    {name = "pit_back", objective = "ENTRANCE_MAIN_OBJECTIVE", squads = {
        "BACK_ANCHOR_KNIGHT_SQUAD", "BACK_ANCHOR_CRUSADER_SQUAD", "BACK_ANCHOR_ACOLYTE_SQUAD_A",
        "BACK_ANCHOR_ACOLYTE_SQUAD_B", "BACK_ACOLYTE_SQUAD_A", "BACK_THRALL_SQUAD_1",
        "BACK_THRALL_SQUAD_2"}},
    {name = "pit_shrieker", objective = "ENTRANCE_MAIN_OBJECTIVE", squads = {
        "ENTRANCE_SHRIEKER_SQUAD"}},

    {name = "cave_snipers", objective = "MAIN_OBJECTIVE_80F76532", squads = {
        "SNIPER_SQUAD_1", "SNIPER_SQUAD_2", "SNIPER_SQUAD_RIGHT"}},
    {name = "cave_main", objective = "MAIN_OBJECTIVE_80F76532", squads = {
        "ACOLYTE_SQUAD", "ACOLYTE_FRONT_SQUAD", "ACOLYTE_FRONT_SQUAD_1"}},
    {name = "cave_knights", objective = "MAIN_OBJECTIVE_80F76532", squads = {"KNIGHT_SQUAD"}},

    {name = "airlock_hive", squads = {"SQ_HIVE1", "SQ_HIVE2", "SQ_HIVE3"}},
    {name = "airlock_zavala", squads = {"SQ_ZAVALA"}},

    {name = "xol", actor_owned = true, objective = "XOL_OBJECTIVE", squads = {"SQ_XOL_80F76B80"}},

    {name = "boss_adds_left", objective = "XOL_ATTACK_ADDS_OBJECTIVE", squads = {
        "SQ_LIST_THRALL_0", "SQ_LIST_TROOPER_0", "SQ_LIST_CRUSADER_0"}},
    {name = "boss_adds_right", objective = "XOL_ATTACK_ADDS_OBJECTIVE", squads = {
        "SQ_LIST_THRALL_1", "SQ_LIST_TROOPER_1", "SQ_LIST_BOOMER_0"}},
    {name = "boss_adds_final", objective = "XOL_ATTACK_ADDS_OBJECTIVE", squads = {
        "SQ_LIST_THRALL_2", "SQ_LIST_TROOPER_2", "SQ_LIST_EXPLODER_0"}},
}
end)()

-- ============================================================================
-- music.lua
-- Stage-to-music-section mapping.
-- ============================================================================
local MOD_music = (function()
local ENABLED = false

local SECTIONS = {
    [0] = 0, -- arrival
    [1] = 1, -- approach to the Neural Node
    [2] = 1, -- inhibitor one
    [3] = 2, -- control room
    [4] = 2, -- inhibitor two
    [5] = 3, -- energy three
    [6] = 3, -- inhibitor three
    [7] = 4, -- core arena
    [8] = 4, -- Sulhava
    [9] = 5, -- Thul
    [10] = 5, -- forge
    [11] = 6, -- post-core
    [12] = 6, -- pit
    [13] = 7, -- mini-heatsink
    [14] = 7, -- spire run
    [15] = 8, -- Xol arena
    [16] = 8, -- Xol defeated
}

return function(mission)
    local M = {}

    function M.update(c, s)
        if not ENABLED then return end
        local section = SECTIONS[s:variable("xol.stage") or 0]
        if section == nil or s:variable("xol.music") == section then return end
        c:slot(assert(mission.Slot.M_MUSIC_SENSOR, "strike_xol: missing music sensor"))
            :set_music_section{section = math.max(section, 0), enabled = section >= 0}
        c:set_variable("xol.music", section)
    end

    return M
end
end)()

-- ============================================================================
-- support.lua
-- Transactional helpers bound to the generated SDK module: slots, devices, scenes,
-- interaction rows, actor abilities. The Xol entrance lives here too.
-- ============================================================================
local MOD_support = (function()
local Encounter = MOD_encounter
local ROSTER = MOD_roster
local MUSIC = MOD_music

local DIRECTIVES = {
    investigate        = "OVERLOAD_THE_NEURAL_NET_EED0DA1A", -- Investigate the Neural Node.
    secure_control     = "OVERLOAD_THE_NEURAL_NET_F72EB78D", -- Secure the control room.
    disable_inhibitor  = "OVERLOAD_THE_NEURAL_NET",          -- Disable the inhibitor.
    disable_inhibitor2 = "OVERLOAD_THE_NEURAL_NET_7BEFA791", -- Disable the inhibitor.
    overload_control   = "OVERLOAD_THE_NEURAL_NET_9609340A", -- Overload the control room inhibitor.
    initiate_overload  = "OVERLOAD_THE_NEURAL_NET_FD43FDAC", -- Initiate the inhibitor overload.
    next_inhibitor     = "OVERLOAD_THE_NEURAL_NET_B30CAAEC", -- Find the next inhibitor.
    next_inhibitor2    = "OVERLOAD_THE_NEURAL_NET_EA76365C", -- Find the next inhibitor.
    get_to_core        = "FORGE_THE_ENHANCED_VALKYRIE_368954F7", -- Get to the core.
    sulhava            = "FORGE_THE_ENHANCED_VALKYRIE_9C79EB17", -- Eliminate Sulhava...
    thul               = "FORGE_THE_ENHANCED_VALKYRIE_9AD10432", -- Eliminate Thul the Monstrous.
    forge              = "FORGE_THE_ENHANCED_VALKYRIE",          -- Use the overcharged core...
    sealed_door        = "DEFEND_RASPUTIN_C6B045F8",         -- Get through the sealed door.
    get_to_rasputin    = "DEFEND_RASPUTIN",                  -- Get to Rasputin before Xol...
    protect_rasputin   = "PROTECT_RASPUTIN",                 -- Stop Xol from destroying Rasputin.
    defeat_xol         = "THE_HIVE_GOD",                     -- Defeat Xol.
}

return function(mission, on_clear)
    local api = {groups = {}, mission = mission}
    local music = MUSIC(mission)

    local function slot_id(name)
        return assert(mission.Slot[name], "strike_xol: missing SDK slot " .. name)
    end

    local function task_groups(objective)
        local table_for = mission.TaskGroup and mission.TaskGroup[objective]
        if table_for == nil then return nil end
        local rows = {}
        for index = 0, 23 do
            local row = table_for["GROUP_" .. index]
            if row == nil then break end
            rows[#rows + 1] = row
        end
        return #rows > 0 and rows or nil
    end

    for _, row in ipairs(ROSTER) do
        local squads = {}
        for index, name in ipairs(row.squads) do  -- luacheck: ignore index
            squads[#squads + 1] = {
                name = name,
                id = assert(mission.Squad[name], "strike_xol: missing SDK squad " .. name),
                sensor = slot_id(name),
                objective = row.objective and slot_id(row.objective) or nil,
                groups = row.objective and task_groups(row.objective) or nil,
                actor_owned = row.actor_owned,
            }
        end
        api.groups[row.name] = Encounter.new("xol.g." .. row.name, squads,
            function(c, s) on_clear(c, s, row.name) end)
    end

    function api.slot(c, name) return c:slot(slot_id(name)) end

    function api.matches(c, event, name)
        local slot = api.slot(c, name)
        return event.registry_key == slot.registry_key and event.slot_type == slot.slot_type
            and event.slot_index == slot.slot_index
    end

    function api.matches_any(c, event, names)
        for _, name in ipairs(names) do
            if api.matches(c, event, name) then return true end
        end
        return false
    end

    function api.group(name)
        return assert(api.groups[name], "strike_xol: unknown encounter group " .. name)
    end

    function api.spawn(c, s, names)
        for _, name in ipairs(names) do api.group(name):enter(c, s) end
    end

    function api.clear(s, names)
        for _, name in ipairs(names) do
            if api.group(name):phase(s) < 2 then return false end
        end
        return true
    end

    function api.replace(c, names)
        for _, name in ipairs(names) do api.group(name):replace(c) end
    end

    function api.abandon(c, s, names)
        for _, name in ipairs(names) do api.group(name):abandon(c, s) end
    end

    function api.combat(s, names)
        for _, name in ipairs(names) do
            if api.group(name):phase(s) == 1 then return true end
        end
        return false
    end

    function api.reset(c, names)
        for _, name in ipairs(names) do api.group(name):reset(c) end
    end

    function api.squad(c, s, event)
        for _, row in ipairs(ROSTER) do api.groups[row.name]:on_squad_state(c, s, event) end
    end

    function api.device(c, name, open, snap)
        api.slot(c, name):transition{
            transition = open and c.sdk.device_transitions.open or c.sdk.device_transitions.close,
            snap = snap or false}
    end

    function api.lane(c, name, transition, snap)
        api.slot(c, name):transition{transition = c.sdk.device_transitions[transition],
                                     snap = snap or false}
    end

    function api.enable_device(c, name)
        api.lane(c, name, "unlock"); api.lane(c, name, "power_on")
    end

    function api.devices(c, names, open, snap)
        for _, name in ipairs(names) do api.device(c, name, open, snap) end
    end

    function api.objects(c, names, active)
        for _, name in ipairs(names) do api.slot(c, name):set_object_active{active = active} end
    end

    local JAVELINS = {
        heatsink = false, -- the three inhibitor rooms; every charge there can be shot instead
        arena    = false, -- arena a / b -- a pickup here dropped the run to orbit
        arena_final = true, -- ...but the final one does hand out a spear when the room is won
        core     = true,  -- o_core_javelin_spawner, the spear carried into the core
        postcore = true,  -- the spear the explosion leaves for the corridor beyond the core
        boss     = true,  -- the arena's three spears: the fight has no other damage mechanic
    }

    api.task_groups = task_groups

    function api.javelin(c, group, names)
        local on = JAVELINS[group]
        assert(on ~= nil, "strike_xol: unknown javelin group " .. tostring(group))
        pcall(function() api.objects(c, names, on) end)
        return on
    end

    function api.sequence(c, name) api.slot(c, name):play_sequence{} end

    local ATOM_FIELDS = {"target", "value", "enabled", "seconds", "channel", "ability",
        "quantized"}

    function api.atoms(c, name, atoms, spawn)
        local kinds = c.sdk and c.sdk.atom_kinds
        local built = {}
        for index = 1, #atoms do
            local atom, copy = atoms[index], {}
            local kind = atom.kind
            if type(kind) == "string" then
                assert(kinds ~= nil, "strike_xol: context.sdk.atom_kinds is missing")
                kind = kinds[kind]
                assert(kind ~= nil, "strike_xol: unknown atom kind " .. tostring(atom.kind))
            end
            copy.kind = kind
            for _, field in ipairs(ATOM_FIELDS) do copy[field] = atom[field] end
            built[index] = copy
        end
        local key = api.slot(c, name):run_atoms{spawn = spawn and true or false, atoms = built}
        return key ~= nil and key.value or nil
    end

    function api.ability(c, name, group, key, target, spawn)
        local abilities = mission.ActorAbility and mission.ActorAbility[name]
        local row = abilities and abilities[group] and abilities[group][key]
        if row == nil then return false, "no such authored ability", nil end
        local sent
        local ok, err = pcall(function()
            sent = api.slot(c, name):play_actor_action{
                ability = row, target = target and api.slot(c, target) or nil,
                spawn = spawn and true or false}
        end)
        return ok, err, sent ~= nil and sent.value or nil
    end

    local SUMMON = {group = nil, key = nil}   -- e.g. {group = "GROUP_AFB11A12", key = "KEY_..."}

    function api.summon(c, name)
        local ok, err, key
        if SUMMON.group ~= nil and SUMMON.key ~= nil then
            ok, err, key = api.ability(c, name, SUMMON.group, SUMMON.key, nil, true)
        else
            ok, err = pcall(function()
                key = api.atoms(c, name, {{kind = "trivial"}}, true)
            end)
        end
        c:set_variable("xol.summon", ok and "sent -- awaiting outcome"
                                        or ("RAISED " .. tostring(err):sub(-42)))
        if ok and key ~= nil then c:set_variable("xol.summon.key", key) end
        return ok
    end

    local SCENE_SHAPES = {"context"}
    local scene_reported = {}

    local function try_scene(c, name, shape)
        if shape == "context" then
            local id = mission.Scene[name]
            if id == nil then return false, "no Scene id" end
            return pcall(function() c:scene(id):activate{} end)
        elseif shape == "cinematic" then
            return pcall(function() api.slot(c, name):set_cinematic_active{active = true} end)
        elseif shape == "sequence" then
            return pcall(function() api.slot(c, name):play_sequence{} end)
        else
            return pcall(function() api.slot(c, name):set_object_active{active = true} end)
        end
    end

    function api.scene(c, name, spawn)
        local notes = ""
        if spawn then
            local id = mission.Scene[name]
            local ok, err
            if id == nil then
                ok, err = false, "no Scene id"
            else
                ok, err = pcall(function() c:scene(id):activate{spawn = true} end)
            end
            if ok then
                c:set_variable("xol.scene." .. name, "activated with cast")
                scene_reported[name] = true
                return true
            end
            notes = "cast:" .. tostring(err):sub(-28) .. " "
        end
        for _, shape in ipairs(SCENE_SHAPES) do
            local ok, err = try_scene(c, name, shape)
            if ok then
                notes = notes .. shape .. ":ok "
            else
                notes = notes .. shape .. ":" .. tostring(err):sub(1, 48) .. " "
            end
        end
        if not scene_reported[name] then
            scene_reported[name] = true
            c:set_variable("xol.scene." .. name, notes:sub(1, 60))
        end
        return true
    end

    function api.place_xol(c)
        local ok, err, key
        ok, err = pcall(function()
            api.slot(c, "SQ_XOL_80F76B80"):assign_combat_objective{
                objective = api.slot(c, "XOL_OBJECTIVE")}
        end)
        c:set_variable("xol.place.obj", ok and "assigned" or ("RAISED " .. tostring(err):sub(-40)))
        ok, err = pcall(function()
            key = c:squad(assert(mission.Squad.SQ_XOL_80F76B80,
                                 "strike_xol: no SQ_XOL_80F76B80 squad")):place{}
        end)
        c:set_variable("xol.place", ok and "sent" or ("RAISED " .. tostring(err):sub(-42)))
        if ok and key ~= nil then c:set_variable("xol.k.place", key.value) end
        return ok
    end

    local SNAP_TARGETS = {
        "FLOOR_RUPTURE_5_POINT",
        "SLOT_005F_80F76B80", "SLOT_0060_80F76B80", "SLOT_0061_80F76B80", "SLOT_0062_80F76B80",
        "SLOT_0065_80F76B80", "SLOT_0066_80F76B80", "SLOT_0069_80F76B80", "SLOT_006A_80F76B80",
        "SLOT_006B_80F76B80", "SLOT_0070_80F76B80", "SLOT_0075_80F76B80", "SLOT_007B_80F76B80",
        "SLOT_0082_80F76B80", "SLOT_0083_80F76B80", "SLOT_0084_80F76B80", "SLOT_0085_80F76B80",
        "SLOT_0086_80F76B80",
        "XOL_CAMERA_DUMMY",
    }

    local ABILITY_GROUP = "GROUP_AFB11A12"
    local ABILITIES = {
        "KEY_14F63B80", "KEY_3204711B", "KEY_4FA22660", "KEY_688565B6", "KEY_75A98763",
        "KEY_9173442D", "KEY_9173442E", "KEY_96AAF7B6", "KEY_981397A0", "KEY_9C744932",
        "KEY_B44216E6", "KEY_B473D93A", "KEY_D1649E61", "KEY_D1649E66", "KEY_D166DCDD",
        "KEY_D166DCDE", "KEY_D16B5A29", "KEY_D16B5A2E",
    }

    function api.ability_step(c, s)
        local at = (s:variable("xol.ab.at") or 0) + 1
        if at > #ABILITIES then
            if s:variable("xol.ab") == nil then c:set_variable("xol.ab", "list exhausted") end
            return false
        end
        c:set_variable("xol.ab.at", at)
        local key = ABILITIES[at]
        c:set_variable("xol.ab.now", at .. "/" .. #ABILITIES .. " " .. key)
        local ok, err, sent = api.ability(c, "SQ_XOL_XOL", ABILITY_GROUP, key, nil, false)
        if not ok then
            c:set_variable("xol.ab." .. at, "RAISED " .. tostring(err):sub(-42))
        elseif sent ~= nil then
            c:set_variable("xol.k.ab", sent)
            c:set_variable("xol.ab.key", at)
            c:set_variable("xol.ab." .. at, "sent")
        else
            c:set_variable("xol.ab." .. at, "sent -- no key")
        end
        return true
    end

    function api.snap_xol(c)
        local first_error
        for index, name in ipairs(SNAP_TARGETS) do
            local key
            local ok, err = pcall(function()
                key = api.atoms(c, "SQ_XOL_XOL", {
                    {kind = "snap_to", target = api.slot(c, name), value = 0},
                    {kind = "sleep", seconds = 30.0},
                }, false)
            end)
            if ok then
                c:set_variable("xol.snap", "sent on " .. name)
                c:set_variable("xol.snap.at", index)
                if key ~= nil then c:set_variable("xol.k.snap", key) end
                return true
            end
            if first_error == nil then first_error = tostring(err) end
        end
        c:set_variable("xol.snap", "no legal point target in " .. #SNAP_TARGETS)
        c:set_variable("xol.snap.err", tostring(first_error):sub(-50))
        return false
    end

    function api.bind(c, name)
        local ok, err = pcall(function() api.slot(c, name):bind_combatant_to_squad() end)
        c:set_variable("xol.bind", ok and "armed" or ("RAISED " .. tostring(err):sub(-40)))
        return ok
    end

    function api.arm(c, names)
        local failed = 0
        for _, name in ipairs(names) do
            local ok = pcall(function() api.slot(c, name):fire_trigger{} end)
            if not ok then failed = failed + 1 end
        end
        if failed > 0 then c:set_variable("xol.arm.failed", failed) end
    end

    function api.cue(c, s, index)
        local key = "xol.cue." .. index
        if s:variable(key) then return end
        c:set_variable(key, true)
        api.slot(c, "M_DIALOG_SENSOR"):play_dialogue_cue{
            cue = assert(mission.DialogueCue.M_DIALOG_SENSOR["CUE_" .. index],
                         "strike_xol: missing dialogue cue " .. index)}
    end

    function api.darkness(c, s, enabled)
        if s:variable("xol.darkness") == enabled then return end
        c:set_variable("xol.darkness", enabled)
        api.slot(c, "HARD_WIPE_GLOBALS"):set_darkness_zone{enabled = enabled}
    end

    function api.directive(c, s, key, marker, audience)
        local element = assert(DIRECTIVES[key], "strike_xol: unknown directive " .. key)
        local binding = assert(mission.Directive[element],
                               "strike_xol: missing authored directive " .. element)
        local signature = key .. ":" .. (marker or "") .. ":" .. (audience or "")
        if s:variable("xol.guidance") == signature then return end
        local listener = audience and api.slot(c, audience) or nil
        api.slot(c, "M_DIRECTIVE_SENSOR"):set_directive{
            directive = binding, audience = listener,
            navpoint = marker and api.slot(c, marker) or nil}
        c:set_variable("xol.guidance", signature)
    end

    function api.music(c, s) music.update(c, s) end

    function api.arrival(c, s)
        if s:variable("xol.checkpoint.stage") then return end
        local region, hash = c.region_index, c.spawn_set_hash
        if region == nil or hash == nil or hash == 0 then return end
        if s:variable("xol.spawn.hash") == hash and s:variable("xol.spawn.region") == region then
            return
        end
        c:set_variable("xol.spawn.region", region)
        c:set_variable("xol.spawn.hash", hash)
        c:set_variable("xol.spawn.fallback.region", region)
        c:set_variable("xol.spawn.fallback.hash", hash)
    end

    function api.checkpoint(c, s, stage, region, hash)
        if (s:variable("xol.checkpoint.stage") or 0) >= stage then return end
        c:set_variable("xol.checkpoint.stage", stage)
        if region and hash then
            c:set_variable("xol.spawn.region", region)
            c:set_variable("xol.spawn.hash", hash)
        end
    end

    return api
end
end)()

-- ============================================================================
-- boss.lua
-- The Xol arena. Currently a diagnostic ladder rather than a fight -- see the notes
-- in the ARENA section at the bottom of this file.
-- ============================================================================
local MOD_boss = (function()
return function(mission, a)
    local AI = MOD_combat_ai
    local B = {}
    local LADDER_TIMER = "xol.boss.ladder"
    local DWELL = 12000
    local FIRST = 8000
    local TARGET = "XOL_CAMERA_DUMMY"

    local function status(c, value) c:set_variable("xol.boss.status", value) end

    local GROUP = "GROUP_AFB11A12"
    local ABILITIES = {
        "KEY_14F63B80", "KEY_3204711B", "KEY_4FA22660", "KEY_688565B6", "KEY_75A98763",
        "KEY_9173442D", "KEY_9173442E", "KEY_96AAF7B6", "KEY_981397A0", "KEY_9C744932",
        "KEY_B44216E6", "KEY_B473D93A", "KEY_D1649E61", "KEY_D1649E66", "KEY_D166DCDD",
        "KEY_D166DCDE", "KEY_D16B5A29", "KEY_D16B5A2E",
    }

    local CHANNELS = {
        {0xED8750E2, "boss_phase = 1", 1},
        {0xED8750E2, "boss_phase = 2", 2},
        {0xED8750E2, "boss_phase = 3", 3},
        {0x6D56A3BE, "surface", 1},
        {0x67C5733B, "submerge", 1},
        {0x696B7FEA, "emerge", 1},
        {0x15FACB18, "burrow", 1},
        {0xF49FA4B2, "xol_phase", 1},
        {0x52AB7C84, "xol_state", 1},
    }

    local POINT = 0

    local STEPS = {}
    local function step(label, send) STEPS[#STEPS + 1] = {label, send} end

    for index = 1, #ABILITIES do
        local key = ABILITIES[index]
        step("A" .. index .. "/" .. #ABILITIES .. " ability " .. key, function(c)
            local ok, err, sent = a.ability(c, "SQ_XOL_XOL", GROUP, key, nil, false)
            if not ok then error(tostring(err), 0) end
            return sent
        end)
    end

    step("M1 FACE the camera dummy -- does he turn?", function(c)
        return a.atoms(c, "SQ_XOL_XOL", {
            {kind = "face", target = a.slot(c, TARGET), value = POINT},
            {kind = "sleep", seconds = 30.0},
        }, false)
    end)
    step("M2 MOVE_TO the camera dummy -- does he travel?", function(c)
        return a.atoms(c, "SQ_XOL_XOL", {
            {kind = "move_to", target = a.slot(c, TARGET), value = POINT, enabled = true},
            {kind = "sleep", seconds = 30.0},
        }, false)
    end)
    step("M3 SNAP_TO the camera dummy -- does he relocate?", function(c)
        return a.atoms(c, "SQ_XOL_XOL", {
            {kind = "snap_to", target = a.slot(c, TARGET), value = POINT},
            {kind = "sleep", seconds = 30.0},
        }, false)
    end)

    for index = 1, #CHANNELS do
        local row = CHANNELS[index]
        step("C" .. index .. " set_channel " .. row[2], function(c)
            return a.atoms(c, "SQ_XOL_XOL", {
                {kind = "set_channel", channel = row[1], value = row[3]},
                {kind = "sleep", seconds = 30.0},
            }, false)
        end)
    end

    step("Z OWN HIM -- spawn = true, the only call here that writes a root", function(c)
        return a.atoms(c, "SQ_XOL_XOL", {{kind = "trivial"}}, true)
    end)

    local function post(c, at, label, send)
        c:set_variable("xol.boss.now", label)
        local key
        local ok, err = pcall(function() key = send(c) end)
        if not ok then
            c:set_variable("xol.boss.r" .. at, "RAISED " .. tostring(err):sub(-48))
            return
        end
        c:set_variable("xol.boss.r" .. at, "sent -- awaiting outcome")
        if key ~= nil then
            c:set_variable("xol.boss.key", key)
            c:set_variable("xol.boss.slot", at)
        else
            c:set_variable("xol.boss.r" .. at, "sent -- no request key returned")
        end
    end

    local function rung(c, s)
        if s:variable("xol.boss.done") then return end
        local at = (s:variable("xol.boss.rung") or 0) + 1
        c:set_variable("xol.boss.rung", at)
        if at > #STEPS then
            c:set_variable("xol.boss.now", "LADDER FINISHED")
            status(c, "ladder finished -- nothing left to try")
            return
        end
        local row = STEPS[at]
        post(c, at, row[1], row[2])
        status(c, row[1])
        c:start_timer(LADDER_TIMER, DWELL)
    end

    function B.start(c, s)
        if s:variable("xol.boss.started") then return end
        c:set_variable("xol.boss.started", true)
        c:set_variable("xol.boss.version", "authored-ability-sweep-1")
        pcall(function() a.spawn(c, s, {"xol"}) end)
        pcall(function() a.scene(c, "ARRIVE_1") end)
        c:set_variable("xol.boss.now", "ladder starts in " .. (FIRST // 1000) .. "s")
        status(c, "waiting to start the ladder")
        c:start_timer(LADDER_TIMER, FIRST)
    end

    function B.guidance(c, s)
        a.directive(c, s, "defeat_xol", nil, "M_ENGAGEMENT_SENSOR_80F76B80")
    end

    function B.timer(c, s, e)
        if e.timer_name ~= LADDER_TIMER then return false end
        rung(c, s)
        return true
    end

    function B.squad(c, s, e)
        if not a.matches(c, e, "SQ_XOL_80F76B80") or s:variable("xol.boss.done") then return end
        local groups = AI.groups(mission, "XOL_OBJECTIVE")
        if groups == nil then
            c:set_variable("xol.boss.ai.groups", "none -- XOL_OBJECTIVE has no authored groups")
            return
        end
        local _, assigned = e:task_group{objective = a.slot(c, "XOL_OBJECTIVE")}
        c:set_variable("xol.boss.ai.groups", "present")
        c:set_variable("xol.boss.ai.assigned", assigned == true)
    end

    function B.cleared(c, s, name)
        if name ~= "xol" then return end
        c:set_variable("xol.boss.done", true)
        c:cancel_timer(LADDER_TIMER)
        c:set_variable("xol.boss.died_on", tostring(s:variable("xol.boss.now")))
        status(c, "Xol cleared -- see xol.boss.died_on")
    end

    function B.actor_path(c, s, e)
        if not a.matches(c, e, "SQ_XOL_XOL") then return end
        c:set_variable("xol.boss.actor.dead", e.dead)
    end

    function B.reset(c)
        c:cancel_timer(LADDER_TIMER)
        for _, key in ipairs({"started", "done", "rung", "now", "status", "version",
            "died_on", "ai.groups", "ai.assigned", "actor.dead", "key", "slot"}) do
            c:clear_variable("xol.boss." .. key)
        end
        for index = 1, #STEPS do c:clear_variable("xol.boss.r" .. index) end
    end

    function B.watchdog(c, s) end
    function B.scene_finished(c, s, e) end
    function B.client(c, s, e) end
    function B.interaction(c, s, e) end
    function B.object(c, s, e) end

    function B.damage(c, s, e)
        if not a.matches(c, e, "SQ_XOL_XOL") then return end
        c:set_variable("xol.boss.health", e.health)
    end

    function B.spawned(c, s, e) end

    function B.effect(c, s, e)
        local pending = s:variable("xol.boss.key")
        if pending == nil or e.request_key == nil or e.request_key.value ~= pending then
            return
        end
        local at = s:variable("xol.boss.slot") or 0
        c:set_variable("xol.boss.r" .. at,
            tostring(e.effect) .. " -> " .. tostring(e.outcome))
        c:clear_variable("xol.boss.key")
    end
    return B
end
end)()

-- ============================================================================
-- probe.lua
-- Trigger-sweep diagnostic mode. Off unless PROBE_MODE is set in the route.
-- ============================================================================
local MOD_probe = (function()
return function(mission, a, TRIGGERS)
    local P = {}

    local BATCH = 6
    local TICK = 400
    local RESCAN = 8000
    local TIMER = "xol.probe.arm"

    local function armed(s) return s:variable("xol.probe.armed") or 0 end

    local function report(c, s, code)
        local last = s:variable("xol.probe.last")
        c:set_phase(last and (1000 + last) or code)
    end

    function P.rearm(c, s)
        c:set_variable("xol.probe.armed", 0)
        c:set_variable("xol.probe.failed", 0)
        c:cancel_timer(TIMER)
        c:start_timer(TIMER, TICK)
    end

    function P.start(c, s)
        if s:variable("xol.probe.started") then return end
        c:set_variable("xol.probe.started", true)
        c:set_phase(900)
        P.rearm(c, s)
    end

    function P.timer(c, s, e)
        if e.timer_name ~= TIMER then return false end
        local total = #TRIGGERS
        local first = armed(s) + 1
        if first > total then
            P.rearm(c, s)
            return true
        end
        local last = math.min(first + BATCH - 1, total)
        local failed = s:variable("xol.probe.failed") or 0
        for index = first, last do
            local ok = pcall(function() a.slot(c, TRIGGERS[index]):fire_trigger{} end)
            if not ok then failed = failed + 1 end
        end
        c:set_variable("xol.probe.failed", failed)
        c:set_variable("xol.probe.armed", last)
        if last < total then
            c:start_timer(TIMER, TICK)
            report(c, s, 900 + last)
        else
            c:start_timer(TIMER, RESCAN)
            report(c, s, failed > 0 and (800 + math.min(failed, 99)) or 999)
        end
        return true
    end

    function P.trigger(c, s, e)
        for index, name in ipairs(TRIGGERS) do
            if a.matches(c, e, name) then
                c:set_variable("xol.probe.last", index)
                c:set_variable("xol.probe.count", (s:variable("xol.probe.count") or 0) + 1)
                c:set_phase(1000 + index)
                return
            end
        end
        c:set_phase(998)
    end

    return P
end
end)()

-- ============================================================================
-- triggers.lua
-- Every type-31 player trigger in the scenario, for the arming heartbeat.
-- ============================================================================
local MOD_triggers = (function()
return {
    "PT_THRALLS",                                          --  1  80f736a8  pt_thralls
    "PT_SPAWN_THRALLS_TRIGGER",                            --  2  80f736f2  pt_spawn_thralls_trigger
    "PT_THRALL_SPAWN",                                     --  3  80f73755  pt_thrall_spawn
    "PT_ANCHOR_FALLBACK_1",                                --  4  80f737d8  pt_anchor_fallback_1
    "PT_MIDDLE_SPAWN",                                     --  5  80f737d8  pt_middle_spawn
    "PT_RANGED",                                           --  6  80f737d8  pt_ranged
    "PT_XOL_INTRO",                                        --  7  80f739f9  pt_xol_intro
    "PT_FRONT_HALL",                                       --  8  80f73a65  pt_front_hall
    "PT_CAFE",                                             --  9  80f73a65  pt_cafe
    "PT_ENTRY",                                            -- 10  80f73ad0  pt_entry
    "PF2_OUTLAWS_POLARIS_CORE_PT_ENGAGED_80F73C69",        -- 11  80f73c69  pf2_outlaws_polaris_core.pt_engaged
    "PF2_OUTLAWS_KILL_OLD_BOSS_PT_BOSS_DEATH_80F73C69",    -- 12  80f73c69  pf2_outlaws_kill_old_boss.pt_boss_death
    "PT_SPAWN_FALLEN_RUSHER_80F73C69",                     -- 13  80f73c69  pt_spawn_fallen_rusher
    "PT_BEGIN",                                            -- 14  80f73eac  pt_begin
    "PT_HALL",                                             -- 15  80f73eac  pt_hall
    "PF2_OUTLAWS_POLARIS_CORE_PT_ENGAGED_80F7606F",        -- 16  80f7606f  pf2_outlaws_polaris_core.pt_engaged
    "PF2_OUTLAWS_KILL_OLD_BOSS_PT_BOSS_DEATH_80F7606F",    -- 17  80f7606f  pf2_outlaws_kill_old_boss.pt_boss_death
    "PT_SPAWN_FALLEN_RUSHER_80F7606F",                     -- 18  80f7606f  pt_spawn_fallen_rusher
    "PT_SPAWN_MAIN_ENCOUNTER",                             -- 19  80f7619e  pt_spawn_main_encounter
    "PT_SPAWN_INTRO_ENCOUNTER",                            -- 20  80f7619e  pt_spawn_intro_encounter
    "PT_ARENA_QUARANTINE",                                 -- 21  80f7619e  pt_arena_quarantine
    "OUTLAWS_STRIKES_MANAGER_PREFAB_OUTLAWS_SPAWN_PLAYER_TRIGGER", -- 22  80f7619e  outlaws_strikes_manager_prefab.outlaws_spawn_player_trigger
    "PT_BACK_SPAWN",                                       -- 23  80f761f6  pt_back_spawn
    "PT_ENTRANCE_UNLEASH",                                 -- 24  80f761f6  pt_entrance_unleash
    "PT_XOL_HINT",                                         -- 25  80f7622d  pt_xol_hint
    "PT_SPAWN_ENCOUNTER_80F762A4",                         -- 26  80f762a4  pt_spawn_encounter
    "PT_SPAWN_ENCOUNTER_80F762FD",                         -- 27  80f762fd  pt_spawn_encounter
    "PT_SPAWN_ENERGY3",                                    -- 28  80f762fd  pt_spawn_energy3
    "PT_AWAKENING_1",                                      -- 29  80f7647d  pt_awakening_1
    "PT_AWAKENING_2",                                      -- 30  80f7647d  pt_awakening_2
    "PT_ENERGY_1",                                         -- 31  80f7648e  pt_energy_1
    "PT_ENERGY_1B",                                        -- 32  80f7648e  pt_energy_1b
    "PT_ENERGY_SPAWN_INITIAL",                             -- 33  80f7649f  pt_energy_spawn_initial
    "PT_ENERGY_3_80F7649F",                                -- 34  80f7649f  pt_energy_3
    "PT_ENERGY_4",                                         -- 35  80f764b3  pt_energy_4
    "PT_ENERGY_3_80F764B3",                                -- 36  80f764b3  pt_energy_3
    "PT_ENERGY_3_EXIT",                                    -- 37  80f764b3  pt_energy_3_exit
    "PT_GOTO_HEATSINK_80F764C1",                           -- 38  80f764c1  pt_goto_heatsink
    "PT_HEATSINK_ROAR_DIALOG",                             -- 39  80f764cf  pt_heatsink_roar_dialog
    "PT_PRIESTS_1",                                        -- 40  80f764dd  pt_priests_1
    "PT_XOL_MINIHEAT_FALLBACK",                            -- 41  80f76532  pt_xol_miniheat_fallback
    "PT_XOL_HINT_MEDIUM_1",                                -- 42  80f76532  pt_xol_hint_medium_1
    "PT_GOTO_MINIHEAT_A",                                  -- 43  80f76546  pt_goto_miniheat_a
    "PT_EXIT_MINIHEAT",                                    -- 44  80f76546  pt_exit_miniheat
    "PT_GOTO_HEATSINK_80F76546",                           -- 45  80f76546  pt_goto_heatsink
    "PT_FLYOVER",                                          -- 46  80f765ba  pt_flyover
    "PT_DOOR_B",                                           -- 47  80f767af  pt_door_b
    "PT_DOOR_C",                                           -- 48  80f767af  pt_door_c
    "PT_NEAR_FW",                                          -- 49  80f76838  pt_near_fw
    "PT_ENTER_DOOR",                                       -- 50  80f768ff  pt_enter_door
    "BARRIER_TRIGGER",                                     -- 51  80f7697d  barrier_trigger
    "PT_CORE_TRIGGER",                                     -- 52  80f76a08  pt_core_trigger
    "PT_XOL_ARENA_QUARANTINE_TRIGGER",                     -- 53  80f76b80  pt_xol_arena_quarantine_trigger
    "PT_START_ZAVALA_SCENE",                               -- 54  80f76bdf  pt_start_zavala_scene
    "PT_SPIRE_AIRLOCK",                                    -- 55  80f76bdf  pt_spire_airlock
    "PT_GOTO_SPIRE",                                       -- 56  80f76bf7  pt_goto_spire
    "PT_GUNROOM_SPIRE",                                    -- 57  80f76bf7  pt_gunroom_spire
    "PT_GOTO_SPIRE_HEATSINK",                              -- 58  80f76bf7  pt_goto_spire_heatsink
    "PT_XOL_START",                                        -- 59  80f76c06  pt_xol_start
    "PT_DROPSHIP_START",                                   -- 60  80f76e35  pt_dropship_start
    "ENFORCER_APPROACHED_TRIGGER",                         -- 61  80f76ec8  enforcer_approached_trigger
    "CABAL_LOWER_SPAWN_TRIGGER",                           -- 62  80f76ec8  cabal_lower_spawn_trigger
    "PLAYER_IS_NEAR_BATTLE_TRIGGER",                       -- 63  80f76ec8  player_is_near_battle_trigger
}
end)()

-- ============================================================================
-- route.lua
-- The stage machine: what each beat opens, spawns, says and waits for. This is the
-- bulk of the mission.
-- ============================================================================
local MOD_route = (function()

local BOSS = MOD_boss
local PROBE = MOD_probe
local ALL_TRIGGERS = MOD_triggers

local PROBE_MODE = false

local OPEN_ROUTE_DOORS_AT_START = false

local PHASE_SHOWS_STAGE = true

local MAX_SKIP = 2
local SKIP_INSIST = 3

local HOLD_RELEASE = 240000
local HOLD_TIMER = "xol.hold"

local CHECKPOINTS = {
    [1]  = 0x1FBEB09F,  [2]  = 0x1FBEB09F,
    [3]  = 0x22915EFE,
    [4]  = 0x2EA8FB98,
    [5]  = 0x42255A8A,  [6]  = 0x42255A8A,  [7]  = 0x42255A8A,
    [8]  = 0x25506FA7,
    [9]  = 0xD1A2BAC4,
    [11] = 0xDB99EC2A,  -- the spire corridor, off the airlock screenshots
    [12] = 0xDB99EC2A,
    [13] = 0xC7CF9198,  -- the bridge
    [14] = 0xC7CF9198,
}

local REARM_TICK = 10000
local REARM_TIMER = "xol.rearm"
local BRIDGE_SLAM_TIMER = "xol.bridge.slam"
local BRIDGE_BREAK_TIMER = "xol.bridge.break"

local SLAM_IMPACT = 0

local BREAK_IMPACT     = 0       -- the ram, the rupture, the camera
local BREAK_SECTION_1  = 200     -- the piece he hits first
local BREAK_SECTION_2  = 100
local BREAK_SECTION_3  = 100
local BREAK_EXTENSIONS = 1500   -- the rest of the span, coming away behind him
local BREAK_SWAP       = 700   -- the torn end that stays hanging off the edge

local GATES = {
    {name = "D_PHASE_WALL",       from = 2,  upto = 2},  -- opened when the cave knights fall
    {name = "D_ENERGY_DOOR_1",    from = 4,  upto = 4},  -- by the first charge
    {name = "D_ENERGY_DOOR_2",    from = 6,  upto = 7},  -- by the second
    {name = "D_ENERGY_DOOR_3",    from = 8,  upto = 8},  -- by the third
    {name = "D_ENERGY_CORE_DOOR", from = 9,  upto = 9},  -- by the ogre and the wizard
    {name = "D_CORE_EXIT_DOOR",   from = 9,  upto = 10}, -- by the core charge
}
local GATE_BY_NAME = {}
for _, row in ipairs(GATES) do GATE_BY_NAME[row.name] = row end

local INVERTED = {
    D_PHASE_WALL = true,
}

local TRIGGER_DOORS = {
    {trigger = "PT_GOTO_SPIRE_HEATSINK", name = "D_ENERGY_DOOR_6", blockers = {"O_DOOR"}},
}

local DOORS = {
    {stage = 11, name = "D_ENERGY_DOOR_6"},
    {stage = 11, name = "D_LANDING_DOOR"},
    {stage = 11, name = "D_RASPUTIN_DOOR_1"},
    {stage = 11, name = "D_RASPUTIN_DOOR_2"},
    {stage = 11, name = "D_RASPUTIN_DOOR_3"},
    {stage = 11, name = "D_SOTG_DOOR_1"},
    {stage = 11, name = "D_SOTG_DOOR_2"},
    {stage = 11, name = "D_LOOPBACK_DOOR_1"},
    {stage = 11, name = "D_LOOPBACK_DOOR_2"},
    {stage = 12, name = "D_ZAVALA_DOOR_PROXY"},

    {stage = 14, name = "D_BOSS_DOOR"},
}

local BLOCKERS = {
    {stage = 11, name = "O_LOOPBACK_DOOR_2"},
    {stage = 11, name = "O_DOOR"},
    {stage = 14, name = "O_BOSS_DOOR"},
}

local BRIDGE_SECTIONS = {"BRIDGE_SECTION_DEVICE_1", "BRIDGE_SECTION_DEVICE_2",
    "BRIDGE_SECTION_DEVICE_3"}
local BRIDGE_EXTENSIONS = {
    "BRIDGE_EXTENSION_1", "BRIDGE_EXTENSION_2", "BRIDGE_EXTENSION_3", "BRIDGE_EXTENSION_4",
    "BRIDGE_EXTENSION_5", "BRIDGE_EXTENSION_6", "BRIDGE_EXTENSION_7", "BRIDGE_EXTENSION_8",
    "BRIDGE_EXTENSION_9", "BRIDGE_EXTENSION_10", "BRIDGE_EXTENSION_11", "BRIDGE_EXTENSION_12",
    "BRIDGE_EXTENSION_13", "BRIDGE_EXTENSION_14", "BRIDGE_EXTENSION_15"}

local BRIDGE_SWAP = "BRIDGE_SECTION_SWAP"

local BRIDGE_FIRE = {"DROP_FIRE_1", "DROP_FIRE_2", "DROP_FIRE_3", "DROP_FIRE_4"}

local BRIDGE_HAZARDS = {"TOGGLE_BRIDGE_SLIDING_TRIGGER", "TOGGLE_BRIDGE_ARC_HAZARD_TRIGGER",
                        "TOGGLE_BRIDGE_ARC_GROUNDED_HAZARD_TRIGGER"}

local TRIGGERS = {
    "PT_XOL_INTRO",
    "PT_XOL_HINT_MEDIUM_1", "PT_XOL_MINIHEAT_FALLBACK", "PT_GOTO_MINIHEAT_A",
    "PT_EXIT_MINIHEAT", "PT_GOTO_HEATSINK_80F76546",
    "PT_BACK_SPAWN", "PT_ENTRANCE_UNLEASH",
    "PT_ENERGY_1", "PT_ENERGY_SPAWN_INITIAL", "PT_ENERGY_1B", "PT_ENERGY_3_80F7649F",
    "PT_SPAWN_ENCOUNTER_80F762FD", "PT_SPAWN_ENERGY3",
    "PT_ENERGY_3_80F764B3", "PT_ENERGY_4", "PT_ENERGY_3_EXIT",
    "PT_SPAWN_INTRO_ENCOUNTER", "PT_ARENA_QUARANTINE", "PT_SPAWN_MAIN_ENCOUNTER",
    "OUTLAWS_STRIKES_MANAGER_PREFAB_OUTLAWS_SPAWN_PLAYER_TRIGGER", "PT_PRIESTS_1",
    "PT_AWAKENING_1", "PT_AWAKENING_2",
    "PT_XOL_HINT",
    "PT_HEATSINK_ROAR_DIALOG", "PT_GOTO_HEATSINK_80F764C1",
    "PT_SPIRE_AIRLOCK", "PT_GUNROOM_SPIRE", "PT_START_ZAVALA_SCENE",
    "PT_GOTO_SPIRE", "PT_GOTO_SPIRE_HEATSINK",
    "PT_XOL_START", "PT_XOL_ARENA_QUARANTINE_TRIGGER",
}

local CHARGES = {
    energy1 = {vent = "DEVICE_HEATSINK_BATTERY_1", target = "O_HEATSINK_DESTRUCTIBLE_1",
               door = "D_ENERGY_DOOR_1", cue = 4},
    energy2 = {vent = "DEVICE_HEATSINK_BATTERY_2", target = "O_HEATSINK_DESTRUCTIBLE_2",
               door = "D_ENERGY_DOOR_2", cue = 9},
    energy3 = {vent = "DEVICE_HEATSINK_BATTERY_3", target = "O_HEATSINK_DESTRUCTIBLE_3",
               door = "D_ENERGY_DOOR_3", cue = 10},
    core    = {vent = "DEVICE_HEATSINK_CORE_80F760F2", target = "O_HEATSINK_DESTRUCTIBLE_FORGE",
               door = "D_CORE_EXIT_DOOR", cue = 14},
}
local CHARGE_ORDER = {"energy1", "energy2", "energy3", "core"}

return function(mission)
    local R = {}
    local a
    local boss
    local probe

    local function stage(s) return s:variable("xol.stage") or 0 end

    local function charge_key(key) return "xol.chg." .. key end

    local core_opened

    local function gate_key(name) return "xol.gate." .. name end

    local FORCE_LIMIT = 3

    local POSITION_DRIVEN = {
        D_ENERGY_DOOR_6 = true,      -- the airlock at the end of the core corridor
        D_CORE_EXIT_DOOR = true,
        D_ZAVALA_DOOR_PROXY = true,
        D_PHASE_WALL = true,
    }

    local NEVER_FORCED = {D_ZAVALA_DOOR_PROXY = true}

    local function drive(c, s, name, clear, force)
        if NEVER_FORCED[name] then force = false end
        local key = "xol.pose." .. name
        local want = clear and 1 or 0
        if force and s:variable(key) == want then
            local tries = (s:variable("xol.force." .. name) or 0) + 1
            if tries > FORCE_LIMIT then
                force = false
            else
                c:set_variable("xol.force." .. name, tries)
            end
        end
        local fresh = force or s:variable(key) ~= want
        c:set_variable(key, want)
        local pose = clear
        if INVERTED[name] then pose = not pose end
        pcall(function()
            a.lane(c, name, "unlock")
            a.lane(c, name, "power_on")
            if POSITION_DRIVEN[name] then
                if fresh and not NEVER_FORCED[name] then a.device(c, name, not pose, true) end
                a.device(c, name, pose)
            end
        end)
    end

    local function open_gate(c, s, name)
        c:set_variable(gate_key(name), true)
        drive(c, s, name, true)
    end

    local function shut_gate(c, s, name)
        drive(c, s, name, false)
        pcall(function() a.lane(c, name, "lock") end)
    end

    local function drop_phase_wall(c, s)
        if s:variable("xol.phasewall") then return end
        c:set_variable("xol.phasewall", true)
        pcall(function() a.objects(c, {"O_PHASE_WALL"}, false) end)
        open_gate(c, s, "D_PHASE_WALL")
    end

    local reported_row = {}
    local function s_has(_, key) return reported_row[key] ~= nil end
    local function mark_row(key) reported_row[key] = true end

    local function offer(c, names, tag)
        for index, name in ipairs(names) do
            local key
            local ok = pcall(function()
                key = a.slot(c, name):set_interactable_object{active = true}
            end)
            if tag and index == 1 and ok and key ~= nil and not s_has(c, "xol.k." .. tag) then
                mark_row("xol.k." .. tag)
                c:set_variable("xol.k." .. tag, key.value)
                c:set_variable("xol.r." .. tag, "sent")
            elseif tag and index == 1 and not ok then
                c:set_variable("xol.r." .. tag, "RAISED")
            end
        end
    end

    local function open_vent(c, s, key)
        local row = CHARGES[key]
        a.enable_device(c, row.vent)
        a.device(c, row.vent, true)
        if s:variable(charge_key(key)) then return end
        c:set_variable(charge_key(key), 1)
        a.objects(c, {row.target}, true)
        offer(c, {row.target}, "c." .. key)
    end

    local ON_BLOW = {
        energy1 = function(c, _) a.sequence(c, "SEQUENCE_ENERGY1_ALARM") end,
        energy2 = function(c, s) a.cue(c, s, 6) end,
        energy3 = function(c, _) a.sequence(c, "SEQUENCE_CORE_ALARM") end,
    }

    local function charge_blown(c, s, key)
        if s:variable(charge_key(key)) ~= 1 then return false end
        local row = CHARGES[key]
        c:set_variable(charge_key(key), 2)
        c:set_variable("xol.blown." .. key, true)
        if ON_BLOW[key] then pcall(function() ON_BLOW[key](c, s) end) end
        if key == "core" then
            core_opened(c, s)
        end
        if row.cue ~= nil and key ~= "core" then a.cue(c, s, row.cue) end
        open_gate(c, s, row.door)
        return true
    end

    local function control_arm(c, s)
        if s:variable("xol.control.armed") then return end
        c:set_variable("xol.control.armed", true)
        offer(c, {"CONTROL_ENERGY_INTERACT_OBJECT_2"})
        pcall(function() a.slot(c, "ENERGY2_GHOST_LINK"):set_ghost_link{active = true} end)
    end

    local function control_wave_one(c, s)
        if not s:variable("xol.control.scanned") then return end
        if not a.clear(s, {"control_initial"}) then return end
        a.spawn(c, s, {"control_wave1"})
    end

    local function control_scan(c, s)
        c:set_variable("xol.control.scanned", true)
        control_wave_one(c, s)
    end

    local function control_cleared(c, s, name)
        if name == "control_initial" and a.clear(s, {"control_initial"}) then
            control_arm(c, s)
            control_wave_one(c, s)
        elseif name == "control_wave1" and a.clear(s, {"control_wave1"}) then
            a.spawn(c, s, {"control_wave2"})
        elseif name == "control_wave2" and a.clear(s, {"control_wave2"}) then
            a.spawn(c, s, {"control_wave3", "control_wizard"})
        elseif name == "control_wizard" then
            a.cue(c, s, 7)
            a.sequence(c, "SEQUENCE_ENERGY2_ALARM")
            a.javelin(c, "heatsink", {"HEATSINK_JAVELIN_SPAWNER_2"})
            open_vent(c, s, "energy2")
            a.cue(c, s, 8)
        end
    end

    local CORE_SPEAR = "O_CORE_JAVELIN_SPAWNER"

    local SPEAR_LIFETIME = 21000

    function core_opened(c, s)
        if s:variable("xol.core.opened") then return end
        c:set_variable("xol.core.opened", true)
        open_gate(c, s, "D_CORE_EXIT_DOOR")
        a.javelin(c, "core", {CORE_SPEAR})
        a.cue(c, s, 14)
        a.cue(c, s, 15)
        a.javelin(c, "postcore", {"O_POSTCORE_JAVELIN_SPAWNER"})
        a.spawn(c, s, {"postcore"})
    end

    local function spear_taken(c, s)
        if s:variable("xol.spear.core") then return false end
        c:set_variable("xol.spear.core", true)
        return true
    end

    local function arena_won(c, s)
        a.javelin(c, "arena", {"HEATSINK_JAVELIN_SPAWNER_ARENA_A",
                               "HEATSINK_JAVELIN_SPAWNER_ARENA_B"})
        a.javelin(c, "arena_final", {"HEATSINK_JAVELIN_SPAWNER_ARENA_FINAL"})
        a.cue(c, s, 13)
        open_gate(c, s, "D_ENERGY_CORE_DOOR")
        open_vent(c, s, "core")
    end

    local AIRLOCK_DOORS = {"D_ENERGY_DOOR_6"}

    local AIRLOCK_HOLD_OPEN = {}
    local AIRLOCK_BLOCKERS = {"O_DOOR"}

    local function open_airlock(c, s)
        for _, name in ipairs(AIRLOCK_DOORS) do drive(c, s, name, true, true) end
        pcall(function()
            a.objects(c, AIRLOCK_BLOCKERS, false)
            for _, name in ipairs(AIRLOCK_HOLD_OPEN) do a.lane(c, name, "lock") end
            a.slot(c, "GL_DOOR"):set_ghost_link{active = true}
        end)
    end

    local BREAK_STEPS = {
        {BREAK_IMPACT,     "impact"},
        {BREAK_SECTION_1,  "section_1"},
        {BREAK_SECTION_2,  "section_2"},
        {BREAK_SECTION_3,  "section_3"},
        {BREAK_EXTENSIONS, "extensions"},
        {BREAK_SWAP,       "swap"},
    }
    table.sort(BREAK_STEPS, function(x, y) return x[1] < y[1] end)

    local function drop(c, name)
        pcall(function()
            a.enable_device(c, name)
            a.device(c, name, true)
        end)
    end

    local function break_part(c, s, what)
        c:set_variable("xol.bridge.part", what)
        if what == "impact" then
            pcall(function() a.sequence(c, "ARRIVAL_SEQUENCE") end)
            pcall(function()
                a.objects(c, {"XOL_CAMERA_DUMMY"}, true)
                a.objects(c, {"O_FLOOR_RUPTURE"}, true)
                a.scene(c, "FLOOR_RUPTURE_SCENE")
                for _, name in ipairs(BRIDGE_HAZARDS) do a.slot(c, name):fire_trigger{} end
            end)
        elseif what == "section_1" then
            drop(c, "BRIDGE_SECTION_DEVICE_1")
        elseif what == "section_2" then
            drop(c, "BRIDGE_SECTION_DEVICE_2")
        elseif what == "section_3" then
            drop(c, "BRIDGE_SECTION_DEVICE_3")
        elseif what == "extensions" then
            for _, name in ipairs(BRIDGE_EXTENSIONS) do drop(c, name) end
        elseif what == "swap" then
            pcall(function()
                a.enable_device(c, BRIDGE_SWAP)
                a.device(c, BRIDGE_SWAP, false, true)
                a.device(c, BRIDGE_SWAP, true)
            end)
        end
    end

    local function collapse(c, s)
        local at = (s:variable("xol.bridge.at") or 0) + 1
        local row = BREAK_STEPS[at]
        if row == nil then return end
        c:set_variable("xol.bridge.at", at)
        c:set_variable("xol.bridge.collapsed", true)
        break_part(c, s, row[2])
        local next_row = BREAK_STEPS[at + 1]
        if next_row then
            c:start_timer(BRIDGE_BREAK_TIMER, math.max(1, next_row[1] - row[1]))
        end
    end

    local function slam(c, s, why)
        if s:variable("xol.bridge.slam") then return end
        c:set_variable("xol.bridge.slam", why)
        c:clear_variable("xol.bridge.slam.wait")
        c:cancel_timer(BRIDGE_SLAM_TIMER)
        c:set_variable("xol.bridge.region", tostring(s:variable("xol.region")))
        pcall(function() a.place_xol(c) end)
        pcall(function() a.scene(c, "BREACH_INTRO") end)
        if SLAM_IMPACT > 0 then
            c:start_timer(BRIDGE_BREAK_TIMER, SLAM_IMPACT)
        else
            collapse(c, s)
        end
    end

    local function prime_xol(c, s)
        if s:variable("xol.primed") then return end
        local ok, err = pcall(function() a.spawn(c, s, {"xol"}) end)
        if ok then
            c:set_variable("xol.primed", true)
        else
            c:set_variable("xol.bridge.spawn.error", tostring(err):sub(-60))
        end
    end

    local function break_bridge(c, s)
        if s:variable("xol.bridge") then return end
        c:set_variable("xol.bridge", true)
        prime_xol(c, s)
        slam(c, s, "on phase 13 entry -- named boss")
    end

    local STAGES = {
        {   -- 7  pt_xol_intro
            name = "arrival",
            triggers = {"PT_XOL_INTRO"},
            directive = {"protect_rasputin", "AP_XOL_START", "M_ENGAGEMENT_SENSOR_80F73A15"},
            crossed = function(c, s) a.cue(c, s, 0) end,
        },
        {   -- 41 42 43  the first fight, and the screen shake with it
            name = "first_contact",
            groups = {"cave_snipers", "cave_main", "cave_knights"},
            triggers = {"PT_XOL_HINT_MEDIUM_1", "PT_XOL_MINIHEAT_FALLBACK",
                        "PT_GOTO_MINIHEAT_A"},
            enter = function(c, s)
                a.enable_device(c, "DEV_XOL_HINT_1")
                a.device(c, "DEV_XOL_HINT_1", true)
                a.spawn(c, s, {"cave_snipers", "cave_main", "cave_knights"})
            end,
            cleared = function(c, s, name)
                if a.clear(s, {"cave_knights"}) then drop_phase_wall(c, s) end
            end,
            hold = function(c, s) return a.combat(s, {"cave_knights"}) end,
        },
        {   -- 44 45  the banner turns over and the next room fills
            name = "neural_net",
            groups = {"pit_front", "pit_shrieker", "pit_back"},
            keep_until = 5,
            triggers = {"PT_EXIT_MINIHEAT", "PT_GOTO_HEATSINK_80F76546"},
            directive = {"investigate", "AP_GOTO_HEATSINK_80F76546",
                         "M_ENGAGEMENT_SENSOR_80F760DC"},
            enter = function(c, s)
                a.spawn(c, s, {"pit_front", "pit_shrieker", "pit_back"})
                a.cue(c, s, 2)
            end,
        },
        {   -- 31  first heatsink: hold interact at the console, then shoot the charge
            name = "heatsink_one",
            triggers = {"PT_ENERGY_1", "PT_BACK_SPAWN", "PT_ENTRANCE_UNLEASH"},
            enter = function(c, s)
                a.cue(c, s, 3)
                offer(c, {"CONTROL_ENERGY_INTERACT_OBJECT_1"})
            end,
            interactions = {"CONTROL_ENERGY_INTERACT_OBJECT_1"},
            used = function(c, s)
                a.enable_device(c, "D_ENERGY_1_SCREEN")
                a.device(c, "D_ENERGY_1_SCREEN", true)
                a.javelin(c, "heatsink", {"HEATSINK_JAVELIN_SPAWNER_1"})
                open_vent(c, s, "energy1")
            end,
        },
        {   -- 33
            name = "cooling",
            groups = {"cooling"},
            triggers = {"PT_ENERGY_SPAWN_INITIAL"},
            enter = function(c, s) a.spawn(c, s, {"cooling"}) end,
        },
        {   -- 32  the control room fills; the console only wakes once it is quiet
            name = "control_initial",
            groups = {"control_initial"},
            keep_until = 8,
            triggers = {"PT_ENERGY_1B"},
            enter = function(c, s) a.spawn(c, s, {"control_initial"}) end,
            cleared = control_cleared,
            interactions = {"CONTROL_ENERGY_INTERACT_OBJECT_2"},
            ghost = {"ENERGY2_GHOST_LINK"},
            used = control_scan,
        },
        {   -- 34  the scan brings the room down: three waves, and the wizard opens the vent
            name = "control_room",
            groups = {"control_wave1", "control_wave2", "control_wave3", "control_wizard"},
            triggers = {"PT_ENERGY_3_80F7649F"},
            enter = function(c, s)
                a.cue(c, s, 5)
                a.sequence(c, "SEQUENCE_SCREECH_ENERGY_2")
                a.spawn(c, s, {"control_initial"})
                if a.clear(s, {"control_initial"}) then control_arm(c, s) end
            end,
            interactions = {"CONTROL_ENERGY_INTERACT_OBJECT_2"},
            ghost = {"ENERGY2_GHOST_LINK"},
            used = control_scan,
            cleared = control_cleared,
        },
        {   -- 27 28  clear the hall, then the console frees the third charge
            name = "energy_hall",
            groups = {"energy3_entry", "energy3_shrieker", "energy3_thralls", "energy3_back"},
            triggers = {"PT_SPAWN_ENCOUNTER_80F762FD", "PT_SPAWN_ENERGY3",
                        "PT_ENERGY_3_80F764B3", "PT_ENERGY_4"},
            enter = function(c, s)
                a.spawn(c, s, {"energy3_entry", "energy3_shrieker", "energy3_thralls",
                               "energy3_back"})
                offer(c, {"CONTROL_ENERGY_INTERACT_OBJECT_3"})
                c:set_variable("xol.energy3.ready", true)
            end,
            interactions = {"CONTROL_ENERGY_INTERACT_OBJECT_3"},
            used = function(c, s)
                a.enable_device(c, "D_ENERGY_3_SCREEN")
                a.device(c, "D_ENERGY_3_SCREEN", true)
                a.javelin(c, "heatsink", {"HEATSINK_JAVELIN_SPAWNER_3"})
                open_vent(c, s, "energy3")
            end,
        },
        {   -- 37  the core arena: three waves, the ogre last
            name = "core_arena",
            groups = {"arena_wave1", "arena_wave2", "arena_wave3", "arena_wizard", "arena_ogre"},
            purge = true,
            triggers = {"PT_ENERGY_3_EXIT", "PT_SPAWN_INTRO_ENCOUNTER", "PT_ARENA_QUARANTINE",
                        "PT_SPAWN_MAIN_ENCOUNTER", "PT_PRIESTS_1",
                        "OUTLAWS_STRIKES_MANAGER_PREFAB_OUTLAWS_SPAWN_PLAYER_TRIGGER"},
            directive = {"get_to_core", nil, "M_ENGAGEMENT_SENSOR_80F7619E"},
            enter = function(c, s)
                a.objects(c, {"HEATSINK_JAVELIN_SPAWNER_ARENA_A",
                              "HEATSINK_JAVELIN_SPAWNER_ARENA_B",
                              "HEATSINK_JAVELIN_SPAWNER_ARENA_FINAL",
                              CORE_SPEAR}, false)
                a.spawn(c, s, {"arena_wave1"})
            end,
            cleared = function(c, s, name)
                if name == "arena_wave1" and a.clear(s, {"arena_wave1"}) then
                    a.spawn(c, s, {"arena_wave2"})
                    a.cue(c, s, 11)
                elseif name == "arena_wave2" and a.clear(s, {"arena_wave2"}) then
                    a.cue(c, s, 12)
                    a.spawn(c, s, {"arena_wave3", "arena_wizard", "arena_ogre"})
                elseif (name == "arena_wizard" or name == "arena_ogre")
                    and a.clear(s, {"arena_wizard", "arena_ogre"}) then
                    arena_won(c, s)
                end
            end,
            hold = function(c, s) return a.combat(s, {"arena_wizard", "arena_ogre"}) end,
        },
        {   -- 29 30  the core itself, shot rather than interacted with
            name = "final_core",
            groups = {"postcore"},
            triggers = {"PT_AWAKENING_1", "PT_AWAKENING_2"},
            directive = {"forge", "NP_AWAKENING_1", "M_ENGAGEMENT_SENSOR_80F760F2"},
            enter = function(c, s) end,
        },
        {   -- 39 25  the shake, the banner, and the door that kept blocking the run
            name = "rasputin_door",
            triggers = {"PT_HEATSINK_ROAR_DIALOG"},
            directive = {"get_to_rasputin", "NP_GOTO_SPIRE_HEATSINK",
                         "M_ENGAGEMENT_SENSOR_80F76621"},
            enter = function(c, s)
                a.sequence(c, "SEQUENCE_XOL_SCREEN_SHAKE")
                a.sequence(c, "SE_RASPUTIN_ALERT")
                open_airlock(c, s)
            end,
            tick = open_airlock,
        },
        {   -- 54 55 57  the airlock
            name = "airlock",
            groups = {"airlock_hive"},
            triggers = {"PT_START_ZAVALA_SCENE", "PT_SPIRE_AIRLOCK", "PT_GUNROOM_SPIRE"},
            enter = function(c, s)
                open_airlock(c, s)
                a.spawn(c, s, {"airlock_hive"})
            end,
            tick = open_airlock,
        },
        {   -- 56  the banner turns to the boss and the bridge goes
            name = "bridge",
            triggers = {"PT_GOTO_SPIRE", "PT_XOL_START"},
            directive = {"defeat_xol", "NP_XOL_START", "M_ENGAGEMENT_SENSOR_80F76B80"},
            enter = break_bridge,
        },
        {   -- 53  the arena. Untouched this pass.
            name = "xol_arena",
            groups = {"xol"},
            triggers = {"PT_XOL_ARENA_QUARANTINE_TRIGGER"},
            enter = function(c, s) boss.start(c, s) end,
            guidance = function(c, s) boss.guidance(c, s) end,
        },
    }

    local ROWS = {
        {beat = "heatsink_one",  name = "CONTROL_ENERGY_INTERACT_OBJECT_1", tag = "e1"},
        {beat = "control_room",  name = "CONTROL_ENERGY_INTERACT_OBJECT_2", tag = "e2",
         needs = "xol.control.armed", ghost = "ENERGY2_GHOST_LINK"},
        {beat = "energy_hall",   name = "CONTROL_ENERGY_INTERACT_OBJECT_3", tag = "e3"},
        {beat = "rasputin_door", name = "O_DOORBUTTON",   window = 3},
        {beat = "rasputin_door", name = "O_DOORBUTTON_1", window = 3},
    }
    for _, row in ipairs(ROWS) do
        for index, beat in ipairs(STAGES) do
            if beat.name == row.beat then row.index = index end
        end
        assert(row.index, "strike_xol: no beat named " .. row.beat)
    end

    local function offer_rows(c, s)
        local reached = stage(s)
        for _, row in ipairs(ROWS) do
            local spent = s:variable("xol.used." .. row.index) == true
            local expired = row.window ~= nil and reached > row.index + row.window
            local ready = row.needs == nil or s:variable(row.needs) == true
            if reached >= row.index and ready and not spent and not expired then
                offer(c, {row.name}, row.tag)
                if row.ghost then
                    pcall(function() a.slot(c, row.ghost):set_ghost_link{active = true} end)
                end
            end
        end
    end

    local function apply_doors(c, s)
        local reached = stage(s)
        local all = OPEN_ROUTE_DOORS_AT_START
        for _, row in ipairs(DOORS) do
            local settled = s:variable("xol.pose." .. row.name) == 1
            if all or (row.stage <= reached and not (settled and row.stage < reached - 3)) then
                drive(c, s, row.name, true, row.stage == reached)
            end
        end
        for _, row in ipairs(TRIGGER_DOORS) do
            if all or s:variable(gate_key(row.name)) then
                drive(c, s, row.name, true)
                if row.blockers then pcall(function() a.objects(c, row.blockers, false) end) end
            end
        end
        for _, row in ipairs(BLOCKERS) do
            if all or (row.stage <= reached and row.stage >= reached - 3) then
                pcall(function() a.objects(c, {row.name}, false) end)
            end
        end
        for _, row in ipairs(GATES) do
            local settled = s:variable("xol.pose." .. row.name) == 1
            if settled and row.upto < reached - 3 and not all then
            elseif all or s:variable(gate_key(row.name)) then
                drive(c, s, row.name, true, reached <= row.upto + 1)
            elseif reached >= row.from then
                shut_gate(c, s, row.name)
            end
        end
        pcall(function()
            local up = reached == 2 and not s:variable("xol.phasewall")
            a.objects(c, {"O_PHASE_WALL"}, up)
        end)
    end

    local function guidance(c, s)
        local current = STAGES[stage(s)]
        if current == nil then return end
        if current.guidance then current.guidance(c, s)
        elseif current.directive then
            a.directive(c, s, current.directive[1], current.directive[2], current.directive[3])
        end
        a.music(c, s)
    end

    local NEAR_BEHIND, NEAR_AHEAD = 1, 3
    local SWEEP_EVERY = 6

    local function near(s, stage_index)
        local reached = stage(s)
        return stage_index >= reached - NEAR_BEHIND and stage_index <= reached + NEAR_AHEAD
    end
    R.near = near

    local function rearm(c, s)
        local tick = (s:variable("xol.rearm.tick") or 0) + 1
        c:set_variable("xol.rearm.tick", tick)
        if tick % SWEEP_EVERY == 0 then
            a.arm(c, TRIGGERS)
        else
            local wanted = {}
            for index, row in ipairs(STAGES) do
                if row.triggers and near(s, index) then
                    for _, name in ipairs(row.triggers) do wanted[#wanted + 1] = name end
                end
            end
            for _, row in ipairs(TRIGGER_DOORS) do wanted[#wanted + 1] = row.trigger end
            a.arm(c, wanted)
        end
        apply_doors(c, s)
        offer_rows(c, s)
        if s:variable("xol.bridge") and (s:variable("xol.squad.alive") or 0) > 0 then
            pcall(function() a.ability_step(c, s) end)
        end
        local current = STAGES[stage(s)]
        if current and current.tick then pcall(function() current.tick(c, s) end) end
        if stage(s) >= #STAGES then pcall(function() boss.watchdog(c, s) end) end
        c:cancel_timer(REARM_TIMER)
        c:start_timer(REARM_TIMER, REARM_TICK)
    end

    local SWEEP_BEHIND = 1
    local function sweep_behind(c, s)
        local reached = stage(s)
        local row = STAGES[reached]
        local upto = (row and row.purge) and reached - 1 or reached - SWEEP_BEHIND
        for index = 1, upto do
            local behind = STAGES[index]
            if behind and behind.groups and not s:variable("xol.swept." .. index)
                and reached >= (behind.keep_until or 0) then
                c:set_variable("xol.swept." .. index, true)
                pcall(function() a.abandon(c, s, behind.groups) end)
            end
        end
    end

    local function advance(c, s, target)
        if target > #STAGES then target = #STAGES end
        while stage(s) < target do
            local next_stage = stage(s) + 1
            c:set_variable("xol.stage", next_stage)
            if PHASE_SHOWS_STAGE and not PROBE_MODE then c:set_phase(next_stage) end
            a.checkpoint(c, s, next_stage, s:variable("xol.region"), CHECKPOINTS[next_stage])
            apply_doors(c, s)
            local row = STAGES[next_stage]
            if row and row.enter then
                pcall(function() row.enter(c, s) end)
            end
            sweep_behind(c, s)
        end
        guidance(c, s)
    end
    R.advance = advance

    function R.bind(support)
        a = support
        boss = BOSS(mission, support, function(c, s) advance(c, s, stage(s) + 1) end)
        probe = PROBE(mission, support, ALL_TRIGGERS)
        return R
    end

    function R.client(c, s, e)
        a.arrival(c, s)
        local region = e.held_region_index or e.current_region_index
        local moved = region ~= nil and s:variable("xol.arm.region") ~= region
        if moved then c:set_variable("xol.arm.region", region) end
        local first = not s:variable("xol.armed")
        if first then
            c:set_variable("xol.armed", true)
            if stage(s) == 0 then advance(c, s, 1) end
        end
        if PROBE_MODE then
            if first or moved then apply_doors(c, s) end
            probe.start(c, s)
            if moved and not first then probe.rearm(c, s) end
            return
        end
        if first or moved then rearm(c, s) end
        if stage(s) >= #STAGES then boss.client(c, s, e) end
        guidance(c, s)
    end

    function R.trigger(c, s, e)
        if PROBE_MODE then probe.trigger(c, s, e); return end
        local at = stage(s)
        for _, row in ipairs(TRIGGER_DOORS) do
            if a.matches(c, e, row.trigger) then
                c:set_variable(gate_key(row.name), true)
                drive(c, s, row.name, true, true)
                if row.blockers then pcall(function() a.objects(c, row.blockers, false) end) end
                return
            end
        end
        local current = STAGES[at]
        if current and current.crossed and not s:variable("xol.crossed." .. at)
            and current.triggers and a.matches_any(c, e, current.triggers) then
            c:set_variable("xol.crossed." .. at, true)
            current.crossed(c, s)
            guidance(c, s)
            return
        end
        for index, row in ipairs(STAGES) do
            if row.triggers and index > at and a.matches_any(c, e, row.triggers) then
                if current and current.hold and not s:variable("xol.hold.done." .. at)
                    and current.hold(c, s) then
                    c:set_variable("xol.held", (s:variable("xol.held") or 0) + 1)
                    return
                end
                if index - at > MAX_SKIP then
                    local key = "xol.skip." .. index
                    local insisted = (s:variable(key) or 0) + 1
                    c:set_variable(key, insisted)
                    c:set_variable("xol.skips", (s:variable("xol.skips") or 0) + 1)
                    if insisted < SKIP_INSIST then return end
                end
                advance(c, s, index)
                return
            end
        end
        guidance(c, s)
    end

    local function scan_done(c, s, e, names)
        if not a.matches_any(c, e, names) then return false end
        local key = "xol.scan." .. stage(s)
        if e.active == true and (e.progress or 0) > 0 then
            c:set_variable(key, true)
            return false
        end
        return e.active == false and s:variable(key) == true
    end

    local function consumed(c, s, e, is_ghost)
        local current = STAGES[stage(s)]
        if current == nil or current.used == nil then return false end
        if s:variable("xol.used." .. stage(s)) then return false end
        local named
        if is_ghost then
            named = current.ghost ~= nil and scan_done(c, s, e, current.ghost)
        else
            named = current.interactions ~= nil
                and a.matches_any(c, e, current.interactions)
        end
        if not named then return false end
        c:set_variable("xol.used." .. stage(s), true)
        current.used(c, s)
        return true
    end

    function R.interaction(c, s, e)
        if a.matches(c, e, CORE_SPEAR) and spear_taken(c, s) then guidance(c, s); return end
        if consumed(c, s, e) then guidance(c, s); return end
        if stage(s) >= #STAGES then boss.interaction(c, s, e) end
        guidance(c, s)
    end

    function R.ghost_link(c, s, e)
        if PROBE_MODE then return end
        if consumed(c, s, e, true) then guidance(c, s) end
    end

    function R.cleared(c, s, name)
        local current = STAGES[stage(s)]
        if current and current.cleared then current.cleared(c, s, name) end
        if stage(s) >= #STAGES then boss.cleared(c, s, name) end
        guidance(c, s)
    end

    function R.squad(c, s, e)
        a.squad(c, s, e)
        if stage(s) >= #STAGES - 1 then boss.squad(c, s, e) end
        if a.matches(c, e, "SQ_XOL_80F76B80") and e.alive_count ~= nil then
            c:set_variable("xol.squad.alive", e.alive_count)
            if e.alive_count > 0 and s:variable("xol.bridge.slam.wait") then
                slam(c, s, "on living Xol squad report")
            end
            if e.alive_count > 0 and not s:variable("xol.snapped") then
                c:set_variable("xol.snapped", true)
                pcall(function() a.snap_xol(c) end)
            end
        end
        local ok = pcall(function()
            if not a.matches(c, e, "SQ_XOL_80F76B80") then return end
            c:set_variable("xol.task.report", (s:variable("xol.task.report") or 0) + 1)
            local groups = a.task_groups("XOL_OBJECTIVE")
            if groups == nil then
                c:set_variable("xol.task.best", "NONE -- XOL_OBJECTIVE has no authored groups")
                return
            end
            local best, at, known = nil, -1, 0
            local row, part = "", 1
            for index = 1, #groups do
                local cost, qualified = e:task_cost{group = groups[index]}
                local shown = "?"
                if qualified and cost ~= nil then
                    known = known + 1
                    shown = tostring(math.floor(cost + 0.5))
                    if best == nil or cost < best then best, at = cost, index - 1 end
                end
                row = row .. (index - 1) .. "=" .. shown .. " "
                if index % 4 == 0 or index == #groups then
                    c:set_variable("xol.task.c" .. part, row)
                    part, row = part + 1, ""
                end
            end
            c:set_variable("xol.task.count", #groups)
            c:set_variable("xol.task.received", known)
            c:set_variable("xol.task.best", best == nil
                and (known == 0 and "UNKNOWN -- no qualified costs in this report"
                                or "NONE -- every qualified group is unreachable")
                or (at .. " at " .. math.floor(best + 0.5)))
        end)
        if not ok then c:set_variable("xol.task.error", "cost read raised") end
    end

    function R.spawned(c, s, e)
        c:set_variable("xol.ev.spawned.last",
            tostring(e.slot_type) .. "/" .. tostring(e.slot_index))
        local ours = false
        pcall(function() ours = a.matches_any(c, e, {"SQ_XOL_XOL", "SQ_XOL_80F76B80"}) end)
        if not ours then return end
        c:set_variable("xol.entity.xol", true)
        if s:variable("xol.bridge.slam.wait") then
            slam(c, s, "as he arrived")
        end
        if stage(s) >= #STAGES then boss.spawned(c, s, e) end
    end

    function R.timer(c, s, e)
        if PROBE_MODE then return probe.timer(c, s, e) end
        if e.timer_name == REARM_TIMER then rearm(c, s); return true end
        if e.timer_name == BRIDGE_SLAM_TIMER then
            slam(c, s, "on the 12s spawn backstop")
            return true
        end
        if e.timer_name == BRIDGE_BREAK_TIMER then collapse(c, s); return true end
        for _, key in ipairs(CHARGE_ORDER) do
            if e.timer_name == charge_key(key) then
                if charge_blown(c, s, key) then guidance(c, s) end
                return true
            end
        end
        if stage(s) >= #STAGES then return boss.timer(c, s, e) end
        return false
    end

    function R.object(c, s, e)
        if a.matches(c, e, CORE_SPEAR) and (e.present == false or e.alive == false) then
            if spear_taken(c, s) then guidance(c, s) end
            return
        end
        for _, key in ipairs(CHARGE_ORDER) do
            local row = CHARGES[key]
            if s:variable(charge_key(key)) == 1 and a.matches(c, e, row.target)
                and (e.present == false or e.alive == false) then
                if charge_blown(c, s, key) then guidance(c, s) end
                return
            end
        end
        if stage(s) >= #STAGES then boss.object(c, s, e) end
    end

    function R.actor_path(c, s, e)
        if PROBE_MODE then return end
        if stage(s) >= #STAGES then boss.actor_path(c, s, e) end
    end

    function R.damage(c, s, e)
        if stage(s) >= #STAGES then boss.damage(c, s, e) end
    end

    function R.scene_finished(c, s, e)
        if a.matches(c, e, "BREACH_INTRO") then
            c:set_variable("xol.bridge.scene.finished", true)
        end
        if stage(s) >= #STAGES then boss.scene_finished(c, s, e) end
    end

    function R.effect(c, s, e)
        if e.request_key ~= nil then
            for _, tag in ipairs({"e1", "e2", "e3", "c.energy1", "c.energy2", "c.energy3",
                                  "c.core", "place", "snap", "ab"}) do
                if s:variable("xol.k." .. tag) == e.request_key.value then
                    c:set_variable("xol.r." .. tag, tostring(e.outcome))
                    c:clear_variable("xol.k." .. tag)
                end
            end
        end
        if stage(s) >= #STAGES then boss.effect(c, s, e) end
    end

    function R.reset(c, s)
        local current = STAGES[stage(s)]
        if current == nil then return end
        if stage(s) == #STAGES then boss.reset(c) end
        if current.groups then a.reset(c, current.groups) end
        c:clear_variable("xol.guidance")
        c:clear_variable("xol.used." .. stage(s))
        c:clear_variable("xol.crossed." .. stage(s))
        if current.enter then
            c:clear_variable("xol.boss.started")
            pcall(function() current.enter(c, s) end)
        end
        guidance(c, s)
    end

    R.stage = stage
    R.count = #STAGES
    return R
end
end)()

-- ============================================================================
-- wipe.lua
-- Hard-wipe detection and checkpoint restart.
-- ============================================================================
local MOD_wipe = (function()
return function(mission, route)
    local function checkpoint(state)
        return state:variable("xol.spawn.region"), state:variable("xol.spawn.hash")
    end
    local function timer(state)
        return "xol.wipe.countdown." .. (state:variable("xol.wipe.cycle") or 0)
    end
    local function stage(state) return state:variable("xol.wipe.stage") or 0 end
    local function report(context, at) context:set_phase(500 + at) end
    local function countdown(context, seconds)
        context:slot(assert(mission.Slot.HARD_WIPE_GLOBALS)):set_darkness_zone{
            enabled = true, wipe_seconds = seconds}
    end
    local function cancel(context, state)
        context:cancel_timer(timer(state))
        context:cancel_timer("xol.wipe.retry")
        context:clear_variable("xol.wipe.tries")
        context:clear_variable("xol.wipe.stage")
        context:clear_variable("xol.wipe.seconds")
        context:clear_variable("xol.wipe.request")
        context:slot(assert(mission.Slot.HARD_WIPE_GLOBALS)):set_darkness_zone{
            enabled = state:variable("xol.darkness") == true}
    end

    return {
        active = function(state) return stage(state) >= 2 end,

        fireteam = function(context, state, event)
            local dead = event.dead_count or 0
            local alive = event.alive_count or 0
            local unknown = event.unknown_count or 0
            local all_dead = dead > 0 and alive == 0 and unknown == 0
            context:set_variable("xol.wipe.all_dead", all_dead)
            context:set_variable("xol.wipe.seen", dead .. "/" .. alive .. "/" .. unknown)
            if stage(state) >= 2 then return end -- Native cleanup now owns missing players.
            if not all_dead then
                if stage(state) == 1 then cancel(context, state) end
                return
            end
            local region, hash = checkpoint(state)
            if region == nil or hash == nil then
                context:set_variable("xol.wipe.blocked", "no checkpoint pair")
                return
            end
            if stage(state) == 0 then
                context:set_variable("xol.wipe.cycle", (state:variable("xol.wipe.cycle") or 0) + 1)
                context:set_variable("xol.wipe.stage", 1)
                context:set_variable("xol.wipe.seconds", 3)
                report(context, 1)
                countdown(context, 3)
                context:start_timer(timer(state), 1000)
            end
        end,

        timer = function(context, state, event)
            if event.timer_name == "xol.wipe.retry" then
                if stage(state) ~= 2 then return true end
                local tries = (state:variable("xol.wipe.tries") or 0) + 1
                context:set_variable("xol.wipe.tries", tries)
                context:set_phase(510 + tries)
                local region, hash = checkpoint(state)
                if tries > 3 then
                    region = state:variable("xol.spawn.fallback.region") or region
                    hash = state:variable("xol.spawn.fallback.hash") or hash
                end
                if tries <= 8 then
                    context:set_variable("xol.wipe.request", (context:restart_checkpoint{
                        region = region, spawn_set_hash = hash}).value)
                    context:start_timer("xol.wipe.retry", 5000)
                end
                return true
            end
            if event.timer_name ~= timer(state) then return false end
            if stage(state) ~= 1 then return true end
            if not state:variable("xol.wipe.all_dead") then
                cancel(context, state); return true
            end
            local remaining = state:variable("xol.wipe.seconds") - 1
            context:set_variable("xol.wipe.seconds", remaining)
            countdown(context, remaining)
            if remaining > 0 then
                context:start_timer(timer(state), 1000)
            else
                context:set_variable("xol.wipe.stage", 2)
                report(context, 2)
                local region, hash = checkpoint(state)
                context:set_variable("xol.wipe.request", (context:restart_checkpoint{
                    region = region, spawn_set_hash = hash}).value)
                context:start_timer("xol.wipe.retry", 5000)
            end
            return true
        end,

        client_state = function(context, state, event)
            if stage(state) < 2 or event.spawn_state == nil then return end
            if stage(state) == 2 and event.spawn_state >= 2 then
                local region, hash = checkpoint(state)
                route.reset(context, state)
                context:set_variable("xol.wipe.stage", 3)
                report(context, 3)
                context:restart_checkpoint{region = region, spawn_set_hash = hash,
                    release_request = state:variable("xol.wipe.request")}
            end
            if stage(state) == 3 and event.spawn_state == 0 then cancel(context, state) end
        end,

        effect = function(context, state, event)
            if event.request_key and event.request_key.value == state:variable("xol.wipe.request")
                and event.outcome ~= "transport_staged" then cancel(context, state) end
        end,
    }
end
end)()

-- ============================================================================
-- ENTRY POINT
-- Loads the generated SDK module, wires the modules above together and returns the
-- program table the runtime calls. Event routing only; every decision is above.
-- ============================================================================
local missions = require("missions")
local mission = require(assert(missions.STRIKE_XOL, "strike_xol SDK module is absent"))

local START_STATE = "STATE_80F7356D_0001_0000_80F73562" -- bubble 1, region 8

local route = MOD_route(mission)
local support = MOD_support(mission, function(c, s, name)
    route.cleared(c, s, name)
end)
route.bind(support)
local wipe = MOD_wipe(mission, route)

local function playable(state)
    return not wipe.active(state) and state:variable("xol.complete") ~= true
end

return {
    initial_state = START_STATE and assert(mission.states[START_STATE],
                                           "strike_xol: unknown start state " .. START_STATE),

    on_event_client_state_changed = function(context, state, event)
        pcall(function()
            local seen = (state:variable("xol.ev.client") or 0) + 1
            context:set_variable("xol.ev.client", seen)
            if event.spawn_state ~= nil then
                context:set_variable("xol.ev.spawn_state", event.spawn_state)
                local trail = state:variable("xol.ev.spawn_trail") or ""
                if #trail < 60 then
                    context:set_variable("xol.ev.spawn_trail", trail .. event.spawn_state .. ",")
                end
            end
        end)
        wipe.client_state(context, state, event)
        if not playable(state) then return end
        local region = event.held_region_index or event.current_region_index
        if region ~= nil then context:set_variable("xol.region", region) end
        route.client(context, state, event)
    end,

    on_event_player_trigger = function(context, state, event)
        if not playable(state) then return end
        route.trigger(context, state, event)
    end,

    on_event_object_interacted = function(context, state, event)
        if not playable(state) then return end
        route.interaction(context, state, event)
    end,

    on_event_ghost_link_state = function(context, state, event)
        if not playable(state) then return end
        route.ghost_link(context, state, event)
    end,

    on_event_squad_state = function(context, state, event)
        if wipe.active(state) then return end
        route.squad(context, state, event)
    end,

    on_event_timer_elapsed = function(context, state, event)
        if wipe.timer(context, state, event) or wipe.active(state) then return end
        route.timer(context, state, event)
    end,

    on_event_object_state = function(context, state, event)
        if not playable(state) then return end
        route.object(context, state, event)
    end,

    on_event_actor_path_state = function(context, state, event)
        if not playable(state) then return end
        route.actor_path(context, state, event)
    end,

    on_event_entity_spawned = function(context, state, event)
        pcall(function()
            context:set_variable("xol.ev.spawned", (state:variable("xol.ev.spawned") or 0) + 1)
        end)
        if not playable(state) then return end
        pcall(function() route.spawned(context, state, event) end)
    end,

    on_event_damage_state = function(context, state, event)
        if not playable(state) then return end
        route.damage(context, state, event)
    end,

    on_event_scene_finished = function(context, state, event)
        pcall(function()
            local seen = (state:variable("xol.ev.scene") or 0) + 1
            context:set_variable("xol.ev.scene", seen)
            context:set_variable("xol.ev.scene_last",
                tostring(event.slot_type) .. "/" .. tostring(event.slot_index) ..
                " tag=" .. tostring(event.object_tag))
        end)
        if not playable(state) then return end
        local ok, err = pcall(function() route.scene_finished(context, state, event) end)
        if not ok then context:set_variable("xol.ev.scene_error", tostring(err)) end
    end,

    on_event_fireteam_state = function(context, state, event)
        pcall(function()
            context:set_variable("xol.ev.fireteam", (state:variable("xol.ev.fireteam") or 0) + 1)
            context:set_variable("xol.ev.fireteam_last",
                tostring(event.dead_count) .. "/" .. tostring(event.alive_count) ..
                "/" .. tostring(event.unknown_count))
        end)
        local ok, err = pcall(function() wipe.fireteam(context, state, event) end)
        if not ok then context:set_variable("xol.ev.fireteam_error", tostring(err)) end
    end,
    on_event_effect_result = function(context, state, event)
        wipe.effect(context, state, event)
        if playable(state) then route.effect(context, state, event) end
    end,
}
