import CoreGraphics
import Testing

@testable import TylerCore

/// The modifier is Option. Every press is at (100, 100), over a window tyler may move, or in a gap
/// when it takes gaps, unless a case says otherwise.
@Suite("ModifierGesture")
struct ModifierGestureTests {
  enum Event: Sendable {
    case press(MouseButton, ModifierKeys = .option)
    case drag(MouseButton, CGFloat, CGFloat)
    case release(MouseButton, CGFloat, CGFloat)
    case tapOff
  }

  struct Case: CustomTestStringConvertible, Sendable {
    let name: String
    var modifier = ModifierKeys.option
    var takesGaps = false
    var canCapture = true
    let events: [Event]
    let verdicts: [ModifierGesture.Verdict]
    let actions: [ModifierGesture.Action]

    var testDescription: String { name }
  }

  static let start = CGPoint(x: 100, y: 100)

  @Test(arguments: [
    Case(
      name: "a click is replayed",
      events: [.press(.left), .drag(.left, 102, 101), .release(.left, 102, 101)],
      verdicts: [.swallow, .swallow, .swallow], actions: [.replayClick]),
    Case(
      name: "a left drag moves",
      events: [
        .press(.left), .drag(.left, 104, 100), .drag(.left, 150, 120), .release(.left, 160, 120),
      ],
      verdicts: [.swallow, .swallow, .swallow, .swallow],
      actions: [
        .began(.move, start: start), .moved(CGPoint(x: 104, y: 100)),
        .moved(CGPoint(x: 150, y: 120)), .ended(CGPoint(x: 160, y: 120)),
      ]),
    Case(
      name: "a right drag resizes",
      events: [.press(.right), .drag(.right, 90, 90), .release(.right, 90, 90)],
      verdicts: [.swallow, .swallow, .swallow],
      actions: [
        .began(.resize, start: start), .moved(CGPoint(x: 90, y: 90)),
        .ended(CGPoint(x: 90, y: 90)),
      ]),
    Case(
      name: "other keys pass",
      events: [
        .press(.left, [.option, .shift]), .drag(.left, 150, 100), .release(.left, 150, 100),
      ],
      verdicts: [.pass, .pass, .pass], actions: []),
    Case(
      name: "no keys pass",
      events: [.press(.left, []), .release(.left, 100, 100)], verdicts: [.pass, .pass], actions: []),
    Case(
      name: "nothing to capture passes", canCapture: false,
      events: [.press(.left), .drag(.left, 150, 100), .release(.left, 150, 100)],
      verdicts: [.pass, .pass, .pass], actions: []),
    Case(
      name: "turned off passes", modifier: [],
      events: [.press(.left, []), .drag(.left, 150, 100)], verdicts: [.pass, .pass], actions: []),
    Case(
      name: "the other button mid-drag is swallowed and ignored",
      events: [
        .press(.left), .drag(.left, 150, 100), .press(.right), .drag(.right, 300, 300),
        .release(.right, 300, 300), .release(.left, 160, 100),
      ],
      verdicts: [.swallow, .swallow, .swallow, .swallow, .swallow, .swallow],
      actions: [
        .began(.move, start: start), .moved(CGPoint(x: 150, y: 100)),
        .ended(CGPoint(x: 160, y: 100)),
      ]),
    Case(
      name: "the other button's release doesn't end a held press",
      events: [.press(.left), .release(.right, 100, 100), .release(.left, 100, 100)],
      verdicts: [.swallow, .swallow, .swallow], actions: [.replayClick]),
    Case(
      name: "letting go of the keys mid-drag keeps the drag",
      events: [
        .press(.left), .drag(.left, 150, 100), .press(.left, []), .release(.left, 150, 100),
      ],
      verdicts: [.swallow, .swallow, .swallow, .swallow],
      actions: [
        .began(.move, start: start), .moved(CGPoint(x: 150, y: 100)),
        .ended(CGPoint(x: 150, y: 100)),
      ]),
    Case(
      name: "a slow tap drops a held press",
      events: [.press(.left), .tapOff, .release(.left, 100, 100)],
      verdicts: [.swallow, .pass], actions: []),
    Case(
      name: "a slow tap ends a drag where it was",
      events: [.press(.left), .drag(.left, 150, 100), .tapOff, .drag(.left, 200, 100)],
      verdicts: [.swallow, .swallow, .pass],
      actions: [
        .began(.move, start: start), .moved(CGPoint(x: 150, y: 100)),
        .ended(CGPoint(x: 150, y: 100)),
      ]),
    Case(
      name: "a left drag with no keys moves a gap's divider", takesGaps: true,
      events: [.press(.left, []), .drag(.left, 140, 100), .release(.left, 150, 100)],
      verdicts: [.swallow, .swallow, .swallow],
      actions: [
        .began(.gap, start: start), .moved(CGPoint(x: 140, y: 100)),
        .ended(CGPoint(x: 150, y: 100)),
      ]),
    Case(
      name: "a click in a gap is replayed", takesGaps: true,
      events: [.press(.left, []), .release(.left, 100, 100)],
      verdicts: [.swallow, .swallow], actions: [.replayClick]),
    Case(
      name: "gaps are taken with the modifier turned off", modifier: [], takesGaps: true,
      events: [.press(.left, []), .drag(.left, 150, 100), .release(.left, 150, 100)],
      verdicts: [.swallow, .swallow, .swallow],
      actions: [
        .began(.gap, start: start), .moved(CGPoint(x: 150, y: 100)),
        .ended(CGPoint(x: 150, y: 100)),
      ]),
    Case(
      name: "a right press with no keys passes a gap", takesGaps: true,
      events: [.press(.right, []), .drag(.right, 150, 100), .release(.right, 150, 100)],
      verdicts: [.pass, .pass, .pass], actions: []),
    Case(
      name: "a press with other keys passes a gap", takesGaps: true,
      events: [.press(.left, [.shift]), .drag(.left, 150, 100)], verdicts: [.pass, .pass],
      actions: []),
    Case(
      name: "a press outside a gap passes", takesGaps: true, canCapture: false,
      events: [.press(.left, []), .drag(.left, 150, 100)], verdicts: [.pass, .pass], actions: []),
    Case(
      name: "the modifier still moves when gaps are taken", takesGaps: true,
      events: [.press(.left), .drag(.left, 150, 100), .release(.left, 150, 100)],
      verdicts: [.swallow, .swallow, .swallow],
      actions: [
        .began(.move, start: start), .moved(CGPoint(x: 150, y: 100)),
        .ended(CGPoint(x: 150, y: 100)),
      ]),
    Case(
      name: "after a gesture the next press starts afresh",
      events: [
        .press(.left), .release(.left, 100, 100), .press(.left, []), .release(.left, 100, 100),
      ],
      verdicts: [.swallow, .swallow, .pass, .pass], actions: [.replayClick]),
  ])
  func decidesWhatToSwallowAndDo(_ test: Case) {
    var gesture = ModifierGesture(modifier: test.modifier, takesGaps: test.takesGaps)
    var verdicts: [ModifierGesture.Verdict] = []
    var actions: [ModifierGesture.Action] = []
    for event in test.events {
      switch event {
      case .press(let button, let keys):
        verdicts.append(
          gesture.pressed(button, at: Self.start, keys: keys) { _ in test.canCapture })
      case .drag(let button, let horizontal, let vertical):
        let (verdict, done) = gesture.dragged(button, to: CGPoint(x: horizontal, y: vertical))
        verdicts.append(verdict)
        actions += done
      case .release(let button, let horizontal, let vertical):
        let (verdict, done) = gesture.released(button, at: CGPoint(x: horizontal, y: vertical))
        verdicts.append(verdict)
        actions += done
      case .tapOff:
        actions += gesture.tapTurnedOff()
      }
    }
    #expect(verdicts == test.verdicts)
    #expect(actions == test.actions)
    #expect(!gesture.isActive || test.events.count < 2)
  }

  @Test func asksWhetherItCanCaptureOnlyWhenTheKeysMatch() {
    var gesture = ModifierGesture(modifier: .option)
    var asked = 0
    _ = gesture.pressed(.left, at: Self.start, keys: [.command]) { _ in
      asked += 1
      return true
    }
    #expect(asked == 0)
  }

  @Test(arguments: [
    (MouseButton.left, ModifierKeys.option, ModifierGesture.Kind.move),
    (.right, .option, .resize),
    (.left, ModifierKeys(), .gap),
  ])
  func asksAboutTheKindThePressWouldStart(
    button: MouseButton, keys: ModifierKeys, kind: ModifierGesture.Kind
  ) {
    var gesture = ModifierGesture(modifier: .option, takesGaps: true)
    var asked: [ModifierGesture.Kind] = []
    _ = gesture.pressed(button, at: Self.start, keys: keys) {
      asked.append($0)
      return true
    }
    #expect(asked == [kind])
  }
}
