#import "OAFavoritesFolderMerger.h"
#import "OAFavoriteItem.h"
#import "OAFavoritesHelper.h"
#import "OAUtilities.h"

static const long long kFavoriteTombstoneMaxAgeMs = 90LL * 24 * 60 * 60 * 1000;

@interface OAFavoriteItem (FavoriteMergeComment)

- (NSString *)getComment;

@end

@interface OAFavoritesFolderMergeResult ()

@property (nonatomic, readwrite) BOOL resolved;
@property (nonatomic, readwrite, nullable) OAFavoriteGroup *group;

@end

@implementation OAFavoritesFolderMergeResult
@end

@implementation OAFavoritesFolderMerger

+ (OAFavoritesFolderMergeResult *)mergeLocal:(OAFavoriteGroup *)local
                                         base:(OAFavoriteGroup *)base
                                       remote:(OAFavoriteGroup *)remote
{
    OAFavoritesFolderMergeResult *result = [[OAFavoritesFolderMergeResult alloc] init];
    if (!local || !remote)
    {
        result.resolved = NO;
        return result;
    }

    NSDictionary<NSString *, OAFavoriteItem *> *localPoints = [self pointsByKey:local];
    NSDictionary<NSString *, OAFavoriteItem *> *basePoints = [self pointsByKey:base];
    NSDictionary<NSString *, OAFavoriteItem *> *remotePoints = [self pointsByKey:remote];
    NSMutableSet<NSString *> *keys = [NSMutableSet set];
    [keys addObjectsFromArray:localPoints.allKeys];
    [keys addObjectsFromArray:basePoints.allKeys];
    [keys addObjectsFromArray:remotePoints.allKeys];
    [keys addObjectsFromArray:local.deletedPointTimes.allKeys];
    [keys addObjectsFromArray:base.deletedPointTimes.allKeys];
    [keys addObjectsFromArray:remote.deletedPointTimes.allKeys];

    NSMutableDictionary<NSString *, NSNumber *> *tombstones = [self newestTombstonesAmong:@[local, remote]];
    if (base)
        [self mergeTombstones:base.deletedPointTimes into:tombstones];

    BOOL resolved = YES;
    NSMutableArray<OAFavoriteItem *> *mergedPoints = [NSMutableArray array];
    for (NSString *key in [keys.allObjects sortedArrayUsingSelector:@selector(compare:)])
    {
        OAFavoriteItem *basePoint = basePoints[key];
        OAFavoriteItem *localPoint = localPoints[key];
        OAFavoriteItem *remotePoint = remotePoints[key];
        long long tombstoneTime = tombstones[key].longLongValue;
        OAFavoriteItem *chosen = nil;
        if (base)
        {
            BOOL localChanged = ![self point:localPoint equalsPoint:basePoint];
            BOOL remoteChanged = ![self point:remotePoint equalsPoint:basePoint];
            if (!localChanged && !remoteChanged)
                chosen = localPoint ?: basePoint;
            else if (localChanged && !remoteChanged)
                chosen = localPoint;
            else if (!localChanged && remoteChanged)
                chosen = remotePoint;
            else
                chosen = [self chooseLocal:localPoint remote:remotePoint tombstoneTime:tombstoneTime resolved:&resolved];
        }
        else
        {
            chosen = [self chooseWithoutBaseLocal:localPoint remote:remotePoint tombstoneTime:tombstoneTime resolved:&resolved];
        }

        if (chosen)
        {
            [mergedPoints addObject:chosen];
            if (tombstoneTime > 0 && tombstoneTime <= [self timestampMs:chosen])
                [tombstones removeObjectForKey:key];
        }
        else if (tombstoneTime <= 0 && (localPoint || remotePoint || basePoint))
        {
            long long now = (long long) ([NSDate date].timeIntervalSince1970 * 1000.0);
            tombstones[key] = @(now);
        }
    }

    [self pruneTombstones:tombstones now:(long long) ([NSDate date].timeIntervalSince1970 * 1000.0)];

    OAFavoriteGroup *group = [[OAFavoriteGroup alloc] initWithPoints:mergedPoints
                                                                 name:local.name ?: remote.name
                                                            isVisible:local.isVisible
                                                                color:local.color];
    group.iconName = local.iconName;
    group.backgroundType = local.backgroundType;
    group.isPinned = local.isPinned;
    group.deletedPointTimes = tombstones;
    if (![self applyAppearanceFromLocal:local base:base remote:remote toGroup:group resolved:&resolved])
        resolved = NO;

    result.resolved = resolved;
    result.group = resolved ? group : nil;
    return result;
}

