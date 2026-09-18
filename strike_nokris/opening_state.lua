-- Opening-only storage mapping. Logical field names remain distinct from durable record keys.
local record=require("strike_nokris.state_record")
local crystal=record.schema("C1",{{name="observed",kind="boolean"},{name="live",kind="boolean"},
    {name="spawned",kind="boolean"},{name="transported",kind="boolean"},{name="entry",kind="integer"},
    {name="activation_revision",kind="integer"},{name="sense_generation",kind="integer"}})
local control=record.schema("O1",{{name="crystals_submitted",kind="boolean"},{name="crystals_failed",kind="boolean"},
    {name="cleanup_submitted",kind="boolean"},{name="cleanup_transported",kind="boolean"},
    {name="knight_placed",kind="boolean"},{name="failed",kind="boolean"}})
local latest=record.schema("L1",{{name="population_available",kind="boolean"},{name="alive",kind="integer"},
    {name="counter",kind="integer"},{name="spawn_generation",kind="integer"}})
local fields,field_names={},{}
local function bind(name,description)
    fields[name]=description
    field_names[#field_names+1]=name
end
for index=1,2 do
    for _,field in ipairs(crystal.fields) do
        bind("entry.crystal"..index.."."..field.name,
            {key="entry.crystal"..index,schema=crystal,field=field.name})
    end
end
for _,mapping in ipairs{{"crystals.submitted","crystals_submitted"},{"crystals.failed","crystals_failed"},
    {"cleanup.submitted","cleanup_submitted"},{"cleanup.transported","cleanup_transported"},
    {"knight.placed","knight_placed"},{"failed","failed"}} do
    bind("entry."..mapping[1],{key="entry.control",schema=control,field=mapping[2]})
end
for _,field in ipairs(latest.fields) do
    bind("entry.knight.reported_"..field.name,
        {key="entry.knight.latest",schema=latest,field=field.name})
end
local storage={}
function storage.owns(name) return fields[name]~=nil end
function storage.get(state,name)
    local field=assert(fields[name],"unknown opening packed field")
    return record.get(state,field.key,field.schema,field.field)
end
function storage.set(context,state,name,value)
    local field=assert(fields[name],"unknown opening packed field")
    record.set(context,state,field.key,field.schema,field.field,value)
end
function storage.valid(state)
    -- Old/partial scalar instances retain their evidence and may not submit fresh outputs.
    for _,name in ipairs(field_names) do if state:variable(name)~=nil then return false end end
    local ok=pcall(function()
        record.read(state,"entry.crystal1",crystal); record.read(state,"entry.crystal2",crystal)
        record.read(state,"entry.control",control); record.read(state,"entry.knight.latest",latest)
    end)
    return ok
end
return storage
