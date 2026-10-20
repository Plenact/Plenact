import SwiftUI
import UserNotifications

/// An invitation opens a review; it never performs a task decision.
enum ReviewRhythmKind: String, Codable, CaseIterable {
    case daily, weekly
    var title: String { self == .daily ? "Make room for tomorrow" : "Make room for the coming week" }
    var message: String {
        self == .daily ? "Ready to decide what stays on the Table, goes into the Queue, or gets a day?"
            : "What in the Queue would you like to bring into the coming week?"
    }
    var notificationID: String { "Plenact.ReviewRhythm." + rawValue }
}
struct ReviewRhythmRoute: Identifiable {
    let id = UUID()
    let kind: ReviewRhythmKind
    let date: Date
}

struct ReviewRhythmPreferences: Codable, Equatable {
    var dailyInvitations = true
    var weeklyInvitations = true
    var dailyMinutes = 20 * 60 + 30
    var weeklyMinutes = 18 * 60
    var weeklyWeekday = 1 // Calendar weekday: Sunday.
    var dailyNotifications = false
    var weeklyNotifications = false
    func normalized() -> Self {
        var copy = self
        if !(0..<1440).contains(copy.dailyMinutes) { copy.dailyMinutes = 1230 }
        if !(0..<1440).contains(copy.weeklyMinutes) { copy.weeklyMinutes = 1080 }
        if !(1...7).contains(copy.weeklyWeekday) { copy.weeklyWeekday = 1 }
        return copy
    }
}
enum ReviewRhythmStore {
    static let key = "Plenact.ReviewRhythm.v1"
    static let dismissalsKey = "Plenact.ReviewRhythmDismissals.v1"
    static func load(from defaults: UserDefaults = .standard) -> ReviewRhythmPreferences {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(ReviewRhythmPreferences.self, from: data) else { return ReviewRhythmPreferences() }
        return value.normalized()
    }
    static func save(_ value: ReviewRhythmPreferences, to defaults: UserDefaults = .standard) throws {
        if defaults.object(forKey: key) != nil {
            guard let data = defaults.data(forKey: key) else { throw CocoaError(.fileReadCorruptFile) }
            _ = try JSONDecoder().decode(ReviewRhythmPreferences.self, from: data)
        }
        defaults.set(try JSONEncoder().encode(value.normalized()), forKey: key)
    }
    static func periodID(_ kind: ReviewRhythmKind, date: Date, calendar: Calendar) -> String {
        let key = kind == .daily ? PlanningDate.key(date, calendar: calendar) : PlanningDate.weekKey(date, calendar: calendar)
        return kind.rawValue + "|" + key + "|" + calendar.timeZone.identifier + "|" + String(calendar.firstWeekday)
    }
    static func isDue(_ kind: ReviewRhythmKind, now: Date, preferences: ReviewRhythmPreferences,
                      calendar: Calendar, completed: Bool, deferredUntil: Date?) -> Bool {
        guard !completed, deferredUntil.map({ $0 <= now }) ?? true else { return false }
        let value = preferences.normalized()
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        switch kind {
        case .daily: return value.dailyInvitations && minutes >= value.dailyMinutes
        case .weekly: return value.weeklyInvitations && calendar.component(.weekday, from: now) == value.weeklyWeekday && minutes >= value.weeklyMinutes
        }
    }
    static func deferInvitation(_ kind: ReviewRhythmKind, date: Date, calendar: Calendar,
                                until: Date, defaults: UserDefaults = .standard) {
        var values = (defaults.data(forKey: dismissalsKey).flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) }) ?? [:]
        values[periodID(kind, date: date, calendar: calendar)] = until
        if values.count > 64 {
            // The date component in each key retains recent periods, including permanent skips.
            let keys = values.keys.sorted {
                ($0.split(separator: "|").dropFirst().first ?? "") > ($1.split(separator: "|").dropFirst().first ?? "")
            }.prefix(64)
            values = values.filter { keys.contains($0.key) }
        }
        if let data = try? JSONEncoder().encode(values) { defaults.set(data, forKey: dismissalsKey) }
    }
    static func notificationRequests(_ value: ReviewRhythmPreferences) -> [UNNotificationRequest] {
        let value = value.normalized()
        return ReviewRhythmKind.allCases.compactMap { kind in
            guard kind == .daily ? value.dailyNotifications : value.weeklyNotifications else { return nil }
            let minutes = kind == .daily ? value.dailyMinutes : value.weeklyMinutes
            var components = DateComponents()
            components.hour = minutes / 60; components.minute = minutes % 60
            if kind == .weekly { components.weekday = value.weeklyWeekday }
            // No explicit time zone: these reminders follow local wall-clock time.
            let content = UNMutableNotificationContent()
            content.title = kind.title
            content.body = kind.message
            content.sound = .default
            content.userInfo = ["plenactReview": kind.rawValue]
            return UNNotificationRequest(identifier: kind.notificationID, content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true))
        }
    }
}

