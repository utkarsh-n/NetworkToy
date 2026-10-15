# Packet sniffer teaching model

SnoopyNet's packet sniffer runs a deterministic, discrete-event **38.4 KB probe: 32 original application chunks of 1,200 bytes each**. It is separate from the globe's bulk-transfer forecast and its 2–50 MB payload setting. Every modeled data and acknowledgment frame occupies link time, follows a route, and either arrives or drops. These are simulated transfers, not captures of traffic on the phone or the public internet.

The engine is Foundation-only in `NetworkToy/Simulation/PacketSnifferEngine.swift`. It reads a value copy of `NetworkConfig` and obtains the normalized configuration, synthetic route, distances, propagation times, effective capacity, and queue assumptions from `NetworkEngine.calculate`. It does not change `NetworkEngine`, `NetworkStore`, or the caller's settings.

## API contract

```swift
let result = PacketSnifferEngine.simulate(config: config, seed: 1984)
let counters = result.observedStats(at: elapsedModelMs)
let packet = result.packet(id: 1, at: elapsedModelMs)
let packetWireBytes = result.observedWireBytes(at: elapsedModelMs, packetID: 1)
```

The default seed is `1984`. IDs for the original chunks are `1...32`; a retry preserves the chunk ID. Event IDs are stable, contiguous integers in chronological order, with deterministic ordering for simultaneous events.

| Type | Implemented fields or behavior |
| --- | --- |
| `SnifferResult` | `schedule`, `packets`, normalized `config`, `route`, `durationMs`, `deliveredCount`, `droppedAttempts`, `retryCount`, `ackCount`, `failedCount`, `originalBytes`, `compressedBytes`, `wireBytes`, `bytesSaved`, `goodputMbps`, `seed`, and `assumptions`. |
| `SnifferEvent` | `id`, optional `packetID`, `timeMs`, `kind`, optional `hopIndex`, `hopTitle`, `byteCount`, `detail`, `attempt`, `isAcknowledgment`, optional `acknowledgmentNumber`, optional `packetNumber`, `durationMs`, and optional `medium`. |
| `SnifferPacket` | `id`, `transport`, documentation `sourceAddress`/`destinationAddress`, ports, `sequenceNumber`, `flags`, `originalLength`, `payloadLength`, `headerLength`, `totalLength`, city-name `path`, actual `attemptCount`, `received`, `delivered`, `acknowledged`, and chronological `ledger`. Computed helpers expose `ipProtocolNumber`, `sequenceLabel`, and `status`. |
| `SnifferStats` | Observed `elapsedMs`, `receivedCount`, `deliveredCount`, `droppedAttempts`, `retryCount`, `ackCount`, `wireBytes`, and `goodputMbps`. |

`packet(id:)` returns the final packet outcome and full ledger. During playback, use `packet(id:at:)` to hide future attempts, delivery, confirmation, and ledger entries. `observedStats(at:)` and `observedWireBytes(at:packetID:)` likewise use the observation time. Times are clamped to the capture duration; negative or nonfinite observation times resolve to zero.

### Event meanings

| Kind | Meaning |
| --- | --- |
| `setup` | A DNS, TCP, TLS, or QUIC setup timing placeholder. No decoded setup frame is created. |
| `compress` | Assumed chunk compression and modeled CPU duration. |
| `queued` | Waiting for modeled extra/background delay or a busy link; also records a recovery timer requeuing data. |
| `transmit` | A particular data or ACK frame starts serializing on one link. `durationMs` is that serialization time. |
| `arrive` | The frame survives the link and reaches its next node. |
| `drop` | Seeded loss discards a data or ACK frame after its modeled link transmission and propagation. It does not traverse subsequent links. |
| `retry` | A repeated data attempt actually begins on the source's first link. |
| `deliver` | The receiver's application obtains a decoded original chunk. |
| `ack` | An ACK frame reaches the sender. |
| `duplicate` | A repeated data chunk reaches a receiver that already holds it. It is not delivered twice; feedback is sent again. |
| `exhausted` | The retry budget ends without confirming feedback for this chunk. It is a warning, not successful confirmation. |
| `complete` | The whole capture ends. This single final event has no packet ID and does not imply every chunk was delivered or confirmed. |

