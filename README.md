# SnoopyNet

An iPhone-only, offline network toy for iOS 27. Drag a miniature globe, pick cities, and follow representative packet groups through an illustrative worldwide network.

Uses the existing local `../LabKit` package: native Liquid Glass chrome, accessible rotary controls, and optional haptics. The 1984 Bell Labs theme is entirely dark, with a rotating blue striped globe, cyan phosphor readouts, CRT bloom, and scanlines. Globe and icon artwork are procedural. No accounts or live packet capture.

## Play

Choose fiber, wireless, or mixed local radio plus fiber. Compare TCP with TLS, raw UDP, and QUIC. Turn capacity, packet loss, and compression knobs, or open Tune for delay, payload, shared capacity, playback speed, and haptics. Send a burst, pause/resume, inspect its timeline and protocol envelope, or load one of three experiments. Every configuration edit resets the transfer and updates predicted metrics.

Tap the **1984** badge to open the Baby Bell archive and reveal seven decorative bell satellites. This visual state does not change the route or simulation. The archive provides historical sources and original regional jokes. The interface is 1984-inspired; the modeled internet includes modern protocols.

Tap **Sniff packets** for a separate 32-chunk simulated probe. Start, pause, filter for trouble, and tap a packet event to decode its teaching headers and observed ledger. Degrade capacity, delay, loss, shared capacity, or compression, then restart and compare with the previous finished probe. Clean line, Busy exchange, and Wireless interference presets offer starting points. These local edits leave the main globe settings intact.

## Build

Requires Xcode 27, Swift 6.4, XcodeGen, and the adjacent LabKit checkout.

```sh
xcodegen generate
open Relay.xcodeproj
```

Visible app name: **SnoopyNet**. Internal project and scheme: `Relay`. Bundle: `com.utkarsh.networktoy`. iPhone only; portrait; deployment target iOS 27. Automatic signing uses the workspace's existing team.

The Foundation-only engine has a separate test package:

```sh
swift test
```

Five simulator UI tests cover playback, UDP inspection, delay/default restoration, archive isolation, and sniffer capture/decoding/isolation. Check `Documentation/VERIFICATION.md` for executed results.

## Teaching model

Routes and hubs are synthetic. Radio-only long-haul routes stand for abstract radio/space backhaul; ordinary Wi-Fi/cellular access is local. Fiber travels at an assumed 200,000 km/s, radio at 300,000 km/s. Medium presets use explicit illustrative efficiencies, not measured performance.

Capacity governs serialization, separate from propagation. Congestion shares capacity and adds a simplified queue. Loss is an end-to-end probability. TCP and QUIC retry; UDP can lose independently useful chunks. UDP delivery percentages do not establish that a compressed monolithic file can be recovered. Compression is an assumed byte reduction with a modeled CPU cost, not a specific codec benchmark. Protocol setup is a fresh DNS lookup plus simplified transport/TLS handshakes.

Goodput counts useful original delivered bytes over modeled total time, so compression can make goodput exceed compressed wire capacity. Data-direction wire bytes count IP headers and retries; setup/ACK/link/TLS framing are excluded. Animation is scaled to a readable journey; numeric timings retain modeled milliseconds. Dot samples and retry patterns are representative, not a literal packet capture or a complete TCP congestion-control implementation.

Primary RFC and documentation links are available in the app's Inside the internet guide.

## Simulated packet capture

The probe starts with 32 independently compressible application chunks of 1,200 B each (38.4 KB). It schedules individual data and ACK attempts through the synthetic route: queue wait, serialization, propagation, arrival or loss, retransmission, and application delivery. TCP and QUIC preserve ordered stream delivery; raw UDP delivers independent chunks without ACKs or retries. Seeded outcomes make comparisons repeatable. Recovery stops after eight retries per chunk and leaves missing data or unconfirmed ACKs explicit.

The byte counters reveal only bits already serialized, including partial frames. All-hop wire bytes sum data and ACK traffic on every traversed link, including retries; abstract setup, local framing, and physical coding are excluded. This differs from the bulk transfer's data-direction wire estimate. Header addresses use documentation IPv4 ranges. Security overhead, setup phases, fixed recovery timers, compression ratios, and CPU costs are modeled; no actual codec, sockets, checksums, or cryptography run. Full congestion-window algorithms, adaptive recovery, and routing convergence are outside the probe.

Numeric timestamps use modeled milliseconds; playback stretches the event schedule to 16 seconds. The sniffer displays generated events, not private traffic from the phone.


## Public snapshot

See [PUBLICATION.md](PUBLICATION.md) for publication exclusions and setup requirements.
