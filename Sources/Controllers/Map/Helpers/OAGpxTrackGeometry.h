#import <Foundation/Foundation.h>

#include <OsmAndCore/QtExtensions.h>
#include <QVector>
#include <OsmAndCore/CommonTypes.h>

@class OASGpxFile;

NS_ASSUME_NONNULL_BEGIN

/// Track and route polylines already converted to map coordinates.
/// Built once while the GPX file is parsed, then reused when the overlay is published.
@interface OAGpxTrackGeometry : NSObject

- (const QVector<QVector<OsmAnd::PointI>> &)trackSegments;
- (const QVector<int> &)trackSegmentColors;
- (const QVector<QVector<OsmAnd::PointI>> &)routes;
- (uint64_t)storedBytes;

+ (instancetype)geometryFromGpxFile:(OASGpxFile *)gpxFile;

@end

NS_ASSUME_NONNULL_END