## Packetization and modeled headers

Compression leaves **32 independently compressible and decodable chunks**, each with a smaller payload. It does not merge them into fewer data frames. For reduction `r`:

```text
compressed payload per chunk = ceil(1,200 × (1 − r)) bytes
compressedBytes = 32 × compressed payload per chunk
originalBytes = 32 × 1,200 = 38,400 bytes
bytesSaved = originalBytes − compressedBytes
```

The configuration's compression range is 0–90%. Payload bytes are rounded up to whole bytes. The chosen reduction is assumed achievable; no gzip, Brotli, or other codec runs. Independently usable chunks let raw UDP report received application data despite missing neighboring chunks. This does not demonstrate recovery of a monolithic compressed file.

The fixed teaching envelopes fit a nominal 1,280-byte MTU at the uncompressed 1,200-byte payload size:

| Frame | Modeled bytes beyond application payload |
| --- | --- |
| TCP data with illustrative TLS framing | 62: IPv4 20 + TCP 20 + TLS record/tag/type budget 22. |
| Raw UDP data | 28: IPv4 20 + UDP 8. |
| QUIC data | 64: IPv4/UDP 28 + short QUIC header budget 12 + STREAM envelope budget 8 + authentication tag budget 16. |
| TCP ACK | 40 without an out-of-order SACK block; 52 with a modeled single-block SACK option. |
| QUIC ACK | Fixed illustrative 60-byte frame budget. |

These are accounting envelopes, not a byte encoder or a packet-format conformance test. Real TCP options, TLS records, QUIC variable-length fields, packet coalescing, padding, tags, and link frames vary. The probe does not generate raw encrypted bytes, calculate checksums, or model fragmentation. Link-layer framing is excluded from the byte totals.

Source addresses are `192.0.2.(10 + source node index)` and destination addresses are `198.51.100.(10 + destination node index)`, drawn from documentation blocks. The source port is 49152; the destination is 443 for TCP/QUIC or the illustrative application port 9000 for raw UDP. The displayed IPv4 protocol number is 6 for TCP and 17 for UDP or QUIC-over-UDP. Event text starts its modeled hop-limit accounting at 64 and subtracts one per traversed link.

`sequenceNumber` has transport-specific meaning:

- TCP: compressed byte sequence beginning at `100001`, increasing by `payloadLength` per original chunk. Retries retain the byte sequence.
- QUIC: byte offset in one ordered stream, beginning at zero. Retries retain the stream offset but use a new increasing QUIC packet number.
- UDP: application chunk ID. **UDP has no transport sequence field.** `DATAGRAM` is a descriptive label, not a UDP header flag.

The displayed TCP `PSH ACK` and QUIC `STREAM` labels identify the modeled transfer. They are not evidence of inspected wire bytes or performed encryption.

## Link timing, queues, and media

Each frame enters every traversed link separately. A frame cannot advance to the next link until it finishes serializing and propagating on the current one. Other packets pipeline behind it; the model does not serialize the entire probe once per hop before allowing any packet to advance.

```text
serializationMs = frameBytes × 8 ÷ (effectiveMbps × 1,000)
arrivalMs = transmissionStartMs + serializationMs + linkPropagationMs
```

`linkPropagationMs` comes from the bulk engine's synthetic route. Fiber uses cable-path inflation and assumed propagation at 200,000 km/s; wireless uses an abstract radio/space path and 300,000 km/s. Mixed mode represents local radio access feeding a fiber backbone. Long radio arcs are not ordinary intercontinental Wi-Fi links.

`effectiveMbps` is the selected capacity multiplied by the medium's teaching efficiency—0.96 for fiber, 0.65 for wireless, 0.82 for mixed—and the share left after congestion. Increasing capacity shortens serialization; it does not increase propagation speed.

