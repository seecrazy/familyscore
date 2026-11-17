import Foundation
import CoreLocation
import UserNotifications
import SwiftData

/// 到家提醒（§18.4/§14.2）：围绕"家"坐标 100 米围栏，进入且有未完成待办时本地提醒
enum GeoReminder {

    struct ArrivalMessage: Equatable {
        let title: String
        let body: String
    }

    /// 纯逻辑：到家时是否提醒、提醒什么（可测）
    static func arrivalMessage(openTodoCount: Int, todoTitle: String?,
                               geoEnabled: Bool, minutesSinceLastFire: Int,
                               lastFireDate: Date?, now: Date = .now) -> ArrivalMessage? {
        guard geoEnabled, openTodoCount > 0 else { return nil }
        // 冷却：1 小时内不重复打扰（region 监控进出抖动保护）
        if let last = lastFireDate, now.timeIntervalSince(last) < TimeInterval(minutesSinceLastFire) * 60 {
            return nil
        }
        return ArrivalMessage(
            title: "到家啦，顺手打个卡？",
            body: todoTitle.map { "还有 \("待办")：\($0) —— 现在 2 分钟搞定 💪" }
                ?? "今天还有 \(openTodoCount) 件待办，趁刚到家清一件吧")
    }

    static func region(lat: Double, lon: Double) -> CLCircularRegion {
        let r = CLCircularRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                 radius: 100, identifier: "fs-home")
        r.notifyOnEntry = true
        r.notifyOnExit = false
        return r
    }

    /// 家坐标是否有效
    static func hasHome(_ family: Family) -> Bool {
        family.homeLat != nil && family.homeLon != nil
    }
}

/// 定位服务单例：设家、启停围栏监听
final class LocationService: NSObject, CLLocationManagerDelegate, ObservableObject {

    static let shared = LocationService()
    private let manager = CLLocationManager()
    private(set) var lastArrivalFire: Date?
    private var pendingSetHome: ((Bool) -> Void)?
    private weak var pendingFamily: Family?

    override private init() {
        super.init()
        manager.delegate = self
    }

    /// 一次性取当前位置设为"家"（§18.4 到家提醒配置）；结果经 delegate 异步送达
    func setHomeToCurrent(family: Family, completion: @escaping (Bool) -> Void) {
        manager.requestWhenInUseAuthorization()
        pendingSetHome = completion
        pendingFamily = family
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let done = pendingSetHome else { return }
        pendingSetHome = nil
        if let loc = locations.first, let f = pendingFamily {
            f.homeLat = loc.coordinate.latitude
            f.homeLon = loc.coordinate.longitude
            done(true)
        } else {
            done(false)
        }
        pendingFamily = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        pendingSetHome?(false)
        pendingSetHome = nil
        pendingFamily = nil
    }

    /// 启动到家围栏监听
    func startMonitoring(family: Family) {
        guard GeoReminder.hasHome(family) else { return }
        stopMonitoring()
        manager.startMonitoring(for: GeoReminder.region(lat: family.homeLat!, lon: family.homeLon!))
    }

    func stopMonitoring() {
        for r in manager.monitoredRegions { manager.stopMonitoring(for: r) }
    }

    /// CLMonitor/经典 region 委托
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == "fs-home" else { return }
        lastArrivalFire = .now
        NotificationCenter.default.post(name: .fsArrivedHome, object: nil)
    }
}

extension Notification.Name {
    static let fsArrivedHome = Notification.Name("fsArrivedHome")
}
