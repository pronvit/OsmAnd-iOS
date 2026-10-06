//
//  TripRecordingTimeWidget.swift
//  OsmAnd Maps
//
//  Created by Dmitry Svetlichny on 27.11.2025.
//  Copyright © 2025 OsmAnd. All rights reserved.
//

import Foundation

@objcMembers
final class TripRecordingTimeWidget: OASimpleWidget {
    private static let oneHourMillis: Int64 = 60 * 60 * 1000
    private let blinkDelay: TimeInterval = 0.5

    private let savingTrackHelper = OASavingTrackHelper.sharedInstance()

    private var cachedTimeSpan: Int64 = -1
    private var cachedLastUpdateTime: Int64 = 0

    init(customId: String?, appMode: OAApplicationMode, widgetParams: [String: Any]? = nil) {
        super.init(type: .tripRecordingTime)
        configurePrefs(withId: customId, appMode: appMode, widgetParams: widgetParams)
        updateInfo()
        onClickFunction = { [weak self] _ in
            guard let self, let plugin = self.getMonitoringPlugin() else { return }
            plugin.showTripRecordingDialog()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @discardableResult override func updateInfo() -> Bool {
        guard let plugin = getMonitoringPlugin() else { return true }
        guard let savingTrackHelper else { return true }
        if plugin.saving {
            setText(localizedString("shared_string_save"), subtext: nil)
            setIcon("widget_monitoring_rec_big")
            return true
        }

        let globalRecording = OAAppSettings.sharedManager().mapSettingTrackRecording
        let recording = savingTrackHelper.getIsRecording()
        let liveMonitoring = plugin.isLiveMonitoringEnabled()
        let timeSpan = getTimeSpan()
        if !recording && !hasCurrentTrack(timeSpan: timeSpan) {
            cachedTimeSpan = -1
            setText(localizedString("monitoring_control_start"), subtext: nil)
            setIcon("widget_monitoring_rec_inactive")
            return true
        }

        if cachedTimeSpan != timeSpan {
            cachedTimeSpan = timeSpan
            let formattedTime = OAOsmAndFormatter.getFormattedDurationShort(Double(timeSpan) / 1000, fullForm: false)
            setText(formattedTime, subtext: nil)
        }
        if !recording {
            setIcon("widget_monitoring_rec_inactive")
            return true
        }
        setRecordingIcons(globalRecording: globalRecording, liveMonitoring: liveMonitoring, recording: recording)

        var lastUpdateTime = cachedLastUpdateTime
        if savingTrackHelper.distance > 0 {
            lastUpdateTime = Int64(savingTrackHelper.lastTimeUpdated)
        }
        if lastUpdateTime != cachedLastUpdateTime && (globalRecording || recording) {
            cachedLastUpdateTime = lastUpdateTime
            setRecordingIcons(globalRecording: false, liveMonitoring: liveMonitoring, recording: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + blinkDelay) { [weak self] in
                guard let self, self.savingTrackHelper?.getIsRecording() == true else { return }
                self.setRecordingIcons(globalRecording: globalRecording,
                                       liveMonitoring: liveMonitoring,
                                       recording: !globalRecording)
            }
        }

        return true
    }

    override func configureContextMenu(addGroup: UIMenu, settingsGroup: UIMenu, deleteGroup: UIMenu) -> UIMenu {
        var updatedSettingsGroup = settingsGroup
        let resetAction = UIAction(title: localizedString("show_track_on_map"), image: .icCustomCenterOnTrack) { [weak self] _ in
            guard let self else { return }
            self.showTrackOnMap()
        }

        updatedSettingsGroup = settingsGroup.replacingChildren([resetAction] + settingsGroup.children)
        return UIMenu(title: "", children: [addGroup, updatedSettingsGroup, deleteGroup])
    }

    private func hasCurrentTrack(timeSpan: Int64) -> Bool {
        if savingTrackHelper?.hasData() == true || timeSpan > 0 {
            return true
        }
        guard let gpx = savingTrackHelper?.currentTrack else { return false }
        for trackObject in gpx.tracks {
            guard let track = trackObject as? Track else { continue }
            for segmentObject in track.segments {
                guard let segment = segmentObject as? TrkSegment, segment.points.count > 0 else { continue }
                return true
            }
        }
        return false
    }

    private func getTimeSpan() -> Int64 {
        guard let currentTrack = OASavingTrackHelper.sharedInstance().currentTrack else { return 0 }
        let joinSegments = OAAppSettings.sharedManager().currentTrackIsJoinSegments.get()
        let tracks = (currentTrack.tracks as? [Track]) ?? []
        let firstIsGeneral = tracks.first?.generalTrack ?? false
        let withoutGaps = !joinSegments && (tracks.isEmpty || firstIsGeneral)
        let analysis = currentTrack.getAnalysis(fileTimestamp: 0)
        return withoutGaps ? analysis.timeSpanWithoutGaps : analysis.timeSpan
    }

    private func setRecordingIcons(globalRecording: Bool, liveMonitoring: Bool, recording: Bool) {
        let iconName: String
        if globalRecording {
            iconName = liveMonitoring ? "widget_live_monitoring_rec_big" : "widget_monitoring_rec_big"
        } else if recording {
            iconName = liveMonitoring ? "widget_live_monitoring_rec_small" : "widget_monitoring_rec_small"
        } else {
            iconName = "widget_monitoring_rec_inactive"
        }

        setIcon(iconName)
    }

    private func getMonitoringPlugin() -> OAMonitoringPlugin? {
        OAPluginsHelper.getPlugin(OAMonitoringPlugin.self) as? OAMonitoringPlugin
    }

    private func showTrackOnMap() {
        OARootViewController.instance()?.mapPanel.openTargetView(withGPX: nil)
    }
}
