//
//  OASelectedGPXHelper.m
//  OsmAnd
//
//  Created by Alexey Kulish on 24/08/2017.
//  Copyright © 2017 OsmAnd. All rights reserved.
//

// OsmAnd/src/net/osmand/plus/views/layers/MapSelectionHelper.java
// git revision 14c59e54e11dd340f5cbf9ea99b9f2a85ae9c644

#import "OASelectedGPXHelper.h"
#import "OAGpxTrackGeometry.h"
#import "OAAppSettings.h"
#import "OsmAndApp.h"
#import "OAGPXDatabase.h"
#import "OAObservable.h"
#import "OsmAndSharedWrapper.h"
#import "OsmAnd_Maps-Swift.h"
#import "OASavingTrackHelper.h"
#import "OAUtilities.h"

#include <objc/runtime.h>

static NSString *kBackupSuffix = @"_osmand_backup";

@implementation OASelectedGPXHelper
{
    OAAppSettings *_settings;
    OsmAndAppInstance _app;
    
    NSMutableArray *_selectedGPXFilesBackup;
    NSMutableArray *_loadingGPXPaths;
    NSMutableDictionary<NSString *, OASGpxFile *> *_activeGpx;
    NSMutableDictionary<NSString *, OAGpxTrackGeometry *> *_geometries;
    NSOperationQueue *_operationQueue;
}

+ (OASelectedGPXHelper *)instance
{
    static dispatch_once_t once;
    static OASelectedGPXHelper * sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

+ (BOOL)isGeometryCacheEnabled
{
    // The map stores packed geometry directly. This flag is the old side cache, which still kept the file.
    return NO;
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _app = [OsmAndApp instance];
        _settings = [OAAppSettings sharedManager];
        _selectedGPXFilesBackup = [NSMutableArray new];
        _activeGpx = [NSMutableDictionary dictionary];
        _geometries = [NSMutableDictionary dictionary];
        _loadingGPXPaths = [NSMutableArray new];
        _operationQueue = [[NSOperationQueue alloc] init];
        _operationQueue.maxConcurrentOperationCount = 4;
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didReceiveMemoryWarning:)
                                                     name:UIApplicationDidReceiveMemoryWarningNotification
                                                   object:nil];
    }
    return self;
}

- (NSDictionary<NSString *, OASGpxFile *> *)activeGpx
{
    return [_activeGpx copy];
}

- (NSString *)canonicalGpxPath:(NSString *)path
{
    if (path.length == 0)
        return @"";
    NSString *absolute = [[OAUtilities absoluteGpxPathForPath:path] stringByStandardizingPath];
    return absolute.decomposedStringWithCanonicalMapping;
}

- (BOOL)path:(NSString *)path refersToSameTrackAs:(NSString *)other
{
    NSString *left = [self canonicalGpxPath:path];
    NSString *right = [self canonicalGpxPath:other];
    return left.length > 0 && [left isEqualToString:right];
}

- (NSArray<NSString *> *)storedKeysMatchingPath:(NSString *)path
{
    if (path.length == 0)
        return @[];
    NSMutableArray<NSString *> *matches = [NSMutableArray array];
    NSMutableSet<NSString *> *keys = [NSMutableSet setWithArray:_activeGpx.allKeys];
    [keys addObjectsFromArray:_geometries.allKeys];
    for (NSString *key in keys)
    {
        if ([self path:path refersToSameTrackAs:key])
            [matches addObject:key];
    }
    return matches;
}

- (void)removeGpxFileWith:(NSString *)path {
    NSArray<NSString *> *matches = [self storedKeysMatchingPath:path];
    if (matches.count == 0 && path.length > 0)
        matches = @[path];
    [_activeGpx removeObjectsForKeys:matches];
    [_geometries removeObjectsForKeys:matches];
}

- (void)addGpxFile:(OASGpxFile *)file for:(NSString *)path
{
    // One explicit file (plan route, travel guide, promoted temp track) stays editable.
    // The map still draws the packed geometry, so publishing it does not walk every point.
    // Replace the key the map already displays. A standardized save path must not leave the old line in place.
    NSArray<NSString *> *matches = [self storedKeysMatchingPath:path];
    NSString *key = matches.firstObject ?: path;
    for (NSUInteger index = 1; index < matches.count; index++)
    {
        [_activeGpx removeObjectForKey:matches[index]];
        [_geometries removeObjectForKey:matches[index]];
    }
    if (key.length == 0)
        return;
    if (file)
    {
        _activeGpx[key] = file;
        _geometries[key] = [OAGpxTrackGeometry geometryFromGpxFile:file path:key];
    }
    else
    {
        [_activeGpx removeObjectForKey:key];
        [_geometries removeObjectForKey:key];
    }
}