The scheduler tracks when each link becomes available. Fiber has separate forward and reverse queues. Wireless links and the mixed access segment share one airtime queue for data and ACKs. The probe uses a FIFO reservation model, without a real radio MAC, priority scheduling, or competing packet streams.

Before a link can begin serializing, a frame also pays this modeled per-hop wait:

```text
(extra one-way latency + bulk-engine background queue delay + access delay)
÷ number of route links
```

The background queue term comes from the congestion setting. The additional access-delay budget is zero for fiber, 3 ms for mixed, or 8 ms for wireless; it is amortized across the hops. This fixed waiting budget is distinct from additional waiting caused by frames already occupying a link. It is a teaching assumption, not measured router or radio processing.

## Loss, feedback, ordering, and retry limits

The loss setting is the normalized end-to-end probability for one forward journey, within 0–20%. For `h` route links and probability `p`, each link uses:

```text
per-link probability = 1 − (1 − p)^(1 / h)
```

ACKs face the same independent link conditions in reverse. A fixed integer hash of seed, chunk ID, attempt, hop, and direction supplies each loss decision. This keeps a particular attempt's loss draws stable when only capacity or extra delay changes; timing can still change which attempts become necessary. No nondeterministic random generator or wall clock drives the engine.

Raw UDP sends each original chunk once. It generates no transport ACK and performs no retry. `deliveredCount` can therefore be less than 32.

TCP and QUIC send feedback after network receipt, independently of application decoding. TCP models cumulative ACKs with simplified SACK feedback for an out-of-order chunk. A returned cumulative TCP ACK may confirm multiple earlier chunks. QUIC ACKs identify the transmitted QUIC packet number; a repeated chunk uses a new packet number. Lost ACKs can cause a repeated data transmission even when the receiver already has the chunk.

Both reliable transports use **one ordered application stream**. Later received chunks remain buffered behind a missing chunk. Once the gap closes, decoding/delivery progresses in order. Duplicate data is discarded at the application boundary and acknowledged again.

The source sends an eager 32-chunk flight. Recovery is governed by fixed teaching timers:

```text
baseline RTT = modeled route RTT + 2 × links × one-frame serialization time
initial TCP timer = max(1,000 ms, 2 × baseline RTT)
initial QUIC timer = max(50 ms, 2 × baseline RTT)
attempt timer = min(60,000 ms, initial timer × 2^(attempt − 1))
```

The timer starts after the source link's serialization. Missing confirmation queues another attempt. Queue delays can cause a timer to fire before an ACK arrives, so retries are not synonymous with data loss. This is a per-chunk teaching timer; it does not implement TCP's oldest-unacknowledged-segment timer management or QUIC's standard packet-number-space recovery state.

There are at most **eight retries after the initial transmission: nine data attempts per chunk**. An `exhausted` event leaves confirmation explicitly unresolved. It does not fabricate an ACK or guarantee that missing data was recovered. `failedCount` is `32 − deliveredCount`; a chunk may be delivered yet unconfirmed, so inspect `packet.acknowledged` separately. Later chunks can also be transport-acknowledged but remain buffered behind an application stream gap.

This is not a full TCP or QUIC implementation. It does not implement a congestion window, slow start, CUBIC/BBR, fast retransmit, full SACK ranges, adaptive RTT/variance estimation, standard QUIC PTO computation, flow-control windows, multipath, or multiple independent QUIC streams.

## Compression CPU time and accounting

The model applies the same illustrative CPU-cost assumptions as the bulk engine, scaled to this probe's original 0.0384 MB:

```text
compressionMs = originalMB × 28 × reduction²
decompressionMs per chunk = 0.0012 MB × 2 × reduction
```

Compression occurs before data launch. Receiver decoding uses a serial application-work queue after chunk receipt and, for reliable transports, after stream gaps permit ordered delivery. A large reduction can save transmission time on a narrow link but cost more CPU time than it saves on a very fast link. These costs are assumptions, not device or codec benchmarks.

