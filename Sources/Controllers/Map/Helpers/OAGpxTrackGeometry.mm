#import "OAGpxTrackGeometry.h"

#import "OAGPXDatabase.h"
#import "OsmAndSharedWrapper.h"
#import "OsmAnd_Maps-Swift.h"

#include <OsmAndCore/Utilities.h>
#include <objc/runtime.h>

const void * const OAGpxWaypointFilePathKey = &OAGpxWaypointFilePathKey;

static const int kSensorHeartRate = 0;
static const int kSensorCadence = 1;
static const int kSensorPower = 2;
static const int kSensorAirTemperature = 3;
static const int kSensorWaterTemperature = 4;
static const int kSensorSpeed = 5;
static const int kSensorCount = 6;

static int OAGpxSensorIndexForType(NSInteger type)
{
	switch (type)
	{
		case EOAGPX3DLineVisualizationByTypeHeartRate:
			return kSensorHeartRate;
		case EOAGPX3DLineVisualizationByTypeBicycleCadence:
			return kSensorCadence;
		case EOAGPX3DLineVisualizationByTypeBicyclePower:
			return kSensorPower;
		case EOAGPX3DLineVisualizationByTypeTemperatureA:
			return kSensorAirTemperature;
		case EOAGPX3DLineVisualizationByTypeTemperatureW:
			return kSensorWaterTemperature;
		case EOAGPX3DLineVisualizationByTypeSpeedSensor:
			return kSensorSpeed;
		default:
			return -1;
	}
}

static float OAGpxSensorValue(OASWptPt *point, int sensor)
{
	OASPointAttributes *attributes = point.attributes;
	if (attributes)
	{
		switch (sensor)
		{
			case kSensorHeartRate:
				return attributes.heartRate;
			case kSensorCadence:
				return attributes.bikeCadence;
			case kSensorPower:
				return attributes.bikePower;
			case kSensorAirTemperature:
				return attributes.airTemperature;
			case kSensorWaterTemperature:
				return attributes.waterTemperature;
			case kSensorSpeed:
				return attributes.sensorSpeed;
			default:
				return 0;
		}
	}

	OASSensorPointAnalyser *analyser = OASSensorPointAnalyser.shared;
	switch (sensor)
	{
		case kSensorHeartRate:
			return [analyser getPointAttributeWptPt:point key:OASPointAttributes.sensorTagHeartRate defaultValue:0];
		case kSensorCadence:
			return [analyser getPointAttributeWptPt:point key:OASPointAttributes.sensorTagCadence defaultValue:0];
		case kSensorPower:
			return [analyser getPointAttributeWptPt:point key:OASPointAttributes.sensorTagBikePower defaultValue:0];
		case kSensorAirTemperature:
			return [analyser getPointAttributeWptPt:point key:OASPointAttributes.sensorTagTemperatureA defaultValue:NAN];
		case kSensorWaterTemperature:
			return [analyser getPointAttributeWptPt:point key:OASPointAttributes.sensorTagTemperatureW defaultValue:NAN];
		case kSensorSpeed:
			return [analyser getPointAttributeWptPt:point key:OASPointAttributes.sensorTagSpeed defaultValue:0];
		default:
			return 0;
	}
}

@implementation OAGpxTrackGeometry
{
	QVector<QVector<OsmAnd::PointI>> _trackSegments;
	QVector<int> _trackSegmentColors;
	QVector<QVector<float>> _segmentElevations;
	QVector<QVector<float>> _segmentSpeeds;
	QVector<QVector<float>> _sensorColumns[kSensorCount];
	bool _sensorPresent[kSensorCount];
	QVector<QVector<OsmAnd::PointI>> _routes;
	QVector<QVector<float>> _routeElevations;
	QVector<QVector<float>> _routeSpeeds;
	QVector<QVector<float>> _routeSensorColumns[kSensorCount];
	bool _routeSensorPresent[kSensorCount];
	NSArray<OASWptPt *> *_waypoints;
	NSSet<NSString *> *_hiddenPointGroups;
	NSString *_filePath;
	BOOL _hasElevation;
	double _minElevation;
	double _maxElevation;
	float _maxSpeed;
	BOOL _hasBounds;
	double _boundsLeft;
	double _boundsTop;
	double _boundsRight;
	double _boundsBottom;
}