@MainActor
final class ReviewRhythmNotifications: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = ReviewRhythmNotifications()
    @Published var pending: ReviewRhythmRoute?
    private var isReconciling = false
    private var needsReconcile = false
    func install() { UNUserNotificationCenter.current().delegate = self }
    /// Permission is requested only after an explicit Save with a reminder switch enabled.
    func synchronize(requestPermission: Bool = false) async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        let preferences = ReviewRhythmStore.load()
        let wantsNotifications = preferences.dailyNotifications || preferences.weeklyNotifications
        var status = await center.notificationSettings().authorizationStatus
        if wantsNotifications && requestPermission && status == .notDetermined {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        // Serialize reconciliation, then read the latest saved choices again on a queued pass.
        if isReconciling { needsReconcile = true; return status == .authorized || status == .provisional }
        isReconciling = true
        defer { isReconciling = false }
        repeat {
            needsReconcile = false
            center.removePendingNotificationRequests(withIdentifiers: ReviewRhythmKind.allCases.map(\.notificationID))
            let latest = ReviewRhythmStore.load()
            if status == .authorized || status == .provisional || status == .ephemeral {
                for request in ReviewRhythmStore.notificationRequests(latest) { try await center.add(request) }
            }
        } while needsReconcile
        return !wantsNotifications || status == .authorized || status == .provisional || status == .ephemeral
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                           withCompletionHandler completionHandler: @escaping () -> Void) {
        if let raw = response.notification.request.content.userInfo["plenactReview"] as? String,
           let kind = ReviewRhythmKind(rawValue: raw) {
            let date = response.notification.date
            Task { @MainActor in self.pending = ReviewRhythmRoute(kind: kind, date: date) }
        }
        completionHandler()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

struct ReviewRhythmPanel: View {
    let onOpen: (ReviewRhythmRoute) -> Void
    let onSettings: () -> Void
    var defaults: UserDefaults = .standard
    var nowOverride: Date? = nil
    @Environment(\.planningCalendarAccess) private var access
    @AppStorage(ReviewRhythmStore.key) private var preferencesData = Data()
    @AppStorage(ReviewRhythmStore.dismissalsKey) private var dismissalsData = Data()
    @AppStorage(DailyPlanStore.key) private var dailyData = Data()
    @AppStorage(WeeklyReviewStore.key) private var weeklyData = Data()
    private var calendar: Calendar { access?.document.calendar ?? .current }
    private func due(_ kind: ReviewRhythmKind, at now: Date) -> Bool {
        let completed: Bool
        if kind == .daily {
            completed = (try? DailyPlanStore.load(from: defaults).plans[PlanningDate.key(now, calendar: calendar)]?.eveningReview?.completedAt) != nil
        } else {
            let id = WeeklyReviewRecord(date: now, calendar: calendar).id
            completed = (try? WeeklyReviewStore.load(from: defaults).records[id]?.completedAt) != nil
        }
        let deferred = (try? JSONDecoder().decode([String: Date].self, from: defaults.data(forKey: ReviewRhythmStore.dismissalsKey) ?? Data()))?[ReviewRhythmStore.periodID(kind, date: now, calendar: calendar)]
        return ReviewRhythmStore.isDue(kind, now: now, preferences: ReviewRhythmStore.load(from: defaults), calendar: calendar, completed: completed, deferredUntil: deferred)
    }
    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let now = nowOverride ?? timeline.date
            VStack(alignment: .leading, spacing: 12) {
                ForEach(ReviewRhythmKind.allCases.filter { due($0, at: now) }, id: \.self) { kind in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(kind.title).font(.headline)
                        Text(kind.message).font(.subheadline).foregroundStyle(.secondary)
                        HStack {
                            Button("Review now") { onOpen(ReviewRhythmRoute(kind: kind, date: now)) }
                                .buttonStyle(.borderedProminent)
                            Spacer()
                            Menu("Later", systemImage: "ellipsis") {
                                Button("Remind me here in one hour") {
                                    ReviewRhythmStore.deferInvitation(kind, date: now, calendar: calendar,
                                        until: now.addingTimeInterval(3600), defaults: defaults)
                                }
                                Button(kind == .daily ? "Skip today" : "Skip this week") {
                                    ReviewRhythmStore.deferInvitation(kind, date: now, calendar: calendar, until: .distantFuture, defaults: defaults)
                                }
                            }
                        }
                    }.padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
                HStack {
                    Menu("Planning rhythm", systemImage: "arrow.triangle.2.circlepath") {
                        Button("Review On the Table now") { onOpen(ReviewRhythmRoute(kind: .daily, date: now)) }
                        Button("Review In the Queue now") { onOpen(ReviewRhythmRoute(kind: .weekly, date: now)) }
                        Button("Review invitations & reminders", action: onSettings)
                    }.frame(minHeight: 44)
                    Spacer()
                }.font(.subheadline)
            }
        }
    }
}

