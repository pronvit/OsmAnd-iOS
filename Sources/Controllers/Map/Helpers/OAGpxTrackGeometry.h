#import <Foundation/Foundation.h>

#include <OsmAndCore/QtExtensions.h>
#include <QVector>
#include <OsmAndCore/CommonTypes.h>

@class OASGpxFile, OASWptPt;

FOUNDATION_EXPORT const void * const OAGpxWaypointFilePathKey;

NS_ASSUME_NONNULL_BEGIN

/// Map representation of one GPX file.
/// Track points are packed columns (map position, elevation, speed, and sensor values
/// only when the file actually has them). Named waypoints stay as objects.
/// The parsed file is not retained with this geometry.
@interface OAGpxTrackGeometry : NSObject

- (const QVector<QVector<OsmAnd::PointI>> &)trackSegments;
- (const QVector<int> &)trackSegmentColors;
- (const QVector<QVector<OsmAnd::PointI>> &)routes;

- (BOOL)hasTrackPoints;
- (BOOL)hasRoutePoints;
- (BOOL)hasElevation;
- (double)minElevation;
- (double)maxElevation;
- (float)maxSpeed;

- (float)elevationForSegment:(NSInteger)segment index:(NSInteger)index routes:(BOOL)routes;
- (float)speedForSegment:(NSInteger)segment index:(NSInteger)index routes:(BOOL)routes;
- (BOOL)hasSensorType:(NSInteger)type routes:(BOOL)routes;
- (float)sensorForSegment:(NSInteger)segment index:(NSInteger)index type:(NSInteger)type routes:(BOOL)routes;

- (NSArray<OASWptPt *> *)waypoints;
- (BOOL)isWaypointGroupHidden:(nullable NSString *)category;
- (void)replaceWaypointsFromGpxFile:(OASGpxFile *)gpxFile;

- (uint64_t)storedBytes;

+ (instancetype)geometryFromGpxFile:(OASGpxFile *)gpxFile path:(nullable NSString *)path;

@end

NS_ASSUME_NONNULL_END
