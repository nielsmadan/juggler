import Testing

extension Tag {
    /// Tests that hit the HTTP server, a terminal bridge, or other out-of-process resources.
    @Tag static var integration: Self

    // periphery:ignore - reserved for tagging slow tests
    @Tag static var slow: Self

    // periphery:ignore - reserved for investigating flaky tests that need isolating
    @Tag static var flaky: Self

    /// Idle-CPU and leak regression guards, kept out of the fast loop; run via `just test-perf`.
    @Tag static var performance: Self
}
