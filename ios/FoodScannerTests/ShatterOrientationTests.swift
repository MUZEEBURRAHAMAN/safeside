import Testing
import UIKit
@testable import FoodScanner

/// Chunk 6 (Task 5): the scan-success "shatter" snapshot must render upright
/// regardless of whether the video connection's portrait rotation was actually
/// applied. When the connection already rotated the buffer to portrait the
/// pixels are upright (`.up`); when it did NOT (landscape-native sensor, e.g.
/// `isVideoOrientationSupported == false`), the raw frame is rotated 90° and
/// must be corrected to portrait with `.right`.
@Suite("Shatter snapshot orientation")
struct ShatterOrientationTests {

    @Test("A portrait-rotated connection needs no correction (.up)")
    func portraitConnectionYieldsUp() {
        #expect(CameraViewController.shatterImageOrientation(connectionApplied: true) == .up)
    }

    @Test("An unrotated (landscape-native) buffer is corrected to portrait (.right)")
    func unrotatedBufferYieldsRight() {
        #expect(CameraViewController.shatterImageOrientation(connectionApplied: false) == .right)
    }
}
