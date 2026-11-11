-- Spire content parameters and reconstructed policy; state keys remain host-scoped. The shared
-- skeleton (lib.public_events.event) owns the lifecycle, rally, membership, heroic, reward and
-- incoming keys under the same prefix.
local c = {}

-- Retained keys preserve a running attempt across script reloads; "e" is the event prefix.
c.KEY = "e"
c.WAVE_KEY = "e.w"
c.REQUEST_KEY = "e.q"
c.DEAD_KEY = "e.d"
c.SACRIFICE_KEY = "e.s"
c.CAPTURE_KEY = "e.c"
c.CHARGE_KEY = "e.cv"
c.CONFLUX_CHARGE_KEY = "e.cx"
c.LANE_STAGE_KEY = "e.ls"
c.WAVE_COUNT_KEY = "e.n"
c.DISRUPTOR_KEY = "e.x"
c.INTEGRATION_KEY = "e.i"
c.STREAM_REVISION_KEY = "e.r"
c.REPLACED_KEY = "e.rp"
c.ENDED_KEY = "e.eg"
c.LIVE_KEY = "e.lv"
c.SPIRE_REVISION_KEY = "e.sp"
c.BARRIER_SYNC_KEY, c.BARRIER_RUN_KEY = "e.bs", "e.br"
c.GUARD_KEY = "e.g"

-- Retain each lane's selection request and the placement it follows across reloads.
c.SELECTION_REQUEST_KEY, c.SELECTION_PLACEMENT_KEY = "e.k", "e.kp"

-- Selects the normal Goblin behavior definition containing the sacrifice action.
c.GOBLIN_SACRIFICE_KEY = 0x8ED36756

-- Incident row emitted by the authored sacrifice death-pattern branch.
c.SACRIFICE_INCIDENT = 2795

-- Family timers remain distinct from the shared lifecycle, incoming and rally timers.
c.INTRO_TIMER = "ei"
c.JOIN_LINE_TIMER = "ej"
c.REINFORCE_TIMER = "ew"

-- Lane stages distinguish a charging plate from a completed capture.
c.LANE_CHARGING, c.LANE_CAPTURED = 1, 2

-- Reconstructed capture thresholds send the second and third challenger squads.
c.SECOND_DISRUPTOR_PROGRESS, c.THIRD_DISRUPTOR_PROGRESS = 1 / 3, 2 / 3

-- Authored barrier ranges select red idle, white charge and withdrawal.
c.BARRIER_IDLE, c.BARRIER_WHITE, c.BARRIER_WITHDRAWN = 0.25, 0.15, 0.35

-- Control values select the pillar active range and completed retraction.
c.CONFLUX_ACTIVE, c.CONFLUX_COMPLETE = 0.55, 1

-- The authored plate charge duration; visual synchronization uses seconds.
c.PLATE_CHARGE_SECONDS = 45

-- Wave indexes address the ordered authored squad list in each site definition.
c.WAVE_GOBLINS, c.WAVE_HOBGOBLINS, c.WAVE_MINOTAURS = 1, 2, 3

c.WAVE_ARCHITECTOR_GOBLINS, c.WAVE_HYDRA = 4, 5

c.WAVE_HEADLESS_GOBLINS, c.WAVE_HEADLESS_MINOTAURS = 6, 7

c.WAVE_ARCHITECTOR_MINOTAURS, c.WAVE_ARCHITECTOR_HYDRA = 8, 9

-- Reconstructed normal wave schedule enables Minotaurs after one minute.
c.MINOTAURS_FROM_SECONDS = 60

-- Reconstructed normal wave schedule switches in the final minute.
c.FINAL_MINUTE_SECONDS = 60

-- Reconstructed wave order for the opening, middle, final and heroic portions.
c.OPENING_WAVES = {c.WAVE_GOBLINS}

c.MIDDLE_WAVES = {c.WAVE_GOBLINS, c.WAVE_MINOTAURS}

c.FINAL_WAVES = {c.WAVE_HOBGOBLINS, c.WAVE_GOBLINS, c.WAVE_HYDRA}

c.HEROIC_WAVES = {c.WAVE_HEADLESS_GOBLINS, c.WAVE_ARCHITECTOR_GOBLINS, c.WAVE_HEADLESS_MINOTAURS,
    c.WAVE_ARCHITECTOR_MINOTAURS, c.WAVE_ARCHITECTOR_HYDRA}

-- Reconstructed: guides describe heroic arriving from one direction, so these squads hold one lane.
c.HEROIC_SOLO_WAVES = {[c.WAVE_ARCHITECTOR_MINOTAURS] = true, [c.WAVE_ARCHITECTOR_HYDRA] = true}

-- Reconstructed: a lane sends this two-member wave while a big squad is out elsewhere.
c.HEROIC_SOLO_SUBSTITUTE = c.WAVE_GOBLINS

-- Reconstructed: heroic adds each lane's next wave this often, so one survivor cannot hold a lane.
c.REINFORCE_MS = 15000

-- Resynchronize visual progress after each tenth or any occupancy change.
c.BARRIER_SYNC_STEP = 0.1

-- Reconstructed heroic eligibility requires more than one minute remaining.
c.HEROIC_MIN_REMAINING_SECONDS = 60

-- Heroic mode resets the current deadline to 90 seconds.
c.HEROIC_SECONDS = 90

-- The freeroam service clock drives wave scheduling and replacement-removal guards.
c.TICK_KEY = "now"
c.TICK_SECONDS = 5

-- The authored spire control range from 0.5 to 0.6 selects destruction.
c.SPIRE_EXPLODE = 0.55

-- Failure policy selects the authored slow-dissolve range from 0.6 to 0.7.
c.SPIRE_DISSOLVE = 0.65

-- Cue indexes in the site dialogue sensor; roles are reconstructed from audible lines. The
-- sensor has no separate heroic failure line, so the normal one plays.
c.CUE_ALERT, c.CUE_START, c.CUE_HEROIC, c.CUE_FAILED = 0, 1, 2, 3
c.CUE_SUCCESS, c.CUE_HEROIC_SUCCESS = 5, 6
c.CUE_HEROIC_FAILED = c.CUE_FAILED

-- Reconstructed normal and heroic music section selections.
c.MUSIC_ACTIVE, c.MUSIC_HEROIC = 0, 1

-- Reference incoming timing after the flag leaves: five seconds to the beacon and build, six
-- seconds of the event row, five to the alert, seven to the start.
c.BEACON_AFTER_LEAVE_MS, c.ROW_SHOWN_MS = 5000, 6000
c.ALERT_AFTER_ROW_MS, c.START_AFTER_ALERT_MS = 5000, 7000

-- Reconstructed delay between the success line and the explosion; the skeleton owns the
-- banner, chest and grace delays that follow.
c.END_EXPLODE_MS = 5000

-- Normal Spire encounter duration is four minutes and thirty seconds.
c.EVENT_SECONDS = 270

-- No sequence-end report is exposed; active sequence delay remains reconstructed.
c.INTRO_MS = 8000

-- Completed sacrifices consume the initial integration allowance.
c.INTEGRATIONS = 10

-- The opening squad (class 0x80C0D08A, which binds the same lane program) is placed at the start
-- as authored. Set false to leave it out; its role in the central spawns is unproven.
c.PLACE_OPENING_SQUAD = true

-- Device indexes match the lane definition: pillar first, barrier second.
c.CONFLUX_DEVICE, c.BARRIER_DEVICE = 1, 2

return c
