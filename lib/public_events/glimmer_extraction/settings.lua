-- Glimmer Extraction content parameters and reconstructed policy; state keys remain host-scoped.
-- Timings marked "reference" are read from retail recordings of this event and remain
-- reconstructed family timing policy.
local c = {}

-- Retained keys preserve a running attempt across script reloads; "g" is the event prefix.
c.KEY = "g"
-- Attempt progress: site index, its stage and the extractor counter.
c.SITE_KEY, c.STAGE_KEY, c.DEFEATED_KEY = "g.si", "g.sg", "g.df"
-- Squad request keys carry the site index; a held key means the squad is live.
c.DROPSHIP_KEY, c.CREW_KEY, c.EXTRACTORS_KEY, c.CAPTAIN_KEY = "g.dp", "g.cr", "g.ex", "g.cp"
-- One machine per site: the generation last seen present and its destruction flag.
c.MACHINE_SEEN_KEY, c.MACHINE_GONE_KEY = "g.ms", "g.mg"
-- Heroic keys: wave request prefix, next wave, plate request, shown percent and completion.
c.WAVE_KEY, c.WAVE_COUNT_KEY, c.ZONE_REQUEST_KEY = "g.w", "g.wn", "g.qz"
c.PERCENT_KEY, c.CAPTURED_KEY = "g.pc", "g.cd"

-- Family timers remain distinct from the shared lifecycle, incoming and rally timers.
c.MACHINE_TIMER, c.RELOCATE_TIMER, c.WAVE_TIMER = "gm", "gr", "gw"

-- A site's fight runs extractors first, then their captain; relocating waits for the next crew.
c.STAGE_CREW, c.STAGE_CAPTAIN, c.STAGE_RELOCATING, c.STAGE_DEFEND = 1, 2, 3, 4

-- The directive counter reads "x of 4" at every site in the reference: three extractors and the
-- captain. Squad reports only name a cleared squad, so the counter moves in those two steps.
c.EXTRACTORS, c.CREW_TOTAL = 3, 4

-- Reference clock: 2:24 six seconds after the crew lands and again after each relocation, so
-- every site has its own deadline.
c.EVENT_SECONDS = 150
-- Reference heroic clock: 2:56 four seconds after the switch.
c.HEROIC_SECONDS = 180

-- Reference incoming timing: the alert plays with the flag still up, the ketch arrives 15 s later
-- and the event joins 8 s after that. The flag's departure time is not visible.
c.ALERT_AFTER_LEAVE_MS, c.KETCH_AFTER_ALERT_MS, c.START_AFTER_KETCH_MS = 2000, 15000, 8000

-- Reference: the next crew's clock appears 12-15 s after the "Pursue the Fallen" row.
c.RELOCATE_MS = 13000
-- Reference: the destructible machine transmats in "a few seconds" after the other equipment.
c.MACHINE_MS = 5000
-- The content authors four machine slots per site and the reference shows one target; which
-- slot is the live one is unrecovered, so this first authored slot is a reconstruction.
c.MACHINE_SLOT = 0

-- Reconstructed spacing of the authored heroic waves; only the plate ends the defense.
c.HEROIC_WAVE_MS = 30000

-- The plate reports 0 to 1. Its HUD counter reaches 100 and updates every 5 percentage points.
c.PLATE_FULL_PERCENT, c.PERCENT_STEP = 100, 5

-- Cue indexes in the authored dialogue sensor, matched to their authored lines; the alert,
-- start, first relocation, heroic and heroic success lines were seen in the reference.
c.CUE_ALERT, c.CUE_START, c.CUE_MOVED, c.CUE_MOVED_AGAIN = 0, 1, 2, 3
c.CUE_HEROIC, c.CUE_FAILED, c.CUE_SUCCESS = 4, 5, 6
c.CUE_HEROIC_SUCCESS, c.CUE_HEROIC_FAILED = 8, 9

-- Reconstructed music section selections.
c.MUSIC_ACTIVE, c.MUSIC_HEROIC = 0, 1

-- The existing freeroam service owns this zone clock and must match its cadence.
c.TICK_SECONDS = 5

return c
