//
//  HorizonApp.swift
//  Horizon
//
//  Created by 吴铠涵 on 2026/10/1.
//

import SwiftUI

@main
struct HorizonApp: App {
    @State private var settings: AppSettings = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["CLASH_SUBSCRIPTIONS_DEMO"] == "1",
           ProcessInfo.processInfo.environment["CLASH_STARTUP_AUDIT"] != nil,
           let style = ProcessInfo.processInfo.environment["CLASH_STARTUP_STYLE"],
           let defaults = UserDefaults(suiteName: "Clash.StartupAudit") {
            defaults.removePersistentDomain(forName: "Clash.StartupAudit")
            defaults.set(style, forKey: "ui.interfaceStyle")
            return AppSettings(defaults: defaults)
        }
        #endif
        return AppSettings()
    }()
    @State private var tunnel: TunnelController = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["CLASH_SUBSCRIPTIONS_DEMO"] == "1" { return SubscriptionDemo.controller() }
        #endif
        return TunnelController()
    }()
    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.environment["CLASH_HORIZON_PREVIEW"] == "1" {
                    HorizonScenePreviewView()
                } else if ProcessInfo.processInfo.environment["CLASH_CHART_PREVIEW"] == "1" {
                    TrafficPlotPreview()
                } else { RootTabView(tunnel: tunnel) }
                #else
                RootTabView(tunnel: tunnel)
                #endif
            }
                .environment(settings)
                .environment(\.locale, settings.locale)
                .preferredColorScheme(settings.colorScheme)
        }
    }
}
