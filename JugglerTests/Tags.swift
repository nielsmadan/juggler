import Testing

extension Tag {
    /// Tests that hit the HTTP server, a terminal bridge, or other out-of-process resources.
    /// Excluded from the fast dev loop; run via `just test-all`.
    @Tag static var integration: Self

    // periphery:ignore - reserved for tagging slow tests
    @Tag static var slow: Self

    /// Tests that have historically been flaky — tag while investigating so they can be isolated.
    // periphery:ignore - reserved for investigating flaky tests
    @Tag static var flaky: Self

    /// Resource-hygiene / performance guards (thread & fd leaks, idle CPU). Deterministic
    /// but heavier than a unit test; run via `just test-perf` (e.g. on a weekly schedule).
    @Tag static var performance: Self
}
