import LabKitCore
import LabKitUI
import SwiftUI

/// Reading notes for the offline network model. The sheet owns its dismissal.
struct ProtocolGuide: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LabMetrics.sectionSpacing) {
                    introduction
                    webStack
                    dns
                    tcp
                    udp
                    quic
                    routing
                    routeLearning
                    diagnostics
                    neighbors
                    media
                    security
                    compression
                    measurements
                    experiments
                    modelNotes
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(LabMetrics.gutter)
                .frame(maxWidth: .infinity)
            }
            .background(NetTheme.background.ignoresSafeArea())
            .navigationTitle("Inside the internet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("protocolGuide.done")
                }
            }
        }
        .labPalette(NetTheme.palette)
    }

    private var introduction: some View {
        GuideSection(eyebrow: "FIELD NOTES", title: "Small packets, many layers") {
            GuideParagraph("A page, a message, or a file becomes bytes. Those bytes travel in packets through a series of links and routers. Each layer adds a different job: naming, delivery, routing, security, or moving signals.")
            GuideParagraph("This toy lets you change the conditions and see their consequences. The globe is an offline teaching model; its hubs and paths are synthetic.")
            GuideParagraph(BellArchive.modernModelNote)
        }
    }

    private var webStack: some View {
        GuideSection(eyebrow: "APPLICATION", title: "How a web request fits together") {
            GuideParagraph("HTTP defines requests and responses. HTTPS adds authenticated encryption. These are common stacks, shown from the application down toward the physical link:")
            GuideFormula(label: "HTTPS · HTTP/1.1 OR HTTP/2", value: "HTTP → TLS → TCP → IP → link")
            GuideFormula(label: "HTTPS · HTTP/3", value: "HTTP/3 → QUIC (with TLS) → UDP → IP → link")
            GuideParagraph("An unencrypted HTTP/1.1 connection commonly uses TCP without TLS. DNS usually helps find the server before connecting; it is a separate exchange, rather than a wrapper around every web packet. Cached answers and reused connections can skip setup.")
            GuideSource("HTTP/2 · RFC 9113", url: "https://www.rfc-editor.org/rfc/rfc9113.html")
            GuideSource("HTTP/3 · RFC 9114", url: "https://www.rfc-editor.org/rfc/rfc9114.html")
        }
    }

    private var dns: some View {
        GuideSection(eyebrow: "NAMING", title: "DNS finds an address") {
            GuideParagraph("A resolver asks for records associated with a name, such as the IP address of a server. It may answer from a cache or consult other name servers. Cached records expire according to their time to live.")
            GuideParagraph("DNS has several transports, including UDP, TCP, and encrypted alternatives. The toy uses a short lookup phase to represent this work.")
            GuideSource("DNS concepts · RFC 1034", url: "https://www.rfc-editor.org/rfc/rfc1034")
        }
    }

    private var tcp: some View {
        GuideSection(eyebrow: "TRANSPORT", title: "TCP keeps the bytes in order") {
            GuideParagraph("TCP provides a reliable, ordered byte stream. Sequence numbers identify data, acknowledgments confirm receipt, and missing data is retransmitted. Bytes arriving after a gap can wait until that gap is repaired.")
            GuideParagraph("A connection handshake establishes the session. A congestion window limits unacknowledged data in flight; congestion control adapts sending to network conditions. Reliability can still end in a connection failure when the path stops working.")
            GuideSource("TCP · RFC 9293", url: "https://www.rfc-editor.org/rfc/rfc9293.html")
        }
    }

    private var udp: some View {
        GuideSection(eyebrow: "TRANSPORT", title: "UDP sends separate datagrams") {
            GuideParagraph("UDP preserves message boundaries but has no built-in promise of delivery, ordering, or duplicate protection. UDP itself does not resend missing datagrams or establish a transport handshake.")
            GuideParagraph("An application can add recovery, pacing, or congestion control above UDP. Here, raw UDP deliberately leaves losses unrecovered so you can see the difference between bytes sent and bytes received.")
            GuideSource("UDP · RFC 768", url: "https://www.rfc-editor.org/rfc/rfc768")
        }
    }

    private var quic: some View {
        GuideSection(eyebrow: "TRANSPORT", title: "QUIC builds more on UDP") {
            GuideParagraph("QUIC carries encrypted, reliable streams inside UDP datagrams. It adds acknowledgments, loss recovery, flow control, and congestion control. Its combined transport and TLS handshake can reduce connection setup time.")
            GuideParagraph("Streams have independent ordering: missing data in one stream need not block delivery on another. They still share connection congestion effects. This toy has one transfer, so it cannot demonstrate that multiple-stream advantage; a shorter handshake is not a promise that QUIC always wins.")
            GuideSource("QUIC · RFC 9000", url: "https://www.rfc-editor.org/rfc/rfc9000.html")
        }
    }

    private var routing: some View {
        GuideSection(eyebrow: "NETWORK", title: "IP moves packets hop by hop") {
            GuideParagraph("IP supplies source and destination addresses. A router uses its forwarding information to choose the next hop; it does not normally wait for the entire application file. A packet's hop limit prevents endless circulation through routing loops.")
            GuideParagraph("IP alone does not promise delivery or ordering. Different paths, queues, and failures can change the journey. In the toy, selecting cities changes the path through a fixed graph; real routing policy is more complex.")
            GuideSource("IPv4 routing · RFC 1812", url: "https://www.rfc-editor.org/rfc/rfc1812.html")
        }
    }

    private var routeLearning: some View {
        GuideSection(eyebrow: "ROUTING CONTROL", title: "BGP and OSPF learn where to send") {
            GuideParagraph("BGP exchanges reachability for IP prefixes between networks called autonomous systems. Its path information and policy help choose routes between organizations; the chosen route need not be the geographically shortest one.")
            GuideParagraph("OSPF is used inside an autonomous system. Routers exchange link-state information and calculate paths with the lowest configured cost. Learning routes is separate from forwarding each data packet using those routes.")
            GuideParagraph("The toy selects a shortest geographic-distance path through a fixed synthetic graph. It does not exchange BGP advertisements, maintain OSPF neighbor state, or model routing convergence.")
            GuideSource("BGP · RFC 4271", url: "https://www.rfc-editor.org/rfc/rfc4271.html")
            GuideSource("OSPFv2 · RFC 2328", url: "https://www.rfc-editor.org/rfc/rfc2328.html")
        }
    }

    private var diagnostics: some View {
        GuideSection(eyebrow: "NETWORK FEEDBACK", title: "ICMP asks and reports") {
            GuideParagraph("Ping uses ICMP Echo Request and Echo Reply messages to test reachability and measure a round trip. ICMP also reports problems, such as an unreachable destination or a packet whose TTL or Hop Limit expired: Time Exceeded.")
            GuideParagraph("Traceroute-style probes use increasing hop limits and the resulting replies to reveal successive routers. A missing reply does not always mean a failed path: replies can be filtered or rate limited. ICMP feedback does not make IP reliable.")
            GuideParagraph("The round-trip readout here is a calculated estimate, not a live ping. The toy does not send ICMP probes or discover real routers.")
            GuideSource("ICMPv4 · RFC 792", url: "https://www.rfc-editor.org/rfc/rfc792.html")
            GuideSource("ICMPv6 · RFC 4443", url: "https://www.rfc-editor.org/rfc/rfc4443.html")
        }
    }

    private var neighbors: some View {
        GuideSection(eyebrow: "LOCAL DELIVERY", title: "ARP and Neighbor Discovery find the next hop") {
            GuideParagraph("An IP destination and a local link address have different jobs. Even when the destination is a public internet IP address, a local Ethernet frame usually goes to the next-hop gateway's MAC address, rather than the remote server's MAC address.")
            GuideParagraph("For IPv4 on Ethernet, ARP resolves a next-hop IP address to its link address. IPv6 Neighbor Discovery uses ICMPv6 to resolve neighbor addresses, discover routers, and check neighbor reachability. Cached mappings can avoid repeating a lookup.")
            GuideParagraph("These exchanges stay on the local link. A router creates a new link envelope for the next hop. The toy illustrates those envelopes but does not simulate ARP or Neighbor Discovery messages or caches.")
            GuideSource("ARP · RFC 826", url: "https://www.rfc-editor.org/rfc/rfc826.html")
            GuideSource("IPv6 Neighbor Discovery · RFC 4861", url: "https://www.rfc-editor.org/rfc/rfc4861.html")
        }
    }

    private var media: some View {
        GuideSection(eyebrow: "LINK & PHYSICAL", title: "Fiber, radio, Ethernet, and Wi-Fi") {
            GuideParagraph("Ethernet and Wi-Fi organize communication across individual links. Fiber carries light; radio carries electromagnetic waves through the air. Ethernet can run over copper or fiber. Wi-Fi is a local wireless link, often followed by wired and fiber hops on the same internet journey.")
            GuideParagraph("Wireless capacity and delay can vary with shared airtime, interference, and signal conditions. Fiber and wireless are editable presets here, not universal performance guarantees. Radio signals in air are not inherently slower than light in glass.")
            GuideParagraph("A long globe arc marked radio represents an abstract long-haul radio or space link. It does not mean a Wi-Fi access point reaches across an ocean.")
            GuideSource("Ethernet · IEEE 802.3", url: "https://www.ieee802.org/3/")
            GuideSource("Wireless LANs · IEEE 802.11", url: "https://www.ieee802.org/11/")
        }
    }

    private var security: some View {
        GuideSection(eyebrow: "SECURITY", title: "TLS protects the conversation") {
            GuideParagraph("TLS authenticates the server and protects application data against eavesdropping and undetected changes. Its handshake establishes keys. Routers still need enough addressing information to forward the packets; encryption does not make a journey invisible.")
            GuideParagraph("For HTTPS over TCP, TLS sits above TCP. QUIC integrates TLS 1.3 into its transport handshake. QUIC uses TLS-derived keys to protect its own packets, without TLS record framing. The toy shows setup time and packet overhead; it does not perform cryptography.")
            GuideSource("TLS 1.3 · RFC 8446", url: "https://www.rfc-editor.org/rfc/rfc8446.html")
        }
    }

    private var compression: some View {
        GuideSection(eyebrow: "PAYLOAD", title: "Fewer bytes, extra work") {
            GuideParagraph("Lossless content compression represents the same information with fewer bytes. A web server and client can negotiate an encoding such as gzip or Brotli. Content is compressed before encryption, then decompressed at the receiving endpoint.")
            GuideParagraph("Repetitive text usually offers more savings than already compressed images or video. Compression and decompression cost computing time. On a narrow link the saved transfer time may dominate; on a fast link that work may outweigh a small reduction.")
            GuideParagraph("The compression control changes a modeled payload ratio and CPU cost. It does not run an actual codec. TLS 1.3 does not use TLS-level compression; HTTP content compression is a separate operation.")
            GuideSource("HTTP compression · MDN", url: "https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Compression")
            GuideSource("Encoding negotiation · MDN", url: "https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Accept-Encoding")
        }
    }

    private var measurements: some View {
        GuideSection(eyebrow: "MEASUREMENTS", title: "Capacity is different from travel time") {
            GuideParagraph("Bandwidth is link capacity in bits per second. Propagation delay is the time a signal spends traveling. Increasing capacity fits more bits onto the link each second; it does not change the signal's propagation speed.")
            GuideFormula(label: "SERIALIZATION TIME", value: "packet bits ÷ link bits per second")
            GuideFormula(label: "PROPAGATION TIME", value: "path distance ÷ signal speed")
            GuideFormula(label: "ONE HOP", value: "queue wait + serialization + propagation + processing")
            GuideFormula(label: "GOODPUT", value: "useful delivered payload bits ÷ elapsed seconds")
            GuideParagraph("Round-trip time (RTT) measures a trip out and back. Jitter is variation in delay. Here, goodput counts original useful bytes delivered over the whole modeled journey, including setup and CPU time. Compression can make it exceed wire capacity because the original bytes take fewer bits to carry. Wire traffic includes headers and retransmitted copies. Packet loss and time spent waiting for feedback can reduce goodput below the link's advertised capacity.")
            GuideSource("Packet delay components · Cisco", url: "https://www.cisco.com/c/en/us/support/docs/voice/voice-quality/5125-delay-details.html")
        }
    }

    private var experiments: some View {
        GuideSection(eyebrow: "TRY IT", title: "Three useful comparisons") {
            GuideExperiment(title: "A wide pipe, a long trip", text: "Keep delay high and raise bandwidth. The bulk transfer gets faster while setup still waits for replies. Then lower delay and compare.")
            GuideExperiment(title: "What does loss cost?", text: "Raise wireless loss and compare TCP, raw UDP, and QUIC. Watch retries, delivery, and completion time. UDP can finish sending while the receiver still has missing data.")
            GuideExperiment(title: "Compression's break-even point", text: "Compare compression on and off over a narrow link, then a fast one. Try a large assumed reduction for text and a small one for already compressed media; compare bytes saved with modeled CPU time.")
        }
    }

    private var modelNotes: some View {
        GuideSection(eyebrow: "MODEL BOUNDARY", title: "What the globe represents") {
            GuideParagraph("This app makes no real network requests for the simulation. Hubs, links, routes, capacities, and traffic are synthetic. Animated dots are symbolic packet batches. Their count and loss markers are not literal packet counts or exact loss percentages. Globe scale and animation time are adapted for visibility.")
            GuideParagraph("Loss is a configurable teaching probability. Compression ratios, CPU costs, setup phases, retries, and congestion behavior are simplified. Real networks add routing policy, link-layer recovery, competing flows, caching, server work, and many implementation choices.")
            GuideParagraph("Use the results to explore cause and effect, not to predict an ISP's speed or benchmark a real protocol implementation. Source links open the standards and documentation used for these notes.")
        }
    }
}