- (BOOL)isLoading
{
    return _loadingGPXPaths.count > 0;
}

- (NSDictionary<NSString *, OAGpxTrackGeometry *> *)geometries
{
    return [_geometries copy];
}

- (OAGpxTrackGeometry *)geometryForPath:(NSString *)path
{
    OAGpxTrackGeometry *geometry = _geometries[path];
    if (geometry)
        return geometry;
    for (NSString *key in [self storedKeysMatchingPath:path])
    {
        geometry = _geometries[key];
        if (geometry)
            return geometry;
    }
    return nil;
}

- (BOOL)replaceDisplayedGeometry:(OAGpxTrackGeometry *)geometry forPath:(NSString *)path
{
    if (geometry == nil)
        return NO;
    NSArray<NSString *> *matches = [self storedKeysMatchingPath:path];
    if (matches.count == 0)
        return NO;
    NSString *key = matches.firstObject;
    for (NSUInteger index = 1; index < matches.count; index++)
        [_geometries removeObjectForKey:matches[index]];
    _geometries[key] = geometry;
    return YES;
}

- (void)replaceWaypointsOnGeometryForPath:(NSString *)path fromFile:(OASGpxFile *)file
{
    if (!file)
        return;
    NSArray<NSString *> *matches = [self storedKeysMatchingPath:path];
    if (matches.count == 0 && path.length > 0)
        matches = @[path];
    for (NSString *key in matches)
        [_geometries[key] replaceWaypointsFromGpxFile:file];
}

- (nullable OASGpxFile *)getGpxFileFor:(NSString *)path
{
    if (path.length == 0)
        return nil;
    OASGpxFile *file = _activeGpx[path];
    if (file)
        return file;
    for (NSString *key in [self storedKeysMatchingPath:path])
    {
        file = _activeGpx[key];
        if (file)
            return file;
    }
    NSString *absolute = [OAUtilities absoluteGpxPathForPath:path];
    if (![[NSFileManager defaultManager] fileExistsAtPath:absolute])
        return nil;
    OASKFile *kFile = [[OASKFile alloc] initWithFilePath:absolute];
    return [OASGpxUtilities.shared loadGpxFileFile:kFile];
}

- (nullable OASGpxFile *)activeGpxFileForPath:(NSString *)path fallbackPath:(nullable NSString *)fallbackPath
{
    NSDictionary<NSString *, OASGpxFile *> *activeGpx = self.activeGpx;
    OASGpxFile *activeGpxFile = activeGpx[path];
    if (activeGpxFile == nil && fallbackPath.length > 0)
        activeGpxFile = activeGpx[fallbackPath];
    if (activeGpxFile == nil && path.lastPathComponent.length > 0)
        activeGpxFile = activeGpx[path.lastPathComponent];
    if (activeGpxFile == nil && fallbackPath.lastPathComponent.length > 0)
        activeGpxFile = activeGpx[fallbackPath.lastPathComponent];

    return activeGpxFile;
}

- (BOOL)containsGpxFileWith:(NSString *)path
{
    if (_activeGpx[path] != nil || _geometries[path] != nil)
        return YES;
    return [self storedKeysMatchingPath:path].count > 0;
}

- (void)markTrackForReload:(NSString *)filePath
{
    [self removeGpxFileWith:filePath];
}

