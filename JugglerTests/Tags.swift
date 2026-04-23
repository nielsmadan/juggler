import Testing

extension Tag {
    /// Tests that hit the HTTP server, a terminal bridge, or other out-of-process resources.
    /// Excluded from the fast dev loop; run via `just test-all`.
    @Tag static var integration: Self

    @Tag static var slow: Self

    /// Tests that have historically been flaky — tag while investigating so they can be isolated.
    @Tag static var flaky: Self
}