private struct GuideSection<Content: View>: View {
    let eyebrow: String
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(eyebrow)
                .font(LabFont.eyebrow)
                .tracking(1.5)
                .foregroundStyle(NetTheme.muted)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color(LabSemantic.ink))
                .accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LabMetrics.panelPadding)
        .background(NetTheme.panel, in: RoundedRectangle(cornerRadius: LabMetrics.panelRadius))
    }
}

private struct GuideParagraph: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(LabFont.body)
            .foregroundStyle(Color(LabSemantic.ink, opacity: LabSemantic.bodyAlpha))
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

private struct GuideFormula: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(LabFont.readoutLabel)
                .foregroundStyle(NetTheme.muted)
            Text(value)
                .font(LabFont.readoutValue)
                .foregroundStyle(Color(LabSemantic.forecast))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(NetTheme.screen, in: RoundedRectangle(cornerRadius: LabMetrics.chipRadius))
        .accessibilityElement(children: .combine)
    }
}

private struct GuideSource: View {
    let title: String
    let url: String
    init(_ title: String, url: String) {
        self.title = title
        self.url = url
    }

    var body: some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                Label(title, systemImage: "arrow.up.right")
                    .font(LabFont.hint)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: LabMetrics.minHit, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .tint(Color(NetTheme.signalBlue))
            .accessibilityHint("Opens the source documentation")
        }
    }
}

private struct GuideExperiment: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(LabFont.cardTitle)
                .foregroundStyle(Color(LabSemantic.ink))
            GuideParagraph(text)
        }
    }
}

#Preview {
    ProtocolGuide()
}
