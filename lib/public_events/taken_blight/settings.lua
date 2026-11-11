-- Taken Blight content parameters and reconstructed policy; state keys remain host-scoped.
-- Timings marked "reference" are read from one retail Io recording and remain reconstructed
-- family timing policy. The shared skeleton owns the lifecycle,
-- membership, heroic, reward and incoming keys under the same prefix.
local c = {}

-- Retained keys preserve a running attempt across script reloads; "tb" is the event prefix.
c.KEY = "tb"
-- Location index, the move in progress, Blight Integrity and the final-location window.
c.LOCATION_KEY, c.PURSUING_KEY, c.INTEGRITY_KEY, c.FINAL_KEY = "tb.l", "tb.mv", "tb.i", "tb.f"
-- One live flag and one placement request per squad index of the current location.
c.SQUAD_LIVE_KEY, c.SQUAD_REQUEST_KEY = "tb.s", "tb.q"
c.ULTRA_KEY, c.ULTRA_REQUEST_KEY = "tb.u", "tb.uq"
c.BLIGHT_REQUEST_KEY, c.DAMAGE_REQUEST_KEY = "tb.b", "tb.dq"
-- The monitored location, and that it reported a live Blight before any zero is believed.
c.WATCHED_KEY, c.HEALTH_SEEN_KEY = "tb.w", "tb.hs"

-- Family timers remain distinct from the shared lifecycle, incoming and rally timers.
c.ARRIVE_TIMER, c.FIGHT_TIMER, c.FINAL_TIMER = "tba", "tbg", "tbf"

-- Most squads any location places: floater, anchor and three tethers.
c.MAX_SQUADS = 5

-- Reference clocks: the marker reads 2:56 about 4 s after the start, each move resets the clock
-- to about 2:30 and the Blightmaker row starts near 2:30.
c.EVENT_SECONDS, c.PURSUE_SECONDS, c.HEROIC_SECONDS = 180, 150, 150

-- Reference incoming timing: the alert plays with the incoming row, the Blight's beam lands
-- about 7 s later and the marker clock starts about 4-6 s after that.
c.INTRO_AFTER_LEAVE_MS, c.ALERT_AFTER_INTRO_MS = 1000, 5000
c.ARRIVE_AFTER_ALERT_MS, c.START_AFTER_ARRIVE_MS = 7000, 6000

-- Reference moves: the next Blight's beam lands about 14 s after the row changes and the fight
-- row returns within about 6 s, with no player nearby. No arrival report is exposed.
c.ARRIVE_MS, c.FIGHT_AFTER_ARRIVE_MS = 13000, 6000

-- Reference final location: the Blight still stood for at least 8 s at 0% before the heroic
-- join. The normal ending itself was not observed, so this window is reconstructed.
c.FINAL_WINDOW_MS = 12000

-- The row shows Blight Integrity as a percentage.
c.INTEGRITY_MAX = 100

-- The existing freeroam service owns this zone clock and must match its cadence.
c.TICK_SECONDS = 5

-- Cue indexes in the authored dialogue sensor. Alert, start and heroic were heard in the
-- reference; move and the normal and failure roles follow the authored lines and the cue layout
-- of the other families. Heroic success was heard at the chest.
c.CUE_ALERT, c.CUE_START, c.CUE_HEROIC, c.CUE_FAILED = 0, 1, 2, 3
c.CUE_MOVE, c.CUE_SUCCESS, c.CUE_HEROIC_SUCCESS, c.CUE_HEROIC_FAILED = 4, 5, 6, 7

-- Reconstructed music section selections.
c.MUSIC_ACTIVE, c.MUSIC_HEROIC = 0, 1

return c
