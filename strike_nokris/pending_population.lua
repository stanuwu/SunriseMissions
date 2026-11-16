-- Bounded copies of typed Sense events awaiting their owned placement receipt.
-- No userdata or native view survives the callback; producer counters are checked on replay.
local fields={"object_tag","registry_key","slot_type","slot_index","source_generation",
    "spawn_generation","sense_generation","population_available","alive_count",
    "objective_revision","registration_reset"}
local pending={}
function pending.push(queue,event)
    local last=queue[#queue]
    if last and last.spawn_generation==event.spawn_generation and last.sense_generation==event.sense_generation then
        for _,field in ipairs(fields) do
            if last[field]~=event[field] then return false,"early_population_conflict" end
        end
        for task=1,5 do
            if last.task_costs[task]~=(event.task_costs and event.task_costs[task]) then
                return false,"early_population_conflict"
            end
        end
        return true
    end
    if #queue==8 then return false,"early_population_capacity" end
    local copy={task_costs={}}
    for _,field in ipairs(fields) do copy[field]=event[field] end
    for task=1,5 do copy.task_costs[task]=event.task_costs and event.task_costs[task] end
    queue[#queue+1]=copy
    return true
end
return pending
