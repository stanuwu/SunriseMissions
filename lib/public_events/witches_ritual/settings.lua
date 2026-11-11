-- Witches' Ritual content parameters and reconstructed policy; state keys remain host-scoped.
-- "Observed" values are read from a 2018-03-26 heroic recording (youtu.be/xajO_cbLqXw, build
-- unrecorded); the remaining family timing is reconstructed policy.
-- The shared skeleton (lib.public_events.event) owns the lifecycle, membership, heroic, reward and
-- incoming keys under the same prefix.
local c = {}

-- Retained keys preserve a running attempt across script reloads; "w" is the event prefix.
c.KEY = "w"
-- Row stage (1 wizards, 2 portal open, 3 boss), wizards killed, placement and ended-generation
-- prefixes, live flag prefix, crystals destroyed, circle state, wave count and hop-on revision.
c.STAGE_KEY, c.KILLED_KEY, c.UNIT_KEY, c.ENDED_KEY = "w.sg", "w.k", "w.u", "w.e"
c.LIVE_KEY, c.CRYSTAL_KEY = "w.l", "w.cr"
c.HOP_REVISION_KEY, c.CIRCLE_KEY, c.WAVE_COUNT_KEY = "w.hr", "w.ci", "w.n"
c.PORTAL_COUNT_KEY = "w.pn"
-- Separate position intents keep plate occupancy independent of wizard lifetime.
c.PLATE_KEYS = {"w.pl1", "w.pl2"}
-- Charge level per plate while occupied, and the flag that the charge completed.
c.CHARGE_KEY, c.CHARGED_KEY = "w.ch", "w.cd"
-- Last requested immunity avoids redundant writes to each crystal hub.
c.CRYSTAL_SHIELD_KEY = "w.cs"
-- Reconstructed vacant/held positions stay inside the graph's charge/success bands.
-- Unsnapped travel from 0.1 to 1 takes 5.4 s at the authored 6 s full-range rate.
-- Five equal host steps play increment sequences; completion disrupts the matching shield.
c.PLATE_OFF, c.PLATE_VACANT, c.PLATE_OCCUPIED = 0, 0.1, 1
c.CHARGE_STEPS, c.CHARGE_STEP_MS = 5, 1080
c.STAGE_WIZARDS, c.STAGE_PORTAL, c.STAGE_BOSS = 1, 2, 3
c.WIZARD_COUNT = 2
-- Heroic opening thralls sent with the Champion: the first three of the six authored intro squads.
c.HEROIC_THRALLS = 3

-- Family timers remain distinct from the shared lifecycle and incoming timers.
c.INTRO_TIMER, c.WAVE_TIMER, c.BOSS_TIMER, c.JOIN_LINE_TIMER = "wi", "ww", "wb", "wj"
-- One charge timer per plate and one cadence for the portal.
c.CHARGE_TIMERS, c.PORTAL_TIMER = {"wc1", "wc2"}, "wp"

-- Observed clock: 3:56 about six seconds after joining. Heroic keeps the running clock (3:07 at the
-- heroic banner, 3:00 and 2:46 on the Champion row).
c.EVENT_SECONDS = 240

-- The existing freeroam service owns this zone clock and must match its cadence.
c.TICK_SECONDS = 5

-- Reconstructed delay between the flag leaving and the event joining; the recording starts at join.
c.START_AFTER_LEAVE_MS = 10000
-- Observed: the first line plays with the joined banner and the second about six seconds later.
c.JOIN_LINE_DELAY_MS = 6000
-- Reconstructed delay before the authored active sequence follows the intro sequence.
c.INTRO_MS = 8000

-- Reconstructed wave cadence; a unit still alive when its group returns is skipped.
c.FIRST_WAVE_MS, c.WAVE_INTERVAL_MS = 15000, 30000
-- Wave groups as indexes into the site's Acolyte wave list, sent in order and repeated.
local SIGIL_1_GROUP_1, SIGIL_2_GROUP_1, SIGIL_1_GROUP_2, SIGIL_2_GROUP_2 = 1, 2, 3, 4
c.WAVE_GROUPS = {{SIGIL_1_GROUP_1, SIGIL_2_GROUP_1}, {SIGIL_1_GROUP_2, SIGIL_2_GROUP_2}}
-- Each plate's Knights arrive one at a time: the first when a player first stands on the plate
-- while its wizard lives (reconstructed trigger; retail's is unknown), the next when the standing
-- one dies, through the site's variants in order. No added respawn delay.
c.KNIGHT_KEY = "w.kn"
-- Reconstructed portal cadence; live squads are not replaced on a later turn.
-- Thrall use their portal rules and Cursed Thrall use their authored arena rules.
c.PORTAL_FIRST_MS, c.PORTAL_INTERVAL_MS = 4000, 8000
-- Portal groups as indexes into the site's portal list, sent in order and repeated.
local THRALL_1, THRALL_2, THRALL_3, CURSED_1, CURSED_2 = 1, 2, 3, 4, 5
c.PORTAL_GROUPS = {
    {THRALL_1, THRALL_2, THRALL_3}, {THRALL_1, THRALL_2, THRALL_3, CURSED_1},
    {THRALL_1, THRALL_2, THRALL_3}, {THRALL_1, THRALL_2, THRALL_3, CURSED_2},
    {THRALL_1, THRALL_2, THRALL_3}, {THRALL_1, THRALL_2, THRALL_3, CURSED_1},
}

-- Window between the portal opening and the Sorcerer: the authored heroic window timer
-- (at_heroic_window, 60 s) reused as the normal expiry. Observed: "Brace Yourself" at 3:24, the
-- heroic banner about 17 s later in a heroic recording, which does not show normal expiry.
c.BOSS_DELAY_MS = 60000

-- Cue indexes in the authored dialogue sensor. Observed: 0 with the joined banner, 1 six seconds
-- later, 6 ("Another day, another Knight") as the heroic ending began. Read from the authored
-- lines only: 2 "Portal destabilized", 3 and 4 the Hive withdrawing, 5 "Wizards down" (used for the
-- normal ending, unobserved), 7 a Knight beaten with the portal down. No heroic-failure line
-- exists, so failure stands in.
-- Cues 0 and 1 are the join lines the site passes to the skeleton.
c.CUE_ALERT, c.CUE_START, c.CUE_PORTAL, c.CUE_FAILED = 0, 1, 2, 3
c.CUE_SUCCESS, c.CUE_HEROIC_SUCCESS, c.CUE_HEROIC_FAILED = 5, 6, 3

-- Reconstructed pillar charge uses tenths; six runes stop at 0.6 below the flame bands.
-- Gateway position 0 selects standing; position 1 closes and destroys it.
-- These device appearance selections remain a qualified reconstruction.
c.ARTIFACT_KEYS, c.RUNE_KEY, c.GATEWAY_KEY = {"w.ar1", "w.ar2"}, "w.ru", "w.gw"
c.RUNES_PER_ARTIFACT = 6
c.PILLAR_OFF, c.PILLAR_STEP, c.PILLAR_FULL = 0, 0.1, 0.6
c.RUNE_OFF, c.RUNE_LIT = 0, 1
c.GATEWAY_STANDING = 0

-- Reconstructed music section selections.
c.MUSIC_ACTIVE, c.MUSIC_HEROIC = 0, 1

return c
