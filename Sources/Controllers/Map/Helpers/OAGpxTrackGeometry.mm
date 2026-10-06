#import "OAGpxTrackGeometry.h"

#import "OAGPXDatabase.h"
#import "OsmAndSharedWrapper.h"
#import "OsmAnd_Maps-Swift.h"

#include <OsmAndCore/Utilities.h>

@implementation OAGpxTrackGeometry
{
	QVector<QVector<OsmAnd::PointI>> _trackSegments;
	QVector<int> _trackSegmentColors;
	QVector<QVector<OsmAnd::PointI>> _routes;
}

- (const QVector<QVector<OsmAnd::PointI>> &)trackSegments
{
	return _trackSegments;
}

- (const QVector<int> &)trackSegmentColors
{
	return _trackSegmentColors;
}

- (const QVector<QVector<OsmAnd::PointI>> &)routes
{
	return _routes;
}

- (uint64_t)storedBytes
{
	uint64_t bytes = (uint64_t)_trackSegmentColors.size() * sizeof(int);
	for (const auto &segment : _trackSegments)
		bytes += (uint64_t)segment.size() * sizeof(OsmAnd::PointI);
	for (const auto &route : _routes)
		bytes += (uint64_t)route.size() * sizeof(OsmAnd::PointI);
	return bytes;
}

+ (instancetype)geometryFromGpxFile:(OASGpxFile *)gpxFile
{
	OAGpxTrackGeometry *geometry = [OAGpxTrackGeometry new];
	if (!gpxFile)
		return geometry;

	if (gpxFile.hasTrkPt)
	{
		for (OASTrack *track in [gpxFile getTracksIncludeGeneralTrack:NO])
		{
			OASInt *color = [[OASInt alloc] initWithInt:(int)kDefaultTrackColor];
			const int colorArgb = [[track getColorDefColor:color] intValue];
			for (OASTrkSegment *segment in track.segments)
			{
				QVector<OsmAnd::PointI> points;
				points.reserve((int)segment.points.count);
				for (OASWptPt *point in segment.points)
					points.push_back(OsmAnd::Utilities::convertLatLonTo31(OsmAnd::LatLon(point.lat, point.lon)));
				if (points.size() > 1)
				{
					geometry->_trackSegments.push_back(points);
					geometry->_trackSegmentColors.push_back(colorArgb);
				}
			}
		}
	}
	else if (gpxFile.hasRtePt)
	{
		for (OASRoute *route in gpxFile.routes)
		{
			QVector<OsmAnd::PointI> points;
			points.reserve((int)route.points.count);
			for (OASWptPt *point in route.points)
				points.push_back(OsmAnd::Utilities::convertLatLonTo31(OsmAnd::LatLon(point.lat, point.lon)));
			if (points.size() > 1)
				geometry->_routes.push_back(points);
		}
	}
	return geometry;
}

@end