- (BOOL)buildGpxList
{
    [_settings hideRemovedGpx];
    
    NSSet<NSString *> *mapSettingVisibleGpx = [NSSet setWithArray:[_settings.mapSettingVisibleGpx get]];
    
    if (_loadingGPXPaths.count > 0)
    {
        [self removeInactiveGpxFiles];
        return YES;
    }
    
    NSMutableArray<GpxLoadOperation *> *gpxLoadOperations = [NSMutableArray array];
    __weak __typeof(self) weakSelf = self;
    
    for (NSString *filePath in mapSettingVisibleGpx)
    {
        @autoreleasepool {
            if ([filePath hasSuffix:kBackupSuffix])
            {
                [_selectedGPXFilesBackup addObject:filePath];
                continue;
            }
            NSString *absoluteGpxFilepath = [OsmAndApp.instance.gpxPath stringByAppendingPathComponent:filePath];
            if ([self shouldLoadFileAtPath:absoluteGpxFilepath])
            {
                [_loadingGPXPaths addObject:absoluteGpxFilepath];
                GpxLoadOperation *loadOperation = [[GpxLoadOperation alloc] initWithFilePath:absoluteGpxFilepath];
                loadOperation.completeHandler =^(NSString *absoluteFilePath, OASGpxFile *gpxFile) {
                    OAGpxTrackGeometry *geometry = [OAGpxTrackGeometry geometryFromGpxFile:gpxFile path:absoluteFilePath];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [weakSelf completeTrackLoadingForFilePath:absoluteFilePath geometry:geometry];
                    });
                };
                loadOperation.cancelledHandler = ^(NSString *absoluteFilePath) {
                    [weakSelf noteLoadingPathCancelled:absoluteFilePath];
                };
                [gpxLoadOperations addObject:loadOperation];
            }
        }
    }
    if (gpxLoadOperations.count > 0)
        [_operationQueue addOperations:gpxLoadOperations waitUntilFinished:NO];
    
    [self removeInactiveGpxFiles];
    
    return _loadingGPXPaths.count > 0;
}

- (void)removeInactiveGpxFiles
{
    NSMutableArray<NSString *> *keysToRemove = [NSMutableArray array];
    NSMutableSet<NSString *> *keys = [NSMutableSet setWithArray:_activeGpx.allKeys];
    [keys addObjectsFromArray:_geometries.allKeys];

    for (NSString *key in keys)
    {
        NSString *gpxFilePath = [OAUtilities getGpxShortPath:key];
        
        if (![_settings isGpxVisible:gpxFilePath])
            [keysToRemove addObject:key];
    }
    
    if (keysToRemove.count > 0)
    {
        [_activeGpx removeObjectsForKeys:keysToRemove];
        [_geometries removeObjectsForKeys:keysToRemove];
    }
}

- (BOOL)shouldLoadFileAtPath:(NSString *)filePath
{
    return ![self containsGpxFileWith:filePath]
           && ![_loadingGPXPaths containsObject:filePath]
           && [[NSFileManager defaultManager] fileExistsAtPath:filePath];
}

- (void)removeFilePathFromLoadingQueue:(NSString *)filePath
{
    [_loadingGPXPaths removeObject:filePath];
}

- (void)publishLoadedTracksIfIdle
{
    if (_loadingGPXPaths.count == 0)
    {
        uint64_t bytes = 0;
        for (OAGpxTrackGeometry *geometry in _geometries.allValues)
            bytes += geometry.storedBytes;
        NSLog(@"GPX map geometry: %llu bytes (%lu tracks)", bytes, (unsigned long)_geometries.count);
        [[_app updateGpxTracksOnMapObservable] notifyEvent];
    }
}

- (void)noteLoadingPathCancelled:(NSString *)filePath
{
    if (![_loadingGPXPaths containsObject:filePath])
        return;
    [_loadingGPXPaths removeObject:filePath];
    [self publishLoadedTracksIfIdle];
}

- (void)completeTrackLoadingForFilePath:(NSString *)absoluteFilePath
                               geometry:(OAGpxTrackGeometry *)geometry
{
    if (geometry)
        _geometries[absoluteFilePath] = geometry;
    [_loadingGPXPaths removeObject:absoluteFilePath];
    [self publishLoadedTracksIfIdle];
}

- (OASGpxFile *)getSelectedGpx:(OASWptPt *)gpxWpt
{
    NSString *waypointPath = objc_getAssociatedObject(gpxWpt, OAGpxWaypointFilePathKey);
    if (waypointPath.length > 0)
    {
        OASGpxFile *marker = [[OASGpxFile alloc] initWithAuthor:nil];
        marker.path = waypointPath;
        return marker;
    }
    for (OASGpxFile *gpxFile in _activeGpx.allValues) {
        if ([[gpxFile getPointsList] containsObject:gpxWpt] || [[gpxFile getRoutePoints] containsObject:gpxWpt])
            return gpxFile;
    }
    
    OASGpxFile *currentTrack = [OASavingTrackHelper sharedInstance].currentTrack;
    if ([[currentTrack getPointsList] containsObject:gpxWpt] || [[currentTrack getRoutePoints] containsObject:gpxWpt])
        return currentTrack;
    
    return nil;
}

