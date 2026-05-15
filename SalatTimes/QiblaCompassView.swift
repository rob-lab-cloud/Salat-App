import SwiftUI
import CoreLocation

// MARK: - Qibla Calculator
struct QiblaCalculator {
    /// Returns the bearing in degrees (0–360) from the given coordinate toward the Kaaba
    static func bearing(from coordinate: CLLocationCoordinate2D) -> Double {
        let kaabaLat = 21.4225 * .pi / 180
        let kaabaLng = 39.8262 * .pi / 180
        let userLat  = coordinate.latitude  * .pi / 180
        let userLng  = coordinate.longitude * .pi / 180

        let dLng = kaabaLng - userLng
        let y = sin(dLng) * cos(kaabaLat)
        let x = cos(userLat) * sin(kaabaLat) - sin(userLat) * cos(kaabaLat) * cos(dLng)
        let bearing = atan2(y, x) * 180 / .pi
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }
}

// MARK: - Compass Manager
class CompassManager: NSObject, ObservableObject {
    @Published var heading: Double = 0          // device heading (true north when available)
    @Published var qiblaAngle: Double = 0        // bearing to Kaaba from true north
    @Published var isAvailable: Bool = false

    private let locationManager = CLLocationManager()
    private var coordinate: CLLocationCoordinate2D?
    private var isRunning = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.headingFilter = 1
    }

    func start(coordinate: CLLocationCoordinate2D) {
        // Avoid stacking heading subscriptions when coordinate changes.
        if isRunning { stop() }
        self.coordinate = coordinate
        qiblaAngle = QiblaCalculator.bearing(from: coordinate)
        isAvailable = CLLocationManager.headingAvailable()
        guard isAvailable else { return }
        locationManager.startUpdatingHeading()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        locationManager.stopUpdatingHeading()
        isRunning = false
    }
}

extension CompassManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Use true heading when the device has a valid location fix; otherwise
        // fall back to magnetic heading (qiblaAngle is true-north based, so
        // trueHeading is the correct reference frame).
        let h = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        DispatchQueue.main.async {
            self.heading = (h + 360).truncatingRemainder(dividingBy: 360)
        }
    }
}

// MARK: - QiblaCompassView (compact, fits in header area)
struct QiblaCompassView: View {
    @StateObject private var compass = CompassManager()
    let coordinate: CLLocationCoordinate2D?

    /// Arrow points toward Qibla — rotated so that the arrow always aims at Kaaba
    private var needleRotation: Double {
        guard coordinate != nil else { return 0 }
        return compass.qiblaAngle - compass.heading
    }

    /// Combined lat/lng key so onChange fires for either component.
    private var coordinateKey: String {
        guard let c = coordinate else { return "" }
        return "\(c.latitude),\(c.longitude)"
    }

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color(hex: "D4AF37").opacity(0.5), Color(hex: "D4AF37").opacity(0.1)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .frame(width: 42, height: 42)

            // Cardinal marks
            ForEach([0, 90, 180, 270], id: \.self) { deg in
                Rectangle()
                    .fill(Color(hex: "D4AF37").opacity(deg == 0 ? 0.7 : 0.25))
                    .frame(width: 1, height: deg == 0 ? 4 : 3)
                    .offset(y: -18)
                    .rotationEffect(.degrees(Double(deg)))
            }

            // N label
            Text("N")
                .font(.system(size: 6, weight: .semibold))
                .foregroundColor(Color(hex: "D4AF37").opacity(0.6))
                .offset(y: -12)

            // Qibla needle (Kaaba arrow)
            QiblaNeedle()
                .scaleEffect(0.65)
                .rotationEffect(.degrees(needleRotation))
                .animation(.interpolatingSpring(stiffness: 60, damping: 12), value: needleRotation)

            // Center dot
            Circle()
                .fill(Color(hex: "D4AF37"))
                .frame(width: 4, height: 4)

            // Kaaba icon at tip when aligned
            if abs(needleRotation.truncatingRemainder(dividingBy: 360)) < 10
                || abs(needleRotation.truncatingRemainder(dividingBy: 360)) > 350 {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 7))
                    .foregroundColor(Color(hex: "F5D07A"))
                    .offset(y: -14)
                    .rotationEffect(.degrees(needleRotation))
                    .animation(.interpolatingSpring(stiffness: 60, damping: 12), value: needleRotation)
            }
        }
        .frame(width: 42, height: 42)
        .onAppear {
            if let coord = coordinate { compass.start(coordinate: coord) }
        }
        .onDisappear { compass.stop() }
        .onChange(of: coordinateKey) { _, _ in
            if let coord = coordinate { compass.start(coordinate: coord) }
        }
    }
}

// MARK: - Needle Shape
struct QiblaNeedle: View {
    var body: some View {
        ZStack {
            // Tip (gold, toward Qibla)
            Triangle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "F5D07A"), Color(hex: "B8860B")],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 8, height: 22)
                .offset(y: -11)

            // Tail (dimmed)
            Triangle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 6, height: 14)
                .rotationEffect(.degrees(180))
                .offset(y: 7)
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}