+ (NSDictionary<NSString *, OAFavoriteItem *> *)pointsByKey:(OAFavoriteGroup *)group
{
    NSMutableDictionary<NSString *, OAFavoriteItem *> *points = [NSMutableDictionary dictionary];
    for (OAFavoriteItem *point in group.points)
    {
        NSString *key = [point getKey];
        if (key.length > 0 && !points[key])
            points[key] = point;
    }
    return points;
}

+ (NSMutableDictionary<NSString *, NSNumber *> *)newestTombstonesAmong:(NSArray<OAFavoriteGroup *> *)groups
{
    NSMutableDictionary<NSString *, NSNumber *> *tombstones = [NSMutableDictionary dictionary];
    for (OAFavoriteGroup *group in groups)
        [self mergeTombstones:group.deletedPointTimes into:tombstones];
    return tombstones;
}

+ (void)mergeTombstones:(NSDictionary<NSString *, NSNumber *> *)source
                   into:(NSMutableDictionary<NSString *, NSNumber *> *)destination
{
    [source enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSNumber *time, BOOL *stop) {
        NSNumber *existing = destination[key];
        if (!existing || existing.longLongValue < time.longLongValue)
            destination[key] = time;
    }];
}

+ (nullable OAFavoriteItem *)chooseLocal:(OAFavoriteItem *)localPoint
                                  remote:(OAFavoriteItem *)remotePoint
                          tombstoneTime:(long long)tombstoneTime
                               resolved:(BOOL *)resolved
{
    if (!localPoint && !remotePoint)
        return nil;
    if (localPoint && remotePoint)
    {
        long long localTime = [self timestampMs:localPoint];
        long long remoteTime = [self timestampMs:remotePoint];
        if (tombstoneTime > MAX(localTime, remoteTime))
            return nil;
        if ([self point:localPoint equalsPoint:remotePoint])
            return localPoint;
        if (localTime != remoteTime)
            return localTime > remoteTime ? localPoint : remotePoint;
        if (resolved)
            *resolved = NO;
        return nil;
    }

    OAFavoriteItem *edited = localPoint ?: remotePoint;
    long long editTime = [self timestampMs:edited];
    if (tombstoneTime > 0 && tombstoneTime != editTime)
        return tombstoneTime > editTime ? nil : edited;
    if (resolved)
        *resolved = NO;
    return nil;
}

+ (nullable OAFavoriteItem *)chooseWithoutBaseLocal:(OAFavoriteItem *)localPoint
                                             remote:(OAFavoriteItem *)remotePoint
                                     tombstoneTime:(long long)tombstoneTime
                                          resolved:(BOOL *)resolved
{
    if (localPoint && remotePoint)
        return [self chooseLocal:localPoint remote:remotePoint tombstoneTime:tombstoneTime resolved:resolved];

    OAFavoriteItem *only = localPoint ?: remotePoint;
    if (!only)
        return nil;
    if (tombstoneTime > [self timestampMs:only])
        return nil;
    return only;
}

