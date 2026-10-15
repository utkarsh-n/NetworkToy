/// Historical notes for the optional 1984 archive. These names do not alter the network model.
/// City coordinates are illustrative regional anchors, not headquarters or service boundaries.
struct BellArchiveItem: Identifiable, Sendable {
    let id: String
    let name: String
    let region: String
    let anchorCity: String
    let latitude: Double
    let longitude: Double
    /// Original playful copy, rather than a quotation or company slogan.
    let quip: String
}

struct BellArchiveSource: Identifiable, Sendable {
    let id: String
    let title: String
    let url: String
    let detail: String
}

enum BellArchive {
    static let date = "January 1, 1984"
    static let dateLabel = "01 JAN 1984"
    static let isoDate = "1984-01-01"
    static let title = "The family plan has changed"
    static let subtitle = "One family. Seven letterheads."
    static let stamp = "DIVESTITURE · 01 JAN 1984"
    static let summary = "On January 1, 1984, AT&T's local telephone operations separated into seven independent regional companies, nicknamed the Baby Bells."
    static let intro = summary
    static let retained = "AT&T retained long-distance service, manufacturing, and Bell Labs. Some Bell Labs staff moved into Bellcore to support the independent regional operators."
    static let modernModelNote = "1984-inspired instruments. Modern internet model. QUIC, TLS 1.3, and today's wireless systems are not being presented as 1984 technology."
    static let mapNote = "Cities mark illustrative regional anchors. They are not exact 1984 headquarters, service boundaries, or real routing hubs."

    static let originals: [BellArchiveItem] = [
        .init(id: "ameritech", name: "Ameritech", region: "Great Lakes",
              anchorCity: "Chicago", latitude: 41.88, longitude: -87.63,
              quip: "Dial tone, with a Midwestern apology."),
        .init(id: "bell-atlantic", name: "Bell Atlantic", region: "Mid-Atlantic",
              anchorCity: "Philadelphia", latitude: 39.95, longitude: -75.16,
              quip: "Your call is important to several states."),
        .init(id: "bellsouth", name: "BellSouth", region: "Southeast",
              anchorCity: "Atlanta", latitude: 33.75, longitude: -84.39,
              quip: "Please hold. The porch light is on."),
        .init(id: "nynex", name: "NYNEX", region: "New York & New England",
              anchorCity: "New York", latitude: 40.71, longitude: -74.01,
              quip: "Four letters. A very long phone book."),
        .init(id: "pacific-telesis", name: "Pacific Telesis", region: "California & Nevada",
              anchorCity: "San Francisco", latitude: 37.77, longitude: -122.42,
              quip: "Same dial tone. Better sunsets."),
        .init(id: "southwestern-bell", name: "Southwestern Bell", region: "South Central",
              anchorCity: "St. Louis", latitude: 38.63, longitude: -90.20,
              quip: "Wide territory. Narrow excuses."),
        .init(id: "us-west", name: "U S WEST", region: "West & Northern Plains",
              anchorCity: "Denver", latitude: 39.74, longitude: -104.99,
              quip: "Long distances. Locally sourced hold music."),
    ]

    static let items = originals

    static let sources: [BellArchiveSource] = [
        .init(id: "att-history", title: "AT&T · Historical brands",
              url: "https://about.att.com/innovation/intellectualproperty/ip_brands/ip_history.html",
              detail: "The 1984 separation and the businesses AT&T retained."),
        .init(id: "original-seven", title: "Federal Register · January 10, 1984",
              url: "https://www.govinfo.gov/content/pkg/FR-1984-01-10/pdf/FR-1984-01-10.pdf",
              detail: "Printed page 1191, footnote 3, lists the original seven regional companies."),
        .init(id: "effective-date", title: "Federal Judicial Center · The breakup of Ma Bell",
              url: "https://www.fjc.gov/node/11371686",
              detail: "The court history identifies January 1, 1984 as the implementation date."),
        .init(id: "bell-labs-history", title: "Nokia Bell Labs · History",
              url: "https://www.nokia.com/bell-labs/about/history/",
              detail: "Bell Labs continued at AT&T; a separate staff group formed Bellcore."),
    ]
}
