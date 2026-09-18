-- Caller must first match the exact squad identity and current observation generation.
-- The client supplies costs and executes the authored tasks. This module only selects a group.
local objective = {}

function objective.choose(event, authored_count, current_group, requested_revision)
    if authored_count < 1 or authored_count > 24 or authored_count % 1 ~= 0 then
        return nil
    end
    if requested_revision < 1 or event.objective_revision ~= requested_revision
        or not event.task_costs then
        return nil
    end

    local selected, minimum = -1, 2040
    for ordinal = 0, authored_count - 1 do
        local cost = event.task_costs[ordinal + 1]
        -- A partial delta cannot prove the minimum or that every task is saturated.
        -- Wait for a complete authored vector; explicit zero remains a valid cost.
        if not cost or cost ~= cost or cost < 0 or cost > 2040 then
            return nil
        end
        if cost < minimum then
            selected, minimum = ordinal, cost
        end
    end
    if selected >= 0 and current_group >= 0 and current_group < authored_count
        and current_group % 1 == 0 and event.task_costs[current_group + 1] == minimum then
        selected = current_group
    end
    return selected
end

-- Upstream assigns objectives on the squad's slot with generated task-group handles and gates
-- revisions natively, so the script-side revision arguments are gone.
--- @return The generated task groups of an objective slot and how many it authors.
function objective.groups(mission, target)
    local name = string.upper(target.name)
    local groups = assert(mission.TaskGroup[name], "no task groups for " .. name)
    local count = 0
    while groups["GROUP_" .. count] ~= nil do count = count + 1 end
    return groups, count
end

function objective.count(mission, target)
    local _, count = objective.groups(mission, target)
    return count
end

--- Assigns the objective; a negative group binds the objective without a task group.
function objective.assign(context, mission, squad_slot, target, group)
    local task_group
    if group and group >= 0 then
        task_group = assert(objective.groups(mission, target)["GROUP_" .. group], "task group " .. group)
    end
    return context:slot(squad_slot):assign_combat_objective{objective = target, task_group = task_group}
end

return objective