+ (BOOL)applyAppearanceFromLocal:(OAFavoriteGroup *)local
                             base:(OAFavoriteGroup *)base
                           remote:(OAFavoriteGroup *)remote
                          toGroup:(OAFavoriteGroup *)group
                         resolved:(BOOL *)resolved
{
    BOOL localChanged = base && ![self appearanceOf:local equalsAppearanceOf:base];
    BOOL remoteChanged = base && ![self appearanceOf:remote equalsAppearanceOf:base];
    OAFavoriteGroup *source = local;
    if (!base)
    {
        if (![self appearanceOf:local equalsAppearanceOf:remote])
        {
            source = [self newerAppearanceBetween:local and:remote resolved:resolved];
            if (!source)
                return NO;
        }
    }
    else if (localChanged && remoteChanged && ![self appearanceOf:local equalsAppearanceOf:remote])
    {
        source = [self newerAppearanceBetween:local and:remote resolved:resolved];
        if (!source)
            return NO;
    }
    else if (remoteChanged)
    {
        source = remote;
    }

    group.isVisible = source.isVisible;
    group.isPinned = source.isPinned;
    group.iconName = source.iconName;
    group.backgroundType = source.backgroundType;
    group.color = source.color;
    return YES;
}

+ (nullable OAFavoriteGroup *)newerAppearanceBetween:(OAFavoriteGroup *)local
                                                 and:(OAFavoriteGroup *)remote
                                            resolved:(BOOL *)resolved
{
    long long localTime = [self newestTimestamp:local];
    long long remoteTime = [self newestTimestamp:remote];
    if (localTime != remoteTime)
        return localTime > remoteTime ? local : remote;
    if (resolved)
        *resolved = NO;
    return nil;
}

+ (long long)newestTimestamp:(OAFavoriteGroup *)group
{
    long long newest = 0;
    for (OAFavoriteItem *point in group.points)
        newest = MAX(newest, [self timestampMs:point]);
    return newest;
}

+ (BOOL)point:(OAFavoriteItem *)point equalsPoint:(OAFavoriteItem *)other
{
    if (point == other)
        return YES;
    if (!point || !other)
        return NO;
    if (fabs([point getLatitude] - [other getLatitude]) > 1e-6)
        return NO;
    if (fabs([point getLongitude] - [other getLongitude]) > 1e-6)
        return NO;
    if (fabs([point getAltitude] - [other getAltitude]) > 0.05)
        return NO;
    if ([self timestampMs:point] != [self timestampMs:other])
        return NO;
    if ([point isVisible] != [other isVisible])
        return NO;
    if (![self string:[point getDescription] equals:[other getDescription]])
        return NO;
    if (![self string:[point getAddress] equals:[other getAddress]])
        return NO;
    if (![self string:[point getComment] equals:[other getComment]])
        return NO;
    if (![self string:[point getInternalIcon] equals:[other getInternalIcon]])
        return NO;
    if (![self string:[point getInternalBackgroundIcon] equals:[other getInternalBackgroundIcon]])
        return NO;
    return [self color:[point getInternalColor] equals:[other getInternalColor]];
}

+ (BOOL)appearanceOf:(OAFavoriteGroup *)group equalsAppearanceOf:(OAFavoriteGroup *)other
{
    if (!group || !other)
        return group == other;
    if (group.isVisible != other.isVisible || group.isPinned != other.isPinned)
        return NO;
    if (![self string:group.iconName equals:other.iconName])
        return NO;
    if (![self string:group.backgroundType equals:other.backgroundType])
        return NO;
    return [self color:group.color equals:other.color];
}

+ (BOOL)string:(NSString *)value equals:(NSString *)other
{
    NSString *left = value ?: @"";
    NSString *right = other ?: @"";
    return [left isEqualToString:right];
}

+ (BOOL)color:(UIColor *)color equals:(UIColor *)other
{
    if (color == other)
        return YES;
    if (!color || !other)
        return NO;
    return color.toARGBNumber == other.toARGBNumber;
}

+ (long long)timestampMs:(OAFavoriteItem *)point
{
    NSDate *timestamp = [point getTimestamp];
    if (!timestamp)
        return 0;
    return (long long) (timestamp.timeIntervalSince1970 * 1000.0);
}

+ (void)pruneTombstones:(NSMutableDictionary<NSString *, NSNumber *> *)tombstones now:(long long)now
{
    NSMutableArray<NSString *> *expired = [NSMutableArray array];
    [tombstones enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSNumber *time, BOOL *stop) {
        if (now - time.longLongValue > kFavoriteTombstoneMaxAgeMs)
            [expired addObject:key];
    }];
    [tombstones removeObjectsForKeys:expired];
}

@end
