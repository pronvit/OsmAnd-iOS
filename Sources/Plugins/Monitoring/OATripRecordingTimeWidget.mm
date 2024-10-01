//
//  OATripRecordingTimeWidget.m
//  OsmAnd Maps
//
//  Created by nnngrach on 02.04.2023.
//  Copyright © 2023 OsmAnd. All rights reserved.
//


#import "OATripRecordingTimeWidget.h"
#import "OASavingTrackHelper.h"
#import "OAOsmAndFormatter.h"
#import "OsmAndApp.h"
#import "OAAppSettings.h"
#import "Localization.h"
#import "OAGPXDatabase.h"
#import "OARootViewController.h"
#import "OAMapPanelViewController.h"
#import "OATrackMenuHudViewController.h"
#import "OsmAnd_Maps-Swift.h"

@implementation OATripRecordingTimeWidget

- (instancetype _Nonnull)initWithPlugin:(OAMonitoringPlugin *)plugin
							   customId:(NSString *_Nullable)customId
								appMode:(OAApplicationMode * _Nonnull)appMode
						   widgetParams:(NSDictionary * _Nullable)widgetParams;
{
    self = [super initWithType:OAWidgetType.tripRecordingTime];
    if (self)
    {
        [self configurePrefsWithId:customId appMode:appMode widgetParams:widgetParams];
        __weak OATextInfoWidget *weakSelf = self;
		__weak OAMonitoringPlugin *pluginWeak = plugin;
		long __block cachedLastUpdateTime;
		long __block cachedTimeSpan = -1;

		self.updateInfoFunction = ^BOOL {
			if (pluginWeak.saving)
			{
				[weakSelf setText:OALocalizedString(@"shared_string_save") subtext:@""];
				[weakSelf setIcon:@"widget_monitoring_rec_big"];
				return YES;
			}
			NSString *d;
			long last = cachedLastUpdateTime;
			BOOL globalRecord = [OAAppSettings sharedManager].mapSettingTrackRecording;
			BOOL isRecording = [OASavingTrackHelper sharedInstance].getIsRecording;
			float dist = [OASavingTrackHelper sharedInstance].distance;

			if (isRecording || globalRecord || dist > 0)
			{
				OASGpxFile *currentTrack = [OASavingTrackHelper sharedInstance].currentTrack;
				BOOL withoutGaps = ![[OAAppSettings sharedManager].currentTrackIsJoinSegments get] &&
				((!currentTrack.tracks || currentTrack.tracks.count == 0) || currentTrack.tracks[0].generalTrack);

				OASGpxTrackAnalysis *analysis = [currentTrack getAnalysisFileTimestamp:0];
				long timeSpan =  withoutGaps ? analysis.timeSpanWithoutGaps : analysis.timeSpan;

				if (cachedTimeSpan != timeSpan)
				{
					cachedTimeSpan = timeSpan;
					NSString *formattedTime = [OAOsmAndFormatter getFormattedDurationShort:timeSpan / 1000 fullForm:NO];
					[weakSelf setText:formattedTime subtext:nil];
				}
			}
			else
			{
				cachedTimeSpan = -1;
				[weakSelf setText:OALocalizedString(@"monitoring_control_start") subtext:nil];
			}

			BOOL liveMonitoringEnabled = [pluginWeak isLiveMonitoringEnabled];
			if (globalRecord)
			{
				//indicates global recording (+background recording)
				d = liveMonitoringEnabled ? @"widget_live_monitoring_rec_big" : @"widget_monitoring_rec_big";
			}
			else if (isRecording)
			{
				//indicates (profile-based, configured in settings) recording (looks like is only active during nav in follow mode)
				d = liveMonitoringEnabled ? @"widget_live_monitoring_rec_small" : @"widget_monitoring_rec_small";
			}
			else
			{
				d = @"widget_monitoring_rec_inactive";
			}

			[weakSelf setIcon:d];
			if ((last != cachedLastUpdateTime) && (globalRecord || isRecording))
			{
				cachedLastUpdateTime = last;
				//blink implementation with 2 indicator states (global logging + profile/navigation logging)
				if (liveMonitoringEnabled)
				{
					d = @"widget_live_monitoring_rec_small";
				}
				else
				{
					d = @"widget_monitoring_rec_small";
				}
				[weakSelf setIcon:d];

				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
					NSString *d = globalRecord
											? (liveMonitoringEnabled ? @"widget_live_monitoring_rec_big" : @"widget_monitoring_rec_big")
											: (liveMonitoringEnabled ? @"widget_live_monitoring_rec_small" : @"widget_monitoring_rec_small");

					[weakSelf setIcon:d];
				});
			}
			return YES;
		};
        
        self.onClickFunction = ^(id sender) {
			[pluginWeak showTripRecordingDialog];
        };
        
        [self updateInfo];
    }
    return self;
}

+ (NSString *) getName
{
    return [NSString stringWithFormat:@"%@ - %@", OALocalizedString(@"record_plugin_name"), OALocalizedString(@"map_widget_trip_recording_duration")];
}

@end
