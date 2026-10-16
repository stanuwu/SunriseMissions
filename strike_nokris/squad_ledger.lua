-- One record owns the transported placement and combat job for one native squad lifetime.
local record = require("strike_nokris.state_record")
local schema = record.schema("S1", {
    {name="transported", kind="boolean"},
    {name="registration_lost", kind="boolean"},
    {name="source", kind="string", limit=20},
    {name="generation", kind="integer"},
    {name="spawn_generation", kind="integer"},
    {name="revision", kind="integer"},
    {name="group", kind="integer"},
})
local ledger = {}

function ledger.get(state, key, field)
    return record.get(state, key, schema, field)
end

function ledger.set(context, state, key, field, value)
    record.set(context, state, key, schema, field, value)
end

function ledger.adopt(context, key, source, counter, generation, revision, group)
    record.write(context, key, schema, {transported=true, source=source, generation=counter,
        spawn_generation=generation, revision=revision, group=group})
end

return ledger
