-- Assembles a campaign mission from capabilities.
-- A capability is a table with a name and up to three passes, each run for every capability in
-- list order before the next pass starts:
--   check(content, builder)    validates the content fields it owns
--   declare(content, builder)  provides services, end kinds, wait kinds and holder actions
--   build(content, builder)    adds facts, graphs, handlers and start or load hooks
local builder = {}

local Builder = {}
Builder.__index = Builder

--- Publishes a service under a name, once.
function Builder:provide(name, service)
    assert(self.services[name] == nil, "campaign service provided twice: " .. name)
    self.services[name] = service
end

--- @return The named service, or nil when no capability provides it.
function Builder:find(name)
    return self.services[name]
end

--- @return The named service; a missing one is a content error.
function Builder:need(name)
    return assert(self.services[name], "campaign service missing: " .. name)
end

--- Registers an extra way for a step to end, named by its `ends` field.
--- @param options function(step, value) returning a list of flow conditions; any one ends the step.
function Builder:end_kind(name, options)
    assert(self.end_kinds[name] == nil, "campaign end kind registered twice: " .. name)
    self.end_kinds[name] = options
    self.end_kind_names[#self.end_kind_names + 1] = name
end

--- Registers an extra sequence wait, named by its item field.
--- @param condition function(value) returning a flow condition that holds once the wait is met.
function Builder:wait_kind(name, condition)
    assert(self.wait_kinds[name] == nil, "campaign wait kind registered twice: " .. name)
    self.wait_kinds[name] = condition
    self.wait_kind_names[#self.wait_kind_names + 1] = name
end

--- Registers what a holder field does when its step starts, its encounter places or its sequence
--- item acts.
--- @param field Content field on a step, an encounter or a sequence item, such as `scenes`.
--- @param run function(context, state, holder, value).
function Builder:action(field, run)
    assert(self.actions[field] == nil, "campaign action registered twice: " .. field)
    self.actions[field] = run
    self.action_fields[#self.action_fields + 1] = field
end

--- Runs every registered action whose field the holder carries, in registration order.
function Builder:run_actions(context, state, holder)
    for _, field in ipairs(self.action_fields) do
        local value = holder[field]
        if value ~= nil then self.actions[field](context, state, holder, value) end
    end
end

--- Adds one part to a runtime handler; parts run in capability order.
function Builder:on(handler, part)
    local parts = self.handlers[handler]
    if parts == nil then
        parts = {}
        self.handlers[handler] = parts
        self.handler_names[#self.handler_names + 1] = handler
    end
    parts[#parts + 1] = part
end

--- Adds a hook that runs on start, before the graphs advance.
function Builder:on_start(hook)
    self.start_hooks[#self.start_hooks + 1] = hook
end

--- Adds a hook that runs after a reattach, before the graphs advance.
function Builder:on_load(hook)
    self.load_hooks[#self.load_hooks + 1] = hook
end

--- Adds a flow graph; graphs handle and advance in the order they are added.
function Builder:graph(graph)
    self.graphs[#self.graphs + 1] = graph
end

--- Adds a hook that runs after every graph has handled an event.
function Builder:after_handle(hook)
    self.handle_hooks[#self.handle_hooks + 1] = hook
end

--- Adds a predicate that, while true, keeps every graph from handling or advancing.
function Builder:hold(predicate)
    self.holds[#self.holds + 1] = predicate
end

local function held(self, context, state)
    for _, predicate in ipairs(self.holds) do
        if predicate(context, state) then return true end
    end
    return false
end

--- Lets every graph observe one event, then runs the after-handle hooks.
function Builder:handle(context, state, event)
    if held(self, context, state) then return end
    for _, graph in ipairs(self.graphs) do graph:handle(context, state, event) end
    for _, hook in ipairs(self.handle_hooks) do hook(context, state, event) end
end

--- Advances every graph without an event.
function Builder:advance(context, state)
    if held(self, context, state) then return end
    for _, graph in ipairs(self.graphs) do graph:advance(context, state) end
end

local function compose(parts)
    if #parts == 1 then return parts[1] end
    return function(context, state, event)
        for _, part in ipairs(parts) do part(context, state, event) end
    end
end

--- Builds the table the runtime loads from a content declaration and a capability list.
function builder.assemble(content, capabilities)
    local self = setmetatable({
        services = {}, end_kinds = {}, end_kind_names = {},
        actions = {}, action_fields = {}, wait_kinds = {}, wait_kind_names = {},
        handlers = {}, handler_names = {}, start_hooks = {}, load_hooks = {}, graphs = {},
        handle_hooks = {}, holds = {},
        initial = {},
    }, Builder)
    for _, pass in ipairs({"check", "declare", "build"}) do
        for _, capability in ipairs(capabilities) do
            if capability[pass] ~= nil then capability[pass](content, self) end
        end
    end
    local program = {
        initial_state = self.initial,
        on_start = function(context, state)
            for _, hook in ipairs(self.start_hooks) do hook(context, state) end
            self:advance(context, state)
        end,
        on_load = function(context, state)
            for _, hook in ipairs(self.load_hooks) do hook(context, state) end
            self:advance(context, state)
        end,
    }
    for _, handler in ipairs(self.handler_names) do
        program[handler] = compose(self.handlers[handler])
    end
    return program
end

return builder
