-- Witches' Ritual retains the encounter keys below across script reloads.
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

-- Heroic continues the running Wizard-phase clock.
c.EVENT_SECONDS = 240

-- The existing freeroam service owns this zone clock and must match its cadence.
c.TICK_SECONDS = 5

-- Reconstructed interval from flag withdrawal to the join.
c.START_AFTER_LEAVE_MS = 10000
-- The first join line plays with the banner; the second follows on this timer.
c.JOIN_LINE_DELAY_MS = 6000
-- Reconstructed delay before the authored active sequence follows the intro sequence.
c.INTRO_MS = 8000

-- Reconstructed wave cadence; a unit still alive when its group returns is skipped.
c.FIRST_WAVE_MS, c.WAVE_INTERVAL_MS = 15000, 30000
-- Wave groups as indexes into the site's Acolyte wave list, sent in order and repeated.
local SIGIL_1_GROUP_1, SIGIL_2_GROUP_1, SIGIL_1_GROUP_2, SIGIL_2_GROUP_2 = 1, 2, 3, 4
c.WAVE_GROUPS = {{SIGIL_1_GROUP_1, SIGIL_2_GROUP_1}, {SIGIL_1_GROUP_2, SIGIL_2_GROUP_2}}
-- Each plate calls its first Knight on entry while its Wizard lives.
-- The next variant replaces the Knight when it dies. The initial trigger is reconstructed.
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

-- The normal Sorcerer arrives when the authored at_heroic_window timer expires.
c.BOSS_DELAY_MS = 60000

-- Dialogue indexes 0 and 1 are the join lines. Both failure paths use cue 3.
-- The normal success cue is reconstructed.
c.CUE_ALERT, c.CUE_START, c.CUE_PORTAL, c.CUE_FAILED = 0, 1, 2, 3
c.CUE_SUCCESS, c.CUE_HEROIC_SUCCESS, c.CUE_HEROIC_FAILED = 5, 6, 3

-- Reconstructed pillar charge uses tenths; six runes stop at 0.6 below the flame bands.
-- Gateway position 0 selects standing; position 1 closes and destroys it.
c.ARTIFACT_KEYS, c.RUNE_KEY, c.GATEWAY_KEY = {"w.ar1", "w.ar2"}, "w.ru", "w.gw"
c.RUNES_PER_ARTIFACT = 6
c.PILLAR_OFF, c.PILLAR_STEP, c.PILLAR_FULL = 0, 0.1, 0.6
c.RUNE_OFF, c.RUNE_LIT = 0, 1
c.GATEWAY_STANDING = 0

-- Reconstructed music section selections.
c.MUSIC_ACTIVE, c.MUSIC_HEROIC = 0, 1

return c
