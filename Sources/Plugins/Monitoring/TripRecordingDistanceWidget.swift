//
//  TripRecordingDistanceWidget.swift
//  OsmAnd Maps
//
//  Created by Dmitry Svetlichny on 25.11.2025.
//  Copyright © 2025 OsmAnd. All rights reserved.
//

import Foundation

@objcMembers
final class TripRecordingDistanceWidget: BaseRecordingWidget {
    private let savingTrackHelper = OASavingTrackHelper.sharedInstance()
    
    private var widgetState: TripRecordingDistanceWidgetState?
    
    init(customId: String?, appMode: OAApplicationMode, widgetParams: [String: Any]? = nil) {
        super.init(type: .tripRecordingDistance)
        self.widgetState = TripRecordingDistanceWidgetState(customId: customId, widgetType: .tripRecordingDistance, widgetParams: widgetParams)
        configurePrefs(withId: customId, appMode: appMode, widgetParams: widgetParams)
        updateInfo()
        onClickFunction = { [weak self] _ in
            guard let self, let gpxFile = self.savingTrackHelper?.currentTrack else { return }
            let trackItem = TrackItem(gpxFile: gpxFile)
            OARootViewController.instance().mapPanel.openTargetView(withGPX: trackItem, selectedTab: .segmentsTab, selectedStatisticsTab: .overviewTab, openedFromMap: true)
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @discardableResult override func updateInfo() -> Bool {
        super.updateInfo()
        guard let savingTrackHelper else { return true }
        guard savingTrackHelper.getIsRecording() || hasCurrentTrack() else {
            setText(nil, subtext: nil)
            return true
        }
        
        let recordingDistanceMode = currentMode()
        if recordingDistanceMode == .totalDistance {
            setDistanceText(savingTrackHelper.distance)
        } else {
            updateLastSlopeDistance(mode: recordingDistanceMode)
        }
        
        updateTitleAndIcon()
        return true
    }
    
    override func getSettingsData(_ appMode: OAApplicationMode, widgetConfigurationParams: [String: Any]?, isCreate: Bool) -> OATableDataModel? {
        let data = OATableDataModel()
        guard let pref = widgetState?.getDistanceModePreference() else { return data }
        let section = data.createNewSection()
        section.headerText = localizedString("shared_string_settings")
        let modeRow = section.createNewRow()
        modeRow.cellType = OAButtonTableViewCell.reuseIdentifier
        modeRow.key = "recording_widget_mode_key"
        modeRow.title = localizedString("shared_string_mode")
        modeRow.setObj(pref, forKey: "pref")
        var currentRaw = TripRecordingDistanceMode.totalDistance.rawValue
        if isCreate, let widgetConfigurationParams, let str = widgetConfigurationParams[pref.key] as? String, let v = Int(str) {
            currentRaw = v
        } else if !isCreate {
            currentRaw = Int(pref.get(appMode))
        }
        
        let currentMode = TripRecordingDistanceMode(rawValue: currentRaw) ?? .totalDistance
        modeRow.setObj(localizedString(currentMode.titleKey), forKey: "value")
        let possibleValues: [OATableRowData] = [TripRecordingDistanceMode.totalDistance, .lastDownhill, .lastUphill].map { mode in
            let row = OATableRowData()
            row.cellType = OASimpleTableViewCell.reuseIdentifier
            row.setObj(mode.rawValue, forKey: "value")
            row.title = localizedString(mode.titleKey)
            return row
        }
        
        modeRow.setObj(possibleValues, forKey: "possible_values")
        return data
    }
    
    override func getIconName() -> String? {
        currentMode().iconName
    }
    
    override func resolvedModeTitleKeyForList() -> String? {
        currentMode().titleKey
    }
    
    private func hasCurrentTrack() -> Bool {
        if savingTrackHelper?.hasData() == true {
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

    private func updateLastSlopeDistance(mode: TripRecordingDistanceMode) {
        if let lastSlope = getLastSlope(isUphill: mode == .lastUphill) {
            setDistanceText(Float(lastSlope.distance))
        } else {
            setDistanceText(0)
        }
    }
    
    private func setDistanceText(_ distance: Float) {
        let parts = OAOsmAndFormatter.getFormattedDistance(distance).components(separatedBy: " ")
        setText(parts.first, subtext: parts.dropFirst().last)
    }
    
    private func updateTitleAndIcon() {
        let mode = currentMode()
        let baseTitle = widgetType?.title ?? ""
        let modeTitle = localizedString(mode == .totalDistance ? "shared_string_total" : mode.titleKey)
        let format = localizedString("ltr_or_rtl_combine_via_colon")
        let fullTitle = String(format: format, baseTitle, modeTitle)
        setContentTitle(fullTitle)
        setIcon(mode == .totalDistance ? "widget_trip_recording" : mode.iconName)
        
        configureSimpleLayout()
    }
    
    private func currentMode() -> TripRecordingDistanceMode {
        guard let pref = widgetState?.getDistanceModePreference() else { return .totalDistance }
        return TripRecordingDistanceMode(rawValue: Int(pref.get())) ?? .totalDistance
    }
}