`wireBytes` sums the bytes of **every data, retry, and ACK transmission on every link actually traversed**. A dropped frame still consumes transmission bytes on the link where it drops. Setup timing placeholders and link-layer framing do not contribute bytes. This differs from the bulk forecast's data-direction, once-per-journey wire total; the two counters should not be compared as if they measured the same boundary.

For a live observation, `observedWireBytes(at:packetID:)` counts only bytes already serialized, including the completed portion of an in-progress frame, rounded down to whole bytes. Summing `transmit.byteCount` as soon as each start event appears would incorrectly include the rest of that frame before it has been sent. The final all-hop sum remains the sum of completed transmission frame sizes.

Counter definitions:

- `deliveredCount`: unique decoded original chunks delivered to the application.
- `receivedCount`: unique chunks physically received at the destination, including buffered chunks.
- `droppedAttempts`: data or ACK frames discarded on a link.
- `retryCount`: repeated data attempts that actually begin at the source.
- `ackCount`: ACK frames that reach the sender. Duplicate feedback can make this exceed 32; it is not the number of uniquely confirmed chunks.
- `goodputMbps`: original useful delivered bytes × 8 divided by elapsed modeled milliseconds × 1,000. It includes setup and waiting time. Because it counts original useful bytes, compression can make it exceed the capacity used to carry compressed bytes.
- `durationMs`: the final emitted event timestamp, including setup, compression, delivery, ACK returns, or retry-budget expiration. The final `complete` event uses this timestamp.

The UI may scale this timeline for readability. Displayed numeric times remain modeled milliseconds. Pausing playback does not change the precomputed schedule; changing capture settings should invalidate the local capture before replay. No sockets, live measurements, codecs, crypto, or external accounts are involved.

## Executed validation

The following command was executed from `/path/to/developer/Documents/AI Stuff/NetworkToy`:

```sh
env CLANG_MODULE_CACHE_PATH=/private/tmp/network-toy-clang-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/network-toy-module-cache \
    swift test --disable-sandbox \
    --cache-path /private/tmp/network-toy-swift-cache \
    --scratch-path /private/tmp/network-toy-swift-build \
    -Xswiftc -module-cache-path \
    -Xswiftc /private/tmp/network-toy-module-cache
```

The final run completed on **2026-10-13, 16:22:33 America/Chicago**. It reported **27 XCTest tests passed, zero failures**: 15 existing bulk-engine tests and 12 packet-sniffer tests. Build time was 139.48 seconds; the combined XCTest run reported 3.984 seconds. The final result was captured in execution session `71968` with command exit status `0`.

**Standalone test-log path: none.** The command captured stdout in the execution tool without file redirection, so no separate stdout log file was written. This document records the executed command and observed result; it does not claim a nonexistent log artifact.

The sniffer checks cover 32-chunk/no-ACK UDP behavior, modeled header/sequence fields, nonoverlapping link serialization, propagation and capacity separation, congestion queues, seeded UDP gaps versus reliable recovery, ACK return paths, new QUIC packet numbers on retry, finite retry exhaustion without fabricated confirmation, compression/CPU tradeoffs, independence from the bulk payload setting, observed-time decoder and partial-byte accounting, and deterministic event IDs/accounting.

These are Foundation-model tests. **No simulator UI tests, signed-phone runtime, physical haptics, or long-running foreground stability are claimed for this validation run.**

## Primary sources

The engine comments link these primary references:

- [RFC 5737 — IPv4 documentation address blocks](https://www.rfc-editor.org/rfc/rfc5737.html).
- [RFC 9293 — TCP, ordered byte streams, acknowledgments, and retransmission](https://www.rfc-editor.org/rfc/rfc9293.html).
- [RFC 6298 — TCP retransmission timers and exponential backoff](https://www.rfc-editor.org/rfc/rfc6298.html).
- [RFC 9000 — QUIC streams, byte offsets, packet acknowledgments, and transport](https://www.rfc-editor.org/rfc/rfc9000.html).

The standards explain protocol behavior. The fixed probe size, synthetic routes, link efficiencies, compression costs, queue budgets, simplified recovery policy, and illustrative frame budgets are this application's declared teaching assumptions, not values mandated by those RFCs.
