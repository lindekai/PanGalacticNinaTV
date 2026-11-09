# M0 – Live read-only test procedure

Goal: capture real responses from the owner's N.I.N.A. / Advanced API / PHD2 setup to turn the [capability matrix](api-capability-matrix.md) from *desk research* into *verified*.

**Safety:** every step below only reads. The probe tool refuses any path outside the allowlist, sends nothing on the N.I.N.A. event socket except the WebSocket handshake/pong/close, and never writes to PHD2. Imaging is started and controlled **by you in N.I.N.A. as usual** – the tooling never does it.

## 0. Prerequisites

- Mac on the same subnet as the telescope PC; Python 3 (`python3 --version`).
- N.I.N.A. running, Advanced API enabled (port 1888).
- PHD2 running with its server enabled (*Tools → Enable Server*; N.I.N.A. needs this anyway).
- Replace `<HOST>` below with the telescope PC's IP or hostname. Do not commit it anywhere.

Reachability (TCP connect only, no data sent):

```sh
nc -z -G 3 <HOST> 1888 && echo "Advanced API port reachable"
nc -z -G 3 <HOST> 4400 && echo "PHD2 event port reachable"
```

If either fails: check the Windows firewall inbound rules for N.I.N.A. and PHD2 (private network profile).

## 1. Record versions

Note in the M0 issue: N.I.N.A. version, Advanced API version (2.2.15.3 expected), PHD2 version (*Help → About*), Windows version.

## 2. Idle snapshot (equipment connected, nothing running)

```sh
python3 tools/m0/m0probe.py rest --host <HOST> --label idle --images
```

Output goes to `captures/` (git-ignored).

## 3. Running session

Open two terminals and start the passive listeners **before** you start your sequence (they stop by themselves after `--seconds`; Ctrl-C also works):

```sh
python3 tools/m0/m0probe.py ws   --host <HOST> --seconds 3600 --label session
python3 tools/m0/m0probe.py phd2 --host <HOST> --seconds 3600 --label session
```

Then start a normal imaging sequence in N.I.N.A. Ideally the window covers: guiding start, at least two completed light frames, a filter change, a dither, and (if it happens naturally) an autofocus run. Please do not provoke failures on purpose.

While a sequence is running, take one or two REST snapshots:

```sh
python3 tools/m0/m0probe.py rest --host <HOST> --label running --images
```

During the `--images` step, glance at Task Manager on the telescope PC and note the CPU spike and whether the running exposure/download was affected. The console prints each request's duration.

## 4. Sanitize

```sh
python3 tools/m0/m0probe.py sanitize captures/<run-folder> captures/sanitized/<run-folder> --redact <PC-HOSTNAME>
```

The sanitizer zeroes site coordinates/elevation, removes file paths, hostnames, device IDs and private IPs. Images (`.jpg`/`.png`) are not modified – check that they are fine to share.

## 5. Hand-over

Share the `captures/sanitized/` folders. They are reviewed again before anything is copied into `Tests/Fixtures/`. Raw captures stay on your Mac.

## 6. Apple TV reachability

Verified in M1 with the app skeleton (tvOS local-network permission prompt, direct HTTP to port 1888, TCP to 4400).
