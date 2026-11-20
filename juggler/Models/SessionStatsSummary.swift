struct SessionStatsSummary: Equatable {
    let workingCount: Int
    let activeCount: Int
    let backburnerCount: Int
    let hiddenCount: Int

    init(sessions: [Session]) {
        let active = sessions.filter { !$0.isHidden && $0.state != .backburner }
        workingCount = active.filter { $0.state == .working || $0.state == .compacting }.count
        activeCount = active.count
        backburnerCount = sessions.filter { $0.state == .backburner }.count
        hiddenCount = sessions.filter(\.isHidden).count
    }

    var displayText: String {
        "\(workingCount)/\(activeCount) busy, \(backburnerCount) backburnered, \(hiddenCount) hidden"
    }
}