struct ReviewRhythmDestination: View {
    let route: ReviewRhythmRoute
    @Environment(\.planningCalendarAccess) private var access
    var body: some View {
        if route.kind == .daily {
            TodayPlanView(date: route.date, calendar: access?.document.calendar ?? .current, opensEveningReview: true)
        } else {
            WeeklyReviewView(date: route.date, calendar: access?.document.calendar ?? .current)
        }
    }
}

struct ReviewRhythmSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var preferences = ReviewRhythmStore.load()
    @State private var saving = false
    @State private var error: String?
    private func time(_ key: WritableKeyPath<ReviewRhythmPreferences, Int>) -> Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: preferences[keyPath: key] / 60,
                minute: preferences[keyPath: key] % 60, second: 0, of: .now) ?? .now
        }, set: { date in
            preferences[keyPath: key] = Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
        })
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Daily · On the Table") {
                    Toggle("Offer an evening review on Today", isOn: $preferences.dailyInvitations)
                    DatePicker("Evening time", selection: time(\.dailyMinutes), displayedComponents: .hourAndMinute)
                    Toggle("Send an evening notification", isOn: $preferences.dailyNotifications)
                }
                Section("Weekly · In the Queue") {
                    Toggle("Offer a weekly review on Today", isOn: $preferences.weeklyInvitations)
                    Picker("Review day", selection: $preferences.weeklyWeekday) {
                        ForEach(1...7, id: \.self) { Text(Calendar.current.weekdaySymbols[$0 - 1]).tag($0) }
                    }
                    DatePicker("Weekly time", selection: time(\.weeklyMinutes), displayedComponents: .hourAndMinute)
                    Toggle("Send a weekly notification", isOn: $preferences.weeklyNotifications)
                }
                Section {
                    Text("Invitations help you decide; they never move or complete an item. Keep work, choose another day, return it to the Queue, or let it go. Neither list has to be empty.")
                    Text("Notifications are optional and use local time. They repeat at your chosen times, even if you already reviewed or skipped the in-app invitation. Later postpones only the invitation on Today. Nothing is sent to another person.")
                        .foregroundStyle(.secondary)
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.secondary)
                        Button("Open iOS notification settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                }
            }
            .navigationTitle("Review rhythm").navigationBarTitleDisplayMode(.inline)
            .disabled(saving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        Task { @MainActor in
                            defer { saving = false }
                            do {
                                try ReviewRhythmStore.save(preferences)
                                if try await ReviewRhythmNotifications.shared.synchronize(requestPermission: true) { dismiss() }
                                else { error = "Your choices are saved. iOS notifications are not allowed; invitations on Today still work. You can allow notifications in iOS Settings or turn the notification switches off." }
                            } catch { self.error = "Could not finish saving reminders: \(error.localizedDescription). Your Cards and Notes are unchanged." }
                        }
                    }.disabled(saving)
                }
            }
            .interactiveDismissDisabled(saving)
        }
    }
}
