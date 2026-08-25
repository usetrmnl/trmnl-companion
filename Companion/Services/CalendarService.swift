//
//  CalendarService.swift
//  Companion
//
//  Created by Mustapha Tarek BEN LECHHAB on 23.08.2025.
//

import Foundation
import EventKit
import Observation

@Observable
class CalendarService {
    // Single EKEventStore instance for memory efficiency
    private let eventStore = EKEventStore()
    
    var authorizationStatus: EKAuthorizationStatus = .notDetermined
    var calendars: [EKCalendar] = []
    var isLoading = false
    
    static let shared = CalendarService()
    
    private init() {
        checkAuthorizationStatus()
    }
    
    func checkAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }
    
    func requestAccess() async -> Bool {
        do {
            if #available(iOS 17.0, *) {
                let granted = try await eventStore.requestFullAccessToEvents()
                await MainActor.run {
                    self.authorizationStatus = granted ? .fullAccess : .denied
                }
                if granted {
                    await loadCalendars()
                }
                return granted
            } else {
                let granted = try await eventStore.requestAccess(to: .event)
                await MainActor.run {
                    self.authorizationStatus = granted ? .authorized : .denied
                }
                if granted {
                    await loadCalendars()
                }
                return granted
            }
        } catch {
            await MainActor.run {
                self.authorizationStatus = .denied
            }
            return false
        }
    }
    
    func loadCalendars() async {
        await MainActor.run {
            self.isLoading = true
        }
        
        let allCalendars = eventStore.calendars(for: .event)
        
        await MainActor.run {
            self.calendars = allCalendars
            self.isLoading = false
        }
    }
    
    func fetchEvents(from selectedCalendarIds: Set<String>) async -> [EKEvent] {
        // In background mode, self.calendars might be empty, so fetch directly from event store
        var calendarsToUse = self.calendars.filter { selectedCalendarIds.contains($0.calendarIdentifier) }
        
        // If no calendars are loaded (e.g., in background mode), fetch them directly
        if calendarsToUse.isEmpty && !selectedCalendarIds.isEmpty {
            let allCalendars = eventStore.calendars(for: .event)
            calendarsToUse = allCalendars.filter { selectedCalendarIds.contains($0.calendarIdentifier) }
            
            // Also update the cached calendars if they were empty
            if self.calendars.isEmpty {
                await MainActor.run {
                    self.calendars = allCalendars
                }
            }
        }
        
        // Date range: today -6 days to today +40 days
        guard !calendarsToUse.isEmpty,
              let startDate = Calendar.current.date(byAdding: .day, value: -6, to: Date()),
              let endDate = Calendar.current.date(byAdding: .day, value: 40, to: Date())
        else {
            return []
        }

        // Create predicate for date range and calendars
        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: calendarsToUse
        )
        
        var events: [EKEvent] = []
        eventStore.enumerateEvents(matching: predicate) { event, stop in
            events.append(event)
        }
        return events
    }
    
    func hasCalendarAccess() -> Bool {
        if #available(iOS 17.0, *) {
            return authorizationStatus == .fullAccess
        } else {
            return authorizationStatus == .authorized
        }
    }
}
