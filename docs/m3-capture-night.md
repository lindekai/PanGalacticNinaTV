# M3 – Capture night checklist

One clear night covers the open M3 captures (#6, #7), the cooling question (#5) and the device check of the guiding chart. Everything here only reads; imaging is run by you in N.I.N.A. as usual. Commands and safety notes: [M0 test procedure](m0-test-procedure.md).

Replace `<HOST>` with the telescope PC's address. Do not commit it.

## Before dark

- [ ] TestFlight build 5 (guiding chart) is installed on the Apple TV.
- [ ] Sequence planned so that it contains, within the first hours: guiding start, a filter change, dithering (every 1–3 frames), and an autofocus run (trigger by filter change or time).
- [ ] PHD2 server enabled (*Tools → Enable Server*), N.I.N.A. Advanced API on port 1888.
- [ ] Mac on the same network, connected to power. Prevent sleep for the whole night: run the listeners under `caffeinate -i` (below) and keep the lid open.
- [ ] Reachability:
  ```sh
  nc -z -G 3 <HOST> 1888 && echo "Advanced API reachable"
  nc -z -G 3 <HOST> 4400 && echo "PHD2 reachable"
  ```
- [ ] Note versions: N.I.N.A., Advanced API plugin, PHD2, Windows.

## 1. Start the listeners (before cooling and before the sequence)

Two terminals, four hours each (`--seconds 14400`). The listeners do not reconnect: if one ends early (N.I.N.A. or PHD2 restarted, network drop), start it again with a new label.

```sh
caffeinate -i python3 tools/m0/m0probe.py ws   --host <HOST> --seconds 14400 --label m3-night
caffeinate -i python3 tools/m0/m0probe.py phd2 --host <HOST> --seconds 14400 --label m3-night
```

- [ ] Both terminals print events (PHD2 sends `Version`/`AppState` right away).

## 2. Cooling (#5)

- [ ] Start the camera cooldown in N.I.N.A. as usual, note the target temperature you chose.
- [ ] Snapshot while the ramp is running:
  ```sh
  python3 tools/m0/m0probe.py rest --host <HOST> --label cooling-ramp
  ```
- [ ] Snapshot after the ramp has finished and the temperature has settled:
  ```sh
  python3 tools/m0/m0probe.py rest --host <HOST> --label cooling-done
  ```
- [ ] Note: chosen target, the setpoint N.I.N.A. shows, the sensor temperature.

## 3. Guiding, dither, settle (#6)

Let it happen naturally; do not provoke failures on purpose.

- [ ] Guiding starts (calibration or reused calibration) and runs for at least 10 minutes.
- [ ] At least two dithers with settling.
- [ ] Two snapshots during steady guiding, a few minutes apart (for comparing N.I.N.A.'s RMS from `/equipment/guider/graph` with PHD2's `GuideStep` stream):
  ```sh
  python3 tools/m0/m0probe.py rest --host <HOST> --label guiding
  ```
- [ ] Note the RMS values PHD2 shows at those moments (total, RA, Dec, in arcsec) – a phone photo of the PHD2 window is enough.
- [ ] If a star is lost or guiding stops by itself, note the local time.

## 4. Sequence events (#7)

- [ ] At least one filter change.
- [ ] At least one autofocus run (note the time; if it fails, note that too).
- [ ] Sequence start captured; sequence end if it happens while the listener runs.

## 5. Device check on the Apple TV (M3 part 1)

- [ ] Overview while guiding: chart under the tiles, total RMS with traffic-light colour, values plausible against PHD2.
- [ ] Chart dimmed when guiding is not active (e.g. during autofocus or after a stop).
- [ ] Meridian tile: time to flip plausible against N.I.N.A.; after the flip it counts towards the next meridian.
- [ ] Anything odd: screenshot or photo plus local time.

## 6. Afterwards

- [ ] Sanitize each run folder:
  ```sh
  python3 tools/m0/m0probe.py sanitize captures/<run-folder> captures/sanitized/<run-folder> --redact <PC-HOSTNAME>
  ```
- [ ] Hand over the `captures/sanitized/` folders and your notes (times, RMS photos, observations). Raw captures stay on your Mac.
- [ ] Comment on #5, #6 and #7 with what was captured; tick the device check in [milestones](milestones.md) once the review is done.
