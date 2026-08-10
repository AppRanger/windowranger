import XCTest

final class WorkspaceSwipeStateMachineTests: XCTestCase {
    func testThreeFingerLeftSwipeEmitsNextOnlyOnceUntilGestureEnds() {
        var state = WorkspaceSwipeStateMachine(fingerCount: .three)

        XCTAssertTrue(state.handle(.touches(touches(x: 0.50))).isEmpty)
        XCTAssertTrue(state.handle(.touches(touches(x: 0.47))).isEmpty)
        XCTAssertEqual(
            state.handle(.touches(touches(x: 0.44))),
            [.switchWorkspace(.next)]
        )
        XCTAssertTrue(state.handle(.touches(touches(x: 0.30))).isEmpty)

        XCTAssertTrue(state.handle(.ended).isEmpty)
        XCTAssertTrue(state.handle(.touches(touches(x: 0.50))).isEmpty)
        XCTAssertEqual(
            state.handle(.touches(touches(x: 0.56))),
            [.switchWorkspace(.previous)]
        )
    }

    func testFourFingerConfigurationRejectsThreeFingerSwipe() {
        var state = WorkspaceSwipeStateMachine(fingerCount: .four)

        XCTAssertTrue(state.handle(.touches(touches(count: 3, x: 0.50))).isEmpty)
        XCTAssertTrue(state.handle(.touches(touches(count: 3, x: 0.30))).isEmpty)
        XCTAssertTrue(state.handle(.ended).isEmpty)
        XCTAssertTrue(state.handle(.touches(touches(count: 4, x: 0.50))).isEmpty)
        XCTAssertEqual(
            state.handle(.touches(touches(count: 4, x: 0.56))),
            [.switchWorkspace(.previous)]
        )
    }

    func testFingerCountChangeMidGestureCancelsUntilAllTouchesEnd() {
        var state = WorkspaceSwipeStateMachine(fingerCount: .three)

        XCTAssertTrue(state.handle(.touches(touches(x: 0.50))).isEmpty)
        XCTAssertTrue(state.handle(.touches(touches(count: 2, x: 0.47))).isEmpty)
        XCTAssertTrue(state.handle(.touches(touches(x: 0.30))).isEmpty)
        XCTAssertTrue(state.handle(.ended).isEmpty)
        XCTAssertTrue(state.handle(.touches(touches(x: 0.50))).isEmpty)
        XCTAssertEqual(
            state.handle(.touches(touches(x: 0.44))),
            [.switchWorkspace(.next)]
        )
    }

    func testVerticalMovementDoesNotSwitchWorkspace() {
        var state = WorkspaceSwipeStateMachine(fingerCount: .three)

        XCTAssertTrue(state.handle(.touches(touches(x: 0.50, y: 0.50))).isEmpty)
        XCTAssertTrue(state.handle(.touches(touches(x: 0.49, y: 0.44))).isEmpty)
        XCTAssertTrue(state.handle(.touches(touches(x: 0.35, y: 0.30))).isEmpty)
    }

    private func touches(
        count: Int = 3,
        x: CGFloat,
        y: CGFloat = 0.5
    ) -> [WorkspaceSwipeTouch] {
        (0..<count).map {
            WorkspaceSwipeTouch(
                identity: "touch-\($0)",
                normalizedPosition: CGPoint(x: x, y: y)
            )
        }
    }
}

@MainActor
final class WorkspaceSwipeControllerTests: XCTestCase {
    private final class FakeMonitor: WorkspaceSwipeEventMonitoring {
        var canStart = true
        var startCount = 0
        var stopCount = 0
        var inputHandler: InputHandler?
        var runtimeIssueHandler: RuntimeIssueHandler?

        func start(
            inputHandler: @escaping InputHandler,
            runtimeIssueHandler: @escaping RuntimeIssueHandler
        ) -> Bool {
            startCount += 1
            guard canStart else { return false }
            self.inputHandler = inputHandler
            self.runtimeIssueHandler = runtimeIssueHandler
            return true
        }

        func stop() {
            stopCount += 1
            inputHandler = nil
            runtimeIssueHandler = nil
        }

        func send(_ input: WorkspaceSwipeInput) {
            inputHandler?(input)
        }
    }

    func testControllerStartsOnlyWhenEnabledAndDispatchesThroughSharedCommandPath() {
        let monitor = FakeMonitor()
        var commands: [(WindowManagerCommand, String)] = []
        let dispatcher = WindowManagerCommandDispatcher { command, correlation in
            commands.append((command, correlation))
        }
        let controller = WorkspaceSwipeController(
            monitor: monitor,
            dispatcher: dispatcher
        )

        controller.update(enabled: false, fingerCount: .three)
        XCTAssertEqual(monitor.startCount, 0)
        controller.update(enabled: true, fingerCount: .three)
        XCTAssertEqual(monitor.startCount, 1)

        monitor.send(.touches(touches(x: 0.50)))
        monitor.send(.touches(touches(x: 0.44)))
        monitor.send(.touches(touches(x: 0.30)))

        XCTAssertEqual(commands.map(\.0), [.cycleWorkspace(1)])
    }

    func testControllerSuspensionStopsAndThenRestartsMonitoring() {
        let monitor = FakeMonitor()
        let dispatcher = WindowManagerCommandDispatcher { _, _ in }
        let controller = WorkspaceSwipeController(
            monitor: monitor,
            dispatcher: dispatcher
        )
        controller.update(enabled: true, fingerCount: .three)

        controller.setSuppressed(true, reason: "test")
        XCTAssertEqual(monitor.stopCount, 1)
        controller.setSuppressed(true, reason: "test")
        XCTAssertEqual(monitor.stopCount, 1)
        controller.setSuppressed(false, reason: "test")
        XCTAssertEqual(monitor.startCount, 2)
    }

    func testControllerReportsUnavailableMonitorAndFailsClosed() {
        let monitor = FakeMonitor()
        monitor.canStart = false
        let dispatcher = WindowManagerCommandDispatcher { _, _ in
            XCTFail("An unavailable monitor must not dispatch")
        }
        let controller = WorkspaceSwipeController(
            monitor: monitor,
            dispatcher: dispatcher
        )
        var issues: [String?] = []
        controller.runtimeIssueChanged = { issues.append($0) }

        controller.update(enabled: true, fingerCount: .four)

        XCTAssertEqual(monitor.startCount, 1)
        XCTAssertNotNil(issues.last ?? nil)
    }

    private func touches(x: CGFloat) -> [WorkspaceSwipeTouch] {
        (0..<3).map {
            WorkspaceSwipeTouch(
                identity: "touch-\($0)",
                normalizedPosition: CGPoint(x: x, y: 0.5)
            )
        }
    }
}
