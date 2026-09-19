# Campaign kit

`lib/campaign` turns one declarative table into a complete mission script. A mission file says
*what* happens: where the player goes, which goal shows, which squads, scenes, beats and cutscenes
play, and what ends each step. The kit does the rest: event handlers, durable progress, trigger
arming, reattach, wipes and replays, and mission completion. A mission file holds no `on_event_*`
handler.

- [Writing a mission](#writing-a-mission)
- [Content reference](#content-reference)
- [How a mission runs](#how-a-mission-runs)
- [Examples](#examples)
- [Extending the kit](#extending-the-kit)

## Writing a mission

A mission lives in `<activity>/<activity>.lua` and returns `campaign.new{...}`:

```lua
local missions = require("missions")
local mission = require(missions.MISSION_TOWERFALL)
local campaign = require("lib.campaign")
local unit, line = campaign.unit, campaign.line
local Slot, Squad, Directive = mission.Slot, mission.Squad, mission.Directive
local cue = mission.DialogueCue.M_DIALOG_SENSOR_80B50913

return campaign.new{
    key = "towerfall",
    directive_sensor = Slot.M_DIRECTIVE_SENSOR_80B50913,
    dialogue_sensor = Slot.M_DIALOG_SENSOR_80B50913,
    legs = {...},
    steps = {...},
    encounters = {...},
}
```

Rules:

- Every identity comes from the generated `missions` module: slots, squads, scenes, states,
  directives, dialogue cues. Spawn set hashes are the only literals, since the SDK does not name
  them.
- `campaign.new` checks the whole table when the script loads. A step that ends on a trigger no leg
  arms, a scene with no event keys or a sequence with two waits fails with a message naming it.
- Long missions can split their content into helpers: `require("<activity>.<helper>")`.

## Content reference

### Mission

| field | meaning |
|---|---|
| `key` | prefix of every variable and timer the mission owns; keep it short and unique |
| `directive_sensor` | type-68 slot the goals are shown through |
| `dialogue_sensor` | type-53 slot the lines play through; needed as soon as anything has `lines` |
| `music_sensor` | type-11 slot the music plays through; needed as soon as anything has `music` |
| `legs` | the regions the mission crosses, in play order; the first is where it starts |
| `steps` | the goal chain, in order |
| `encounters` | squads and beats placed when their step has started and their volume reported |
| `intro` | opening cutscenes `{state, cinematic}` played before the first leg, spawn held |
| `spawn_set` | spawn set hash the arrival filters its points by |
| `omit` | object slots kept out of every seed until something activates them |
| `finish` | `function(context)` run once the last step ends, before the mission completes |

### Legs

```lua
{id = "ship", state = mission.states.<STATE>, arm = {<type-31 slots>}, watch = {<type-30 slots>},
    spawn_set = 0x2EA8FB98}
```

A leg arms its triggers and watches its monitors when the client reaches its region. `spawn_set`
makes a wipe in that region restart the party at that set.

### Steps

| field | meaning |
|---|---|
| `id` | unique name |
| `directive`, `navpoint`, `waypoint` | the goal and its map marker; inside the waypoint volume the marker hides |
| `lines` | `{line(cue), line(cue, filter_volume)}` played when the step starts |
| `ends` | what finishes the step, see below; a step with no end finishes at once |
| `barrier = true` | only the step's own end finishes it; otherwise any later step's trigger, monitor or region also does |
| `revisit = true` | the step's triggers are armed again when it starts and count only from then |
| `checkpoint = true` | a wipe from here on replays this step and what follows; what came before stays done |
| `scenes`, `cutscene`, `sequence`, actions | see below; they run when the step starts |
| `scene` | a scene id activated with no bind and no keys (plain activation) |
| `on_start` | `function(context)` escape hatch, run last |

`ends` accepts any of these; the first to hold finishes the step:

| end | holds when |
|---|---|
| `trigger = slot` or a list | the player crossed the volume |
| `monitor = slot` or a list | a player entered the type-30 volume |
| `region = "<leg id>"` | the client reached that leg |
| `clear = "<encounter id>"` or a list | every squad of those encounters is gone |
| `ghost_link = slot` | the Ghost scan started and completed |
| `interact = slot` | the object was used (its interaction row is sent when the step starts) |
| `scene = slot` | the type-43 scene slot reported finished |
| `health = {slot = slot, at = 0.5}` | the combatant's health fell to that fraction |
| `destroyed = {slots}` | every listed object was destroyed |
| `sequence = true` | the step's own sequence finished |
| `cutscene = true` | the step's own cutscene ended |
| `spoken = cue` | the cue, played by the script, finished in this attempt |

### Encounters

```lua
{id = "hangar", after = "find", trigger = Slot.PT_HANGAR_SPAWN, objective = Slot.OBJ_HANGAR,
    squads = {unit(Squad.SQ_HANGAR_A_A, Slot.SQ_HANGAR_A_A)}, lines = {...}}
```

An encounter places once its `after` step has started (default: the arrival) and its `trigger` or
`monitor` has reported. A report that came earlier counts, so an encounter never misses its volume.
`objective` is assigned to every squad before it is placed. Encounters also take `scenes`,
`cutscene`, `sequence`, actions and `on_start`, run when they place.

`unit(squad, source, group, count)` places every member lane at `count` instead of the package
default, for a squad whose scene needs its full cast.

`groups = mission.TaskGroup.<OBJECTIVE>` (with `objective`) sends each squad to the task group that costs
the least: on every squad state the client reports the cost of each group, the squad moves when another
group is cheaper and stays put on a tie. Without `groups` a squad keeps the group it was assigned.

`approach = mission.TaskGroup.<OBJECTIVE>.GROUP_<n>` (with `objective`, instead of `groups`) puts every
squad on that group from its placement and assigns it again, forcing a new evaluation, the first time
it reports alive in an attempt. The squad is never moved off it; use it for a group whose own
movement is the point, such as a Legionary's jetpack approach.

`hold = true` (with `groups`) places the squads on no group: they stand where they are placed until a
sequence item or step carries `release = {"<encounter id>"}`, after which the pathing routes them.

An `objective` with neither `groups` nor `approach` leaves each squad on no group for good: its combat
AI picks its own moves, which is how some authored behaviours play, such as a Centurion jetting up to
face the player.

### Scenes

```lua
scenes = {{scene = mission.scenes.SC_CENTURION_INTRO, bind = {Slot.SQ_CENTURION_INTRO_CELL_1}}}
```

| field | meaning |
|---|---|
| `scene` | a `mission.scenes` entry |
| `bind` | type-2 cells of the scene's combatant participants; the bind makes the scene spawn its own actor, so never pose them first |
| `keys` | event keys sent once the activation reaches transport; default: the scene's authored keys; `{}` sends none |
| `spawn = true` | asks the runtime to prepare the whole cast; it refuses a scene with a participant that has no type-2 cell |

### Sequences

A `sequence` orders beats inside a step or an encounter. It begins with its holder. Each item waits
for at most one event, then for its delay, then acts:

| wait | holds when |
|---|---|
| `on = slot` | the trigger or monitor reported; a report before the item is reached counts |
| `finished = slot` | the scene slot reported finished after the previous item acted |
| `interacted = slot` | the object reported a use after the previous item acted |
| `cleared = "<encounter id>"` or a list | every squad of those encounters is gone |
| `spoken = cue` | the cue, played by the script, finished in this attempt; a finish before the item is reached counts |
| `after_ms = n` | n milliseconds passed after the wait held |

An item acts with `lines`, `scenes`, `cutscene`, any action, then `run(context, state)`.

### Actions

Steps, encounters and sequence items can all carry these:

| action | does |
|---|---|
| `move = {to = "open", slots = {...}, snap = true}` | applies a device transition to each type-23 slot |
| `objects = {slots = {...}, active = false}` | activates or removes type-4 objects |
| `signal = {scene = mission.scenes.X, keys = {...}}` | sends keys to a scene that is already active |
| `stop = {mission.scenes.X, ...}` | ends each scene's generation and releases its actors |
| `music = 8`, `music = {section = 8, enabled = false}` | selects or clears a section of the mission's music |
| `retire = {Squad.X, ...}` | removes every member of each squad |
| `perform = {cells = {...}, sequence = "SYMBOL"}` | creates each type-2 cell's actor playing that sequence of its own action table, looked up by symbol; the actor's combat AI takes over when it ends |
| `assign = {objective = slot, group = task group, squads = {unit(...)}}` | gives squads already alive that group, with no new evaluation, which would move them onto their task |
| `place = {objective = slot, groups = task groups, squads = {unit(...)}}` | sequence items only: places squads later than the holder does, with the same objective and pathing as an encounter |
| `interact = {slots = {...}, active = false, used = false}` | offers or withdraws a use on type-4 objects; the row goes out used unless `used = false`, which a hold-to-use object needs |

### Cutscenes

```lua
cutscene = {state = mission.states.<cutscene state>, cinematic = Slot.<type-6 slot>,
    after = mission.states.<state to land in>}
```

The cutscene selects its state, starts the cinematic once the client holds it, stops it on its end
or a skip, then moves the client to `after`, where it lands on the default spawn. It has ended once
the client holds `after`. A cinematic plays only in the state that owns it, usually the ordinal-1
state of its bubble.

## How a mission runs

- **Arrival.** The mission starts in the first leg, or in the first `intro` cutscene. The arrival
  is the client's first report of holding the first leg's region.
- **Legs.** Reaching a leg's region arms its triggers and watches its monitors. An armed trigger
  reports once and is disarmed.
- **Steps.** One step at a time: it starts when the previous one finished, shows its goal, plays
  its lines, scenes, cutscene and actions, then waits for its end. The last step completes the
  mission.
- **Facts latch.** A volume report is remembered, so a step or an encounter reached later still
  sees it.
- **Durable state.** All progress lives in mission variables and named timers. A reattach resumes
  exactly where the mission was; a cutscene still playing is ended, not replayed.
- **Wipes.** When the whole party dies in a leg with a `spawn_set`, the party restarts there. The
  graphs hold still until the party is up again, then everything from the last checkpoint step
  replays. Before any checkpoint, the replay starts from the arrival. A new attempt clears every
  timer, so timed beats replay through their sequence.
- **Budget.** A mission has 512 variables and 32 timers. Every step, fact and sequence item uses a
  variable; each flow graph holds at most 64 steps and 64 facts.

## Examples

### A goal chain

```lua
legs = {
    {id = "underwatch", state = mission.states.STATE_80B500BC_0009_0000_80B500BB,
        arm = {Slot.PT_PLAYER_NEAR_SHAXX, Slot.PT_WEAPON_COMPLETE}},
},
steps = {
    {id = "home", directive = Directive.DEFEND_YOUR_HOME, navpoint = Slot.AP_IKORA,
        lines = {line(cue.CUE_1)}, ends = {trigger = Slot.PT_PLAYER_NEAR_SHAXX}},
    {id = "gear", directive = Directive.GEAR_UP_FOR_THE_FIGHT,
        ends = {trigger = Slot.PT_WEAPON_COMPLETE}},
},
```

### A fight that ends the step

```lua
steps = {
    {id = "plaza", directive = Directive.FIGHT_WITH_ZAVALA, ends = {clear = "plaza_hold"}},
},
encounters = {
    {id = "plaza_hold", after = "plaza", trigger = Slot.PT_PLAZA_SPAWN_INIT,
        objective = Slot.OBJ_PLAZA_KILL_CABAL, squads = {
            unit(Squad.SQUAD_KILL_CABAL_1, Slot.SQUAD_KILL_CABAL_1),
            unit(Squad.SQUAD_KILL_CABAL_2, Slot.SQUAD_KILL_CABAL_2),
        }},
},
```

### A scene with a combatant, played on a volume

```lua
encounters = {
    {id = "centurion", trigger = Slot.PT_CENTURION_INTRO_REINFORCE, scenes = {
        {scene = mission.scenes.SC_CENTURION_INTRO, bind = {Slot.SQ_CENTURION_INTRO_CELL_1}},
    }},
},
```

### A timed beat

The wall opens on `pt_start`, the Centurion scene plays on the reinforce volume, and two seconds
after it finishes a line plays; then the step ends and the next goal shows.

```lua
{id = "centurion", barrier = true, ends = {sequence = true}, sequence = {
    {on = Slot.PT_START, move = {to = "open", slots = {Slot.D_UNDERWATCH_COLLAPSING_WALL}}},
    {on = Slot.PT_CENTURION_INTRO_REINFORCE, scenes = {
        {scene = mission.scenes.SC_CENTURION_INTRO, bind = {Slot.SQ_CENTURION_INTRO_CELL_1}},
    }},
    {finished = Slot.SC_CENTURION_INTRO, after_ms = 2000, lines = {line(cue.CUE_5)}},
}},
```

Keys gated one by one, with delays, go through `signal` once the scene is active:

```lua
local shaxx = mission.scenes.SCENE_SHAXX
local key = shaxx.event_keys

sequence = {
    {on = Slot.PT_START_SHAXX_SCENE, scenes = {{scene = shaxx, keys = {key[1], key[2]}}}},
    {on = Slot.PT_WEAPON, signal = {scene = shaxx, keys = {key[4]}}},
    {after_ms = 4000, signal = {scene = shaxx, keys = {key[5]}}},
    {after_ms = 1500, signal = {scene = shaxx, keys = {key[3]}}},
},
```

### A cutscene between two areas, a checkpoint, and the ending

```lua
local SHIP = mission.states.STATE_80B500BC_0008_0000_80B500B8

legs = {
    {id = "bazaar", state = mission.states.STATE_80B500BC_0000_0000_80B500AD},
    {id = "ship", state = SHIP, spawn_set = 0x2EA8FB98},
},
steps = {
    {id = "boarding", barrier = true, ends = {cutscene = true}, cutscene = {
        state = mission.states.STATE_80B500BC_0008_0001_80B500B9,
        cinematic = Slot.MID_CINEMATIC_CINEMATIC, after = SHIP}},
    {id = "deck", checkpoint = true, directive = Directive.DISABLE_THE_SHIELDS,
        ends = {trigger = Slot.PT_DESTROY_BATTLESHIP}},
    {id = "outro", barrier = true, ends = {cutscene = true}, cutscene = {
        state = mission.states.STATE_80B500BC_0001_0001_80B500AF,
        cinematic = Slot.OUTRO_CINEMATIC_CINEMATIC}},
},
```

A wipe on the ship respawns the party at the ship's spawn set and replays `deck`: the goal shows
again. When the outro ends, the last step is done and the mission completes.

## Extending the kit

`campaign.new` assembles the mission from the capabilities listed in `campaign.capabilities`:

| capability | owns |
|---|---|
| `intro` | opening cutscenes and the held spawn |
| `core` | legs, steps, goals, the main chain and completion |
| `encounters` | squad placement, the `place` and `assign` actions and the `clear` end |
| `scenes` | `scenes` entries: bind, activation, event keys |
| `actions` | `move`, `objects`, `signal`, `stop`, `music`, `retire`, `interact`, `perform` |
| `sequence` | `sequence` and the `sequence` end |
| `cutscenes` | `cutscene` and the `cutscene` end |
| `checkpoints` | `spawn_set`, wipes and replays |
| `dialogue` | the `spoken` wait and end; needs a Sunrise build with `dialogue_finished` events |
| `pathing` | `groups`, `approach`, `hold` and the `release` action |

A capability is a module with a `name` and up to three passes. Each pass runs for every capability,
in list order, before the next pass starts:

```lua
local example = {name = "example"}

function example.check(content, builder) end    -- validate the fields this capability owns
function example.declare(content, builder) end  -- services, end kinds, wait kinds, actions
function example.build(content, builder) end    -- facts, graphs, handlers, start and load hooks

return example
```

| builder | use |
|---|---|
| `provide(name, service)`, `find(name)`, `need(name)` | share a service between capabilities |
| `action(field, fn(context, state, holder, value))` | what a field does on a step, an encounter or a sequence item; actions run in registration order |
| `run_actions(context, state, holder)` | run every action the holder carries |
| `end_kind(name, fn(step, value))` | a new `ends` field; `fn` returns the flow conditions that end the step |
| `wait_kind(name, fn(value))` | a new sequence wait; `fn` returns the flow condition that holds once it is met |
| `on(handler, fn(context, state, event))` | add a part to a runtime handler; parts run in capability order |
| `on_start(fn)`, `on_load(fn)` | run before the graphs advance on start or after a reattach |
| `graph(flow)` | add a flow graph; graphs handle and advance in the order added |
| `handle(...)`, `advance(...)` | drive every graph |
| `after_handle(fn)`, `hold(predicate)` | run after every graph handled an event; keep every graph still |
| `initial` | the `initial_state` table the runtime reads |

Rules for a capability:

- Keep no state in the module: everything belongs to the builder or to closures `build` creates.
- Register handlers, actions and end kinds only when the content uses the capability, so a mission
  that does not use it runs exactly as before.
- Store progress in mission variables under `content.key`, never in Lua tables, since a reattach
  rebuilds the VM.
