# Regenerate: python3 -m venv .venv && .venv/bin/pip install skyfield==1.55 && .venv/bin/python tools/astronomy/reference_values.py > Packages/PanGalacticCore/Tests/PanGalacticCoreTests/Fixtures/astronomy/reference.json
"""Reference values for the M4.1 astronomy engine, from the JPL DE421 ephemeris via Skyfield.

Definitions match the spec: Sun events are crossings of the Sun's centre (geometric, topocentric
altitude, no refraction) through -0.833, -6, -12, -18 deg; Moon rise/set is the geocentric altitude
of the Moon's centre crossing +0.125 deg (Meeus ch. 15). Night window: local noon to next local noon.
"""
import json, sys
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo
import numpy as np
from skyfield.api import load, wgs84, Star
from skyfield import almanac
from skyfield.searchlib import find_discrete

ts = load.timescale()
eph = load('de421.bsp')
earth, sun, moon = eph['earth'], eph['sun'], eph['moon']

SITES = [
    ("central-europe-november", 50.0, 8.0, 0.0, "Europe/Berlin", "2026-11-19"),
    ("north-midsummer", 58.0, 12.0, 0.0, "Europe/Stockholm", "2026-06-21"),
    ("equator-equinox", 0.0, 30.0, 0.0, "Africa/Kampala", "2026-03-20"),
    ("south-winter", -34.0, 151.0, 0.0, "Australia/Sydney", "2026-07-15"),
    ("arctic-polar-night", 70.0, 20.0, 0.0, "Europe/Oslo", "2026-12-21"),
]
M31 = Star(ra_hours=(0, 42, 44.0), dec_degrees=(41, 16, 7.0))

def iso(t):
    return t.utc_datetime().replace(microsecond=0).strftime("%Y-%m-%dT%H:%M:%SZ")

def geocentric_alt(t, body, lat, lon):
    ra, dec, _ = earth.at(t).observe(body).apparent().radec(epoch='date')
    lst = (t.gast + lon / 15.0) % 24
    ha = np.radians((lst - ra.hours) * 15)
    la, de = np.radians(lat), dec.radians
    return np.degrees(np.arcsin(np.sin(la) * np.sin(de) + np.cos(la) * np.cos(de) * np.cos(ha)))

def topo_alt(t, body, site):
    alt, az, _ = (earth + site).at(t).observe(body).apparent().altaz()
    return alt.degrees, az.degrees

def crossings(f, t0, t1, threshold):
    def above(t):
        return f(t) > threshold
    above.step_days = 1 / 144
    times, values = find_discrete(t0, t1, above)
    return [(iso(t), "rise" if v else "set") for t, v in zip(times, values)]

def next_full(t):
    times, phases = almanac.find_discrete(t, ts.tt_jd(t.tt + 31), almanac.moon_phases(eph))
    return next(iso(x) for x, p in zip(times, phases) if p == 2)

out = []
for name, lat, lon, elev, tzname, date in SITES:
    tz = ZoneInfo(tzname)
    d = datetime.fromisoformat(date)
    start = datetime(d.year, d.month, d.day, 12, tzinfo=tz)
    end = start + timedelta(days=1)
    t0, t1 = ts.from_datetime(start), ts.from_datetime(end)
    site = wgs84.latlon(lat, lon, elevation_m=elev)
    sun_alt = lambda t: topo_alt(t, sun, site)[0]
    events = {}
    for label, h in [("horizon", -0.833), ("civil", -6.0), ("nautical", -12.0), ("astronomical", -18.0)]:
        events[label] = crossings(sun_alt, t0, t1, h)
    moon_events = crossings(lambda t: geocentric_alt(t, moon, lat, lon), t0, t1, 0.125)
    # Snapshot at 21:00 local
    snap = ts.from_datetime(datetime(d.year, d.month, d.day, 21, tzinfo=tz))
    s_ra, s_dec, _ = earth.at(snap).observe(sun).apparent().radec(epoch='date')
    s_alt, s_az = topo_alt(snap, sun, site)
    m_ra, m_dec, m_dist = earth.at(snap).observe(moon).apparent().radec(epoch='date')
    m_alt, m_az = topo_alt(snap, moon, site)
    illum = almanac.fraction_illuminated(eph, 'moon', snap)
    t_alt, t_az, _ = (earth + site).at(snap).observe(M31).apparent().altaz()
    t_ra, t_dec, _ = earth.at(snap).observe(M31).apparent().radec(epoch='date')
    sep = earth.at(snap).observe(moon).apparent().separation_from(earth.at(snap).observe(M31).apparent()).degrees
    # Meridian transit of M31 in the window
    def m31_ha_positive(t):
        ra, _, _ = earth.at(t).observe(M31).apparent().radec(epoch='date')
        lst = (t.gast + lon / 15.0) % 24
        return ((lst - ra.hours + 12) % 24 - 12) > 0
    m31_ha_positive.step_days = 1 / 48
    tt, vv = find_discrete(t0, t1, m31_ha_positive)
    transit = [iso(t) for t, v in zip(tt, vv) if v]
    out.append({
        "name": name, "latitude": lat, "longitude": lon, "elevation": elev, "timeZone": tzname,
        "nightStart": iso(t0), "nightEnd": iso(t1),
        "sun": {k: [{"time": t, "direction": dirn} for t, dirn in v] for k, v in events.items()},
        "moon": [{"time": t, "direction": dirn} for t, dirn in moon_events],
        "snapshot": {
            "time": iso(snap),
            "sun": {"ra": round(s_ra._degrees, 4), "dec": round(s_dec.degrees, 4), "altitude": round(s_alt, 4), "azimuth": round(s_az, 4)},
            "moon": {"ra": round(m_ra._degrees, 4), "dec": round(m_dec.degrees, 4), "distanceKm": round(m_dist.km, 0),
                     "altitude": round(m_alt, 4), "azimuth": round(m_az, 4), "illuminated": round(float(illum), 4)},
            "m31": {"raOfDate": round(t_ra._degrees, 4), "decOfDate": round(t_dec.degrees, 4),
                    "altitude": round(t_alt.degrees, 4), "azimuth": round(t_az.degrees, 4), "moonSeparation": round(float(sep), 3)},
        },
        "m31Transit": transit,
        "nextFullMoon": next_full(snap),
    })

json.dump({
    "source": "JPL DE421 ephemeris via Skyfield 1.55, generated 2026-11-20; sunrise/sunset and civil twilight of the first site cross-checked against the U.S. Naval Observatory API (aa.usno.navy.mil)",
    "definitions": "Sun: topocentric geometric altitude of the centre crossing -0.833/-6/-12/-18 deg. Moon rise/set: geocentric altitude of the centre crossing +0.125 deg. Snapshot altitudes: topocentric, apparent, no refraction. RA/Dec: apparent, equinox of date, geocentric. M31: J2000 00h42m44s +41d16'07\". Night window: local noon to next local noon.",
    "sites": out,
}, sys.stdout, indent=2)
