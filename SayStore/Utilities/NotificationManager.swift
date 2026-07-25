import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async -> Bool {
        guard await center.notificationSettings().authorizationStatus == .notDetermined else {
            return await center.notificationSettings().authorizationStatus == .authorized
        }
        let granted = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
        return granted ?? false
    }

    func scheduleExpiryNotification(for cert: CertificatePair) {
        guard let expiration = cert.expiration, let uuid = cert.uuid else { return }

        for days in [7, 3, 1] {
            guard let fireDate = Calendar.current.date(byAdding: .day, value: -days, to: expiration),
                  fireDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = cert.nickname ?? "Certificate"
            content.body = "Expires in \(days) day\(days == 1 ? "" : "s")"
            content.sound = .default

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: "cert-expiry-\(uuid)-\(days)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    func scheduleRevokedNotification(for cert: CertificatePair) {
        guard let uuid = cert.uuid else { return }

        let content = UNMutableNotificationContent()
        content.title = cert.nickname ?? "Certificate"
        content.body = "This certificate has been revoked. Apps signed with it may stop working."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "cert-revoked-\(uuid)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        center.add(request)
    }

    func removeNotifications(for cert: CertificatePair) {
        guard let uuid = cert.uuid else { return }
        let ids = ["cert-expiry-\(uuid)-7", "cert-expiry-\(uuid)-3", "cert-expiry-\(uuid)-1", "cert-revoked-\(uuid)"]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    func rescheduleAll(for certificates: [CertificatePair]) {
        center.removeAllPendingNotificationRequests()
        for cert in certificates {
            if cert.revoked == true {
                scheduleRevokedNotification(for: cert)
            } else {
                scheduleExpiryNotification(for: cert)
            }
        }
    }
}
