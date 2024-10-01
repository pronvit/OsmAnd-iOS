//
//  OATripRecordingDistanceWidget.m
//  OsmAnd Maps
//
//  Created by nnngrach on 30.03.2023.
//  Copyright © 2023 OsmAnd. All rights reserved.
//

#import "OATripRecordingDistanceWidget.h"
#import "OASavingTrackHelper.h"
#import "OAMonitoringPlugin.h"
#import "OAOsmAndFormatter.h"
#import "OsmAndApp.h"
#import "OAAppSettings.h"
#import "Localization.h"
#import "OsmAnd_Maps-Swift.h"

@implementation OATripRecordingDistanceWidget

- (instancetype)initWithPlugin:(OAMonitoringPlugin *)plugin
                               customId:(NSString *)customId
                                appMode:(OAApplicationMode *)appMode
                           widgetParams:(NSDictionary *)widgetParams;
{
    self = [super initWithType:OAWidgetType.tripRecordingDistance];
    if (self)
    {
        [self configurePrefsWithId:customId appMode:appMode widgetParams:widgetParams];
        __weak OATextInfoWidget *weakSelf = self;

		self.updateInfoFunction = ^BOOL {
			[weakSelf setIcon:@"widget_trip_recording"];

			NSString *txt = nil;
			NSString *subtxt = nil;
			BOOL globalRecord = [OAAppSettings sharedManager].mapSettingTrackRecording;
			BOOL isRecording = [OASavingTrackHelper sharedInstance].getIsRecording;
			float dist = [OASavingTrackHelper sharedInstance].distance;

			if (isRecording || globalRecord || dist > 0)
			{
				NSString *ds = [OAOsmAndFormatter getFormattedDistance:dist];
				int ls = [ds lastIndexOf:@" "];
				if (ls == -1)
				{
					txt = ds;
				}
				else
				{
					txt = [ds substringToIndex:ls];
					subtxt = [ds substringFromIndex:ls + 1];
				}
			}
			[weakSelf setText:txt subtext:subtxt];
			return YES;
		};

        [self updateInfo];
        
		self.onClickFunction = ^(id sender) {
			OASGpxFile *gpxFile = [OASavingTrackHelper sharedInstance].currentTrack;
			OASTrackItem *trackItem = [[OASTrackItem alloc] initWithGpxFile:gpxFile];
			[[OARootViewController instance].mapPanel openTargetViewWithGPX:trackItem selectedTab:EOATrackMenuHudSegmentsTab selectedStatisticsTab:EOATrackMenuHudSegmentsStatisticsOverviewTab openedFromMap:YES];
		};
    }
    return self;
}

+ (NSString *) getName
{
    return [NSString stringWithFormat:@"%@ - %@", OALocalizedString(@"record_plugin_name"), OALocalizedString(@"map_widget_trip_recording_distance")];
}

@end
