-- Taken Blight encounter settings.
local c = {}
c.NAME = "Taken Blight"

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

-- Relocating and summoning the Blightmaker each start a new deadline.
c.EVENT_SECONDS, c.PURSUE_SECONDS, c.HEROIC_SECONDS = 180, 150, 150

-- Reconstructed time from the alert to the beam, then from the beam to the first fight.
c.INTRO_AFTER_LEAVE_MS, c.ALERT_AFTER_INTRO_MS = 1000, 5000
c.ARRIVE_AFTER_ALERT_MS, c.START_AFTER_ARRIVE_MS = 7000, 6000

-- The host has no landing report. Timers sequence the beam and the next fight.
c.ARRIVE_MS, c.FIGHT_AFTER_ARRIVE_MS = 13000, 6000

-- Reconstructed window for the heroic trigger after the final location reaches zero integrity.
c.FINAL_WINDOW_MS = 12000

-- The row shows Blight Integrity as a percentage.
c.INTEGRITY_MAX = 100

-- The existing freeroam service owns this zone clock and must match its cadence.
c.TICK_SECONDS = 5

-- Dialogue sensor indexes for arrival, relocation and endings. The normal ending is reconstructed.
c.CUE_ALERT, c.CUE_START, c.CUE_HEROIC, c.CUE_FAILED = 0, 1, 2, 3
c.CUE_MOVE, c.CUE_SUCCESS, c.CUE_HEROIC_SUCCESS, c.CUE_HEROIC_FAILED = 4, 5, 6, 7

-- Reconstructed music section selections.
c.MUSIC_ACTIVE, c.MUSIC_HEROIC = 0, 1

return c