- (instancetype)init
{
	self = [super init];
	if (self)
	{
		_waypoints = @[];
		_hiddenPointGroups = [NSSet set];
		_minElevation = NAN;
		_maxElevation = NAN;
		for (int i = 0; i < kSensorCount; i++)
		{
			_sensorPresent[i] = false;
			_routeSensorPresent[i] = false;
		}
	}
	return self;
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

- (BOOL)hasTrackPoints
{
	return !_trackSegments.isEmpty();
}

- (BOOL)hasRoutePoints
{
	return !_routes.isEmpty();
}

- (BOOL)hasElevation
{
	return _hasElevation;
}

- (double)minElevation
{
	return _minElevation;
}

- (double)maxElevation
{
	return _maxElevation;
}

- (float)maxSpeed
{
	return _maxSpeed;
}

- (float)columnValue:(const QVector<QVector<float>> &)columns segment:(NSInteger)segment index:(NSInteger)index
{
	if (segment < 0 || segment >= columns.size())
		return NAN;
	const auto &values = columns[(int)segment];
	if (index < 0 || index >= values.size())
		return NAN;
	return values[(int)index];
}

- (float)elevationForSegment:(NSInteger)segment index:(NSInteger)index routes:(BOOL)routes
{
	return [self columnValue:routes ? _routeElevations : _segmentElevations segment:segment index:index];
}

- (float)speedForSegment:(NSInteger)segment index:(NSInteger)index routes:(BOOL)routes
{
	return [self columnValue:routes ? _routeSpeeds : _segmentSpeeds segment:segment index:index];
}

- (BOOL)hasSensorType:(NSInteger)type routes:(BOOL)routes
{
	const int sensor = OAGpxSensorIndexForType(type);
	if (sensor < 0)
		return NO;
	return routes ? _routeSensorPresent[sensor] : _sensorPresent[sensor];
}

- (float)sensorForSegment:(NSInteger)segment index:(NSInteger)index type:(NSInteger)type routes:(BOOL)routes
{
	const int sensor = OAGpxSensorIndexForType(type);
	if (sensor < 0)
		return NAN;
	if (!(routes ? _routeSensorPresent[sensor] : _sensorPresent[sensor]))
		return NAN;
	return [self columnValue:routes ? _routeSensorColumns[sensor] : _sensorColumns[sensor] segment:segment index:index];
}

- (NSArray<OASWptPt *> *)waypoints
{
	return _waypoints;
}

- (BOOL)isWaypointGroupHidden:(NSString *)category
{
	return [_hiddenPointGroups containsObject:category ?: @""];
}

- (uint64_t)storedBytes
{
	uint64_t bytes = (uint64_t)_trackSegmentColors.size() * sizeof(int);
	for (const auto &segment : _trackSegments)
		bytes += (uint64_t)segment.size() * sizeof(OsmAnd::PointI);
	for (const auto &segment : _segmentElevations)
		bytes += (uint64_t)segment.size() * sizeof(float);
	for (const auto &segment : _segmentSpeeds)
		bytes += (uint64_t)segment.size() * sizeof(float);
	for (int i = 0; i < kSensorCount; i++)
	{
		for (const auto &segment : _sensorColumns[i])
			bytes += (uint64_t)segment.size() * sizeof(float);
		for (const auto &segment : _routeSensorColumns[i])
			bytes += (uint64_t)segment.size() * sizeof(float);
	}
	for (const auto &route : _routes)
		bytes += (uint64_t)route.size() * sizeof(OsmAnd::PointI);
	for (const auto &segment : _routeElevations)
		bytes += (uint64_t)segment.size() * sizeof(float);
	for (const auto &segment : _routeSpeeds)
		bytes += (uint64_t)segment.size() * sizeof(float);
	return bytes;
}

- (void)includeLatitude:(double)latitude longitude:(double)longitude
{
	if (!_hasBounds)
	{
		_boundsLeft = longitude;
		_boundsRight = longitude;
		_boundsTop = latitude;
		_boundsBottom = latitude;
		_hasBounds = YES;
		return;
	}
	_boundsLeft = MIN(_boundsLeft, longitude);
	_boundsRight = MAX(_boundsRight, longitude);
	_boundsTop = MAX(_boundsTop, latitude);
	_boundsBottom = MIN(_boundsBottom, latitude);
}

- (void)includeElevation:(float)elevation speed:(float)speed
{
	if (!isnan(elevation))
	{
		if (!_hasElevation)
		{
			_minElevation = elevation;
			_maxElevation = elevation;
			_hasElevation = YES;
		}
		else
		{
			_minElevation = MIN(_minElevation, (double)elevation);
			_maxElevation = MAX(_maxElevation, (double)elevation);
		}
	}
	if (speed > 0 && isfinite(speed))
		_maxSpeed = MAX(_maxSpeed, speed);
}

- (NSArray<OASWptPt *> *)waypointCopiesFromFile:(OASGpxFile *)gpxFile
{
	NSMutableArray<OASWptPt *> *waypoints = [NSMutableArray array];
	for (OASWptPt *point in [gpxFile getPointsList])
	{
		@autoreleasepool {
			OASWptPt *copy = [[OASWptPt alloc] initWithWptPt:point];
			if (_filePath.length > 0)
				objc_setAssociatedObject(copy, OAGpxWaypointFilePathKey, _filePath, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			[waypoints addObject:copy];
			[self includeLatitude:copy.lat longitude:copy.lon];
		}
	}
	return [waypoints copy];
}

- (NSSet<NSString *> *)hiddenGroupsFromFile:(OASGpxFile *)gpxFile
{
	NSMutableSet<NSString *> *hidden = [NSMutableSet set];
	NSDictionary<NSString *, OASGpxUtilitiesPointsGroup *> *groups = gpxFile.pointsGroups;
	for (NSString *name in groups)
	{
		OASGpxUtilitiesPointsGroup *group = groups[name];
		if (group.hidden)
			[hidden addObject:name ?: @""];
	}
	return [hidden copy];
}

- (void)replaceWaypointsFromGpxFile:(OASGpxFile *)gpxFile
{
	if (!gpxFile)
		return;
	_hiddenPointGroups = [self hiddenGroupsFromFile:gpxFile];
	_waypoints = [self waypointCopiesFromFile:gpxFile];
}

- (void)appendPoint:(OASWptPt *)point
			 points:(QVector<OsmAnd::PointI> &)points
		 elevations:(QVector<float> &)elevations
			 speeds:(QVector<float> &)speeds
			sensors:(QVector<float> *)sensors
		 storeSensor:(const bool *)storeSensor
{
	[self includeLatitude:point.lat longitude:point.lon];
	points.push_back(OsmAnd::Utilities::convertLatLonTo31(OsmAnd::LatLon(point.lat, point.lon)));
	const float elevation = isnan(point.ele) ? NAN : (float)point.ele;
	const float speed = point.attributes ? point.attributes.speed : point.speed;
	elevations.push_back(elevation);
	speeds.push_back(speed);
	[self includeElevation:elevation speed:speed];
	for (int sensor = 0; sensor < kSensorCount; sensor++)
	{
		if (!storeSensor[sensor])
			continue;
		sensors[sensor].push_back(OAGpxSensorValue(point, sensor));
	}
}

- (void)buildFromGpxFile:(OASGpxFile *)gpxFile
{
	if (!gpxFile)
		return;

	if (_filePath.length == 0 && gpxFile.path.length > 0)
		_filePath = [gpxFile.path copy];
	bool storeSensor[kSensorCount] = {};
	OASGpxTrackAnalysis *analysis = nil;
	if (gpxFile.hasTrkPt)
	{
		analysis = [gpxFile getAnalysisFileTimestamp:0];
		if (analysis)
		{
			storeSensor[kSensorHeartRate] = analysis.maxSensorHr > 0;
			storeSensor[kSensorCadence] = analysis.maxSensorCadence > 0;
			storeSensor[kSensorPower] = analysis.maxSensorPower > 0;
			storeSensor[kSensorSpeed] = analysis.maxSensorSpeed > 0;
			storeSensor[kSensorAirTemperature] = analysis.maxSensorTemperature > 0;
			storeSensor[kSensorWaterTemperature] = analysis.maxSensorTemperature > 0;
		}
	}

	if (gpxFile.hasTrkPt)
	{
		for (OASTrack *track in [gpxFile getTracksIncludeGeneralTrack:NO])
		{
			OASInt *color = [[OASInt alloc] initWithInt:(int)kDefaultTrackColor];
			const int colorArgb = [[track getColorDefColor:color] intValue];
			for (OASTrkSegment *segment in track.segments)
			{
				const BOOL storeLine = segment.points.count > 1 && !segment.generalSegment;
				QVector<OsmAnd::PointI> points;
				QVector<float> elevations;
				QVector<float> speeds;
				QVector<float> sensors[kSensorCount];
				if (storeLine)
				{
					const int count = (int)segment.points.count;
					points.reserve(count);
					elevations.reserve(count);
					speeds.reserve(count);
					for (int sensor = 0; sensor < kSensorCount; sensor++)
					{
						if (storeSensor[sensor])
							sensors[sensor].reserve(count);
					}
				}
				for (OASWptPt *point in segment.points)
				{
					@autoreleasepool {
						if (!storeLine)
						{
							[self includeLatitude:point.lat longitude:point.lon];
							continue;
						}
						[self appendPoint:point points:points elevations:elevations speeds:speeds sensors:sensors storeSensor:storeSensor];
					}
				}
				if (points.size() > 1)
				{
					_trackSegments.push_back(points);
					_trackSegmentColors.push_back(colorArgb);
					_segmentElevations.push_back(elevations);
					_segmentSpeeds.push_back(speeds);
					for (int sensor = 0; sensor < kSensorCount; sensor++)
					{
						if (storeSensor[sensor])
							_sensorColumns[sensor].push_back(sensors[sensor]);
					}
				}
			}
		}
		for (int sensor = 0; sensor < kSensorCount; sensor++)
			_sensorPresent[sensor] = storeSensor[sensor] && !_sensorColumns[sensor].isEmpty();
	}
	else if (gpxFile.hasRtePt)
	{
		bool routeSensor[kSensorCount] = {};
		for (OASRoute *route in gpxFile.routes)
		{
			QVector<OsmAnd::PointI> points;
			QVector<float> elevations;
			QVector<float> speeds;
			QVector<float> sensors[kSensorCount];
			const int count = (int)route.points.count;
			if (count > 1)
			{
				points.reserve(count);
				elevations.reserve(count);
				speeds.reserve(count);
			}
			for (OASWptPt *point in route.points)
			{
				@autoreleasepool {
					[self includeLatitude:point.lat longitude:point.lon];
					if (count <= 1)
						continue;
					for (int sensor = 0; sensor < kSensorCount; sensor++)
					{
						const float value = OAGpxSensorValue(point, sensor);
						const BOOL present = sensor == kSensorAirTemperature || sensor == kSensorWaterTemperature
							? !isnan(value) && value != 0
							: value > 0;
						if (present)
							routeSensor[sensor] = true;
					}
					bool storeAll[kSensorCount] = {true, true, true, true, true, true};
					[self appendPoint:point points:points elevations:elevations speeds:speeds sensors:sensors storeSensor:storeAll];
				}
			}
			if (points.size() > 1)
			{
				_routes.push_back(points);
				_routeElevations.push_back(elevations);
				_routeSpeeds.push_back(speeds);
				for (int sensor = 0; sensor < kSensorCount; sensor++)
					_routeSensorColumns[sensor].push_back(sensors[sensor]);
			}
		}
		for (int sensor = 0; sensor < kSensorCount; sensor++)
		{
			if (!routeSensor[sensor])
				_routeSensorColumns[sensor].clear();
			_routeSensorPresent[sensor] = routeSensor[sensor] && !_routeSensorColumns[sensor].isEmpty();
		}
	}

	_hiddenPointGroups = [self hiddenGroupsFromFile:gpxFile];
	_waypoints = [self waypointCopiesFromFile:gpxFile];
}

+ (instancetype)geometryFromGpxFile:(OASGpxFile *)gpxFile path:(NSString *)path
{
	OAGpxTrackGeometry *geometry = [OAGpxTrackGeometry new];
	geometry->_filePath = [path copy];
	[geometry buildFromGpxFile:gpxFile];
	return geometry;
}

@end