- (BOOL)isShowingAnyGpxFiles
{
    return _activeGpx.count > 0 || _geometries.count > 0;
}

- (void)clearAllGpxFilesToShow:(BOOL) backupSelection
{
    NSMutableArray *backedUp = [NSMutableArray new];
    if (backupSelection)
    {
        NSArray *currentlyVisible = _settings.mapSettingVisibleGpx.get;
        for (NSString *filePath in currentlyVisible)
        {
            [backedUp addObject:[filePath stringByAppendingString:kBackupSuffix]];
        }
    }
    [_activeGpx removeAllObjects];
    [_geometries removeAllObjects];
    [_settings.mapSettingVisibleGpx set:[NSArray arrayWithArray:backedUp]];
    [_selectedGPXFilesBackup removeAllObjects];
    [_selectedGPXFilesBackup addObjectsFromArray:backedUp];
}

- (void)restoreSelectedGpxFiles
{
    NSMutableArray *restored = [NSMutableArray new];
    if (_selectedGPXFilesBackup.count == 0)
        [self buildGpxList];
    for (NSString *backedUp in _selectedGPXFilesBackup)
    {
        if ([backedUp hasSuffix:kBackupSuffix])
        {
            [restored addObject:[backedUp stringByReplacingOccurrencesOfString:kBackupSuffix withString:@""]];
        }
    }
    [_settings.mapSettingVisibleGpx set:[NSArray arrayWithArray:restored]];
    [self buildGpxList];
    [_selectedGPXFilesBackup removeAllObjects];
}

+ (void)renameVisibleTrack:(NSString *)oldPath newPath:(NSString *)newPath
{
    OAAppSettings *settings = OAAppSettings.sharedManager;
    NSMutableArray *visibleGpx = [NSMutableArray arrayWithArray:settings.mapSettingVisibleGpx.get];
    for (NSString *gpx in [settings.mapSettingVisibleGpx get])
    {
        if ([gpx compare:oldPath] == NSOrderedSame)
        {
            [visibleGpx removeObject:gpx];
            [visibleGpx addObject:newPath.decomposedStringWithCanonicalMapping];
            break;
        }
    }
    
    [settings.mapSettingVisibleGpx set:[NSArray arrayWithArray:visibleGpx]];
}

- (NSString *)getSelectedGPXFilePath:(NSString *)fileName
{
    NSString *suffix = [NSString stringWithFormat:@"/%@", fileName];
    for (NSString *selectedGpxFile in _selectedGPXFilesBackup)
    {
        if ([selectedGpxFile hasSuffix:suffix])
        {
            return fileName;
        }
    }
    return nil;
}

- (NSArray<OASGpxFile *> *)getSelectedGPXFiles
{
    return [_activeGpx allValues];
}

- (OASWptPt *)getVisibleWayPointByLat:(double)lat lon:(double)lon
{
    CLLocationCoordinate2D markerLatLon = CLLocationCoordinate2DMake(lat, lon);
    if (CLLocationCoordinate2DIsValid(markerLatLon))
    {
        for (OAGpxTrackGeometry *geometry in _geometries.allValues)
        {
            for (OASWptPt *point in geometry.waypoints)
            {
                if ([geometry isWaypointGroupHidden:point.category])
                    continue;
                CLLocationCoordinate2D pointLatLon = CLLocationCoordinate2DMake(point.lat, point.lon);
                if (CLLocationCoordinate2DIsValid(pointLatLon) &&
                    [OAUtilities isCoordEqual:markerLatLon destLat:pointLatLon])
                    return point;
            }
        }
        for (OASGpxFile *selectedGpx in _activeGpx.allValues)
        {
            for (OASWptPt *point in [selectedGpx getPointsList])
            {
                CLLocationCoordinate2D pointLatLon = CLLocationCoordinate2DMake(point.lat, point.lon);
                if (CLLocationCoordinate2DIsValid(pointLatLon) &&
                    [OAUtilities isCoordEqual:markerLatLon destLat:pointLatLon])
                    return point;
            }
        }
    }
    return nil;
}

- (void)didReceiveMemoryWarning:(NSNotification *)notification
{
    // cancel all operations download GPX
    [_operationQueue cancelAllOperations];
    [_loadingGPXPaths removeAllObjects];
    [self publishLoadedTracksIfIdle];
}

@end
