struct SessionStatsSummary: Equatable {
    let workingCount: Int
    let totalCount: Int
    let hiddenCount: Int

    init(sessions: [Session]) {
        workingCount = sessions.filter { $0.state == .working || $0.state == .compacting }.count
        totalCount = sessions.count
        hiddenCount = sessions.filter(\.isHidden).count
    }

    var displayText: String {
        "\(workingCount)/\(totalCount) busy, \(hiddenCount) hidden"
    }
}
