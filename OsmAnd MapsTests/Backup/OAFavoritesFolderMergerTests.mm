#import <XCTest/XCTest.h>
#import "OAFavoritesFolderMerger.h"
#import "OAFavoritesHelper.h"
#import "OAFavoriteItem.h"
#import "OAUtilities.h"

@interface OAFavoritesFolderMergerTests : XCTestCase
@end

@implementation OAFavoritesFolderMergerTests

- (OAFavoriteItem *)pointNamed:(NSString *)name
                   description:(NSString *)description
                     timestamp:(long long)timestamp
{
    OAFavoriteItem *point = [[OAFavoriteItem alloc] initWithLat:1
                                                            lon:2
                                                           name:name
                                                       category:@"Lunch"
                                                       altitude:0
                                                      timestamp:timestamp];
    [point setDescription:description];
    return point;
}

- (UIColor *)colorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue
{
    return [UIColor colorWithRed:red green:green blue:blue alpha:1];
}

- (OAFavoriteGroup *)groupWithPoints:(NSArray<OAFavoriteItem *> *)points color:(UIColor *)color
{
    OAFavoriteGroup *group = [[OAFavoriteGroup alloc] initWithPoints:points name:@"Lunch" isVisible:YES color:color];
    group.iconName = @"restaurant";
    group.backgroundType = @"circle";
    return group;
}

- (OAFavoriteItem *)pointNamed:(NSString *)name inGroup:(OAFavoriteGroup *)group
{
    for (OAFavoriteItem *point in group.points)
    {
        if ([[point getName] isEqualToString:name])
            return point;
    }
    return nil;
}

- (void)testBothSidesAddDifferentPoints
{
    OAFavoriteItem *basePoint = [self pointNamed:@"Cafe" description:@"base" timestamp:1000];
    OAFavoriteGroup *base = [self groupWithPoints:@[basePoint] color:[self colorWithRed:1 green:0 blue:0]];
    OAFavoriteGroup *local = [self groupWithPoints:@[basePoint, [self pointNamed:@"Park" description:@"local" timestamp:2000]] color:[self colorWithRed:1 green:0 blue:0]];
    OAFavoriteGroup *remote = [self groupWithPoints:@[basePoint, [self pointNamed:@"Museum" description:@"remote" timestamp:3000]] color:[self colorWithRed:1 green:0 blue:0]];

    OAFavoritesFolderMergeResult *result = [OAFavoritesFolderMerger mergeLocal:local base:base remote:remote];

    XCTAssertTrue(result.resolved);
    XCTAssertNotNil([self pointNamed:@"Cafe" inGroup:result.group]);
    XCTAssertNotNil([self pointNamed:@"Park" inGroup:result.group]);
    XCTAssertNotNil([self pointNamed:@"Museum" inGroup:result.group]);
}

- (void)testDeleteOnOneSideKeepsTheOtherPoint
{
    OAFavoriteItem *kept = [self pointNamed:@"Cafe" description:@"base" timestamp:1000];
    OAFavoriteItem *removed = [self pointNamed:@"Park" description:@"base" timestamp:1000];
    OAFavoriteGroup *base = [self groupWithPoints:@[kept, removed] color:[self colorWithRed:1 green:0 blue:0]];
    OAFavoriteGroup *local = [self groupWithPoints:@[kept] color:[self colorWithRed:1 green:0 blue:0]];
    OAFavoriteGroup *remote = [self groupWithPoints:@[kept, removed] color:[self colorWithRed:1 green:0 blue:0]];

    OAFavoritesFolderMergeResult *result = [OAFavoritesFolderMerger mergeLocal:local base:base remote:remote];

    XCTAssertTrue(result.resolved);
    XCTAssertNotNil([self pointNamed:@"Cafe" inGroup:result.group]);
    XCTAssertNil([self pointNamed:@"Park" inGroup:result.group]);
    XCTAssertNotNil(result.group.deletedPointTimes[[removed getKey]]);
}

- (void)testNewerEditWinsWhenBothSidesChangeOnePoint
{
    OAFavoriteItem *basePoint = [self pointNamed:@"Cafe" description:@"base" timestamp:1000];
    OAFavoriteItem *localPoint = [self pointNamed:@"Cafe" description:@"local" timestamp:2000];
    OAFavoriteItem *remotePoint = [self pointNamed:@"Cafe" description:@"remote" timestamp:4000];
    OAFavoriteGroup *base = [self groupWithPoints:@[basePoint] color:[self colorWithRed:1 green:0 blue:0]];
    OAFavoriteGroup *local = [self groupWithPoints:@[localPoint] color:[self colorWithRed:1 green:0 blue:0]];
    OAFavoriteGroup *remote = [self groupWithPoints:@[remotePoint] color:[self colorWithRed:1 green:0 blue:0]];

    OAFavoritesFolderMergeResult *result = [OAFavoritesFolderMerger mergeLocal:local base:base remote:remote];

    XCTAssertTrue(result.resolved);
    XCTAssertEqualObjects([[self pointNamed:@"Cafe" inGroup:result.group] getDescription], @"remote");
}

- (void)testEqualTimestampsStayUnresolved
{
    OAFavoriteItem *basePoint = [self pointNamed:@"Cafe" description:@"base" timestamp:1000];
    OAFavoriteItem *localPoint = [self pointNamed:@"Cafe" description:@"local" timestamp:2000];
    OAFavoriteItem *remotePoint = [self pointNamed:@"Cafe" description:@"remote" timestamp:2000];
    OAFavoriteGroup *base = [self groupWithPoints:@[basePoint] color:[self colorWithRed:1 green:0 blue:0]];
    OAFavoriteGroup *local = [self groupWithPoints:@[localPoint] color:[self colorWithRed:1 green:0 blue:0]];
    OAFavoriteGroup *remote = [self groupWithPoints:@[remotePoint] color:[self colorWithRed:1 green:0 blue:0]];

    OAFavoritesFolderMergeResult *result = [OAFavoritesFolderMerger mergeLocal:local base:base remote:remote];

    XCTAssertFalse(result.resolved);
    XCTAssertNil(result.group);
}

- (void)testTombstoneDropsAnUnchangedPointWhenBaseIsMissing
{
    OAFavoriteItem *remotePoint = [self pointNamed:@"Cafe" description:@"remote" timestamp:1000];
    OAFavoriteGroup *local = [self groupWithPoints:@[] color:[self colorWithRed:1 green:0 blue:0]];
    local.deletedPointTimes[[remotePoint getKey]] = @(5000);
    OAFavoriteGroup *remote = [self groupWithPoints:@[remotePoint] color:[self colorWithRed:1 green:0 blue:0]];

    OAFavoritesFolderMergeResult *result = [OAFavoritesFolderMerger mergeLocal:local base:nil remote:remote];

    XCTAssertTrue(result.resolved);
    XCTAssertNil([self pointNamed:@"Cafe" inGroup:result.group]);
}

- (void)testMissingBaseKeepsAPointTheOtherSideNeverDeleted
{
    OAFavoriteItem *localPoint = [self pointNamed:@"Park" description:@"local" timestamp:2000];
    OAFavoriteGroup *local = [self groupWithPoints:@[localPoint] color:[self colorWithRed:1 green:0 blue:0]];
    OAFavoriteGroup *remote = [self groupWithPoints:@[] color:[self colorWithRed:1 green:0 blue:0]];

    OAFavoritesFolderMergeResult *result = [OAFavoritesFolderMerger mergeLocal:local base:nil remote:remote];

    XCTAssertTrue(result.resolved);
    XCTAssertNotNil([self pointNamed:@"Park" inGroup:result.group]);
}

- (void)testGroupColorChangedOnOneSide
{
    OAFavoriteItem *point = [self pointNamed:@"Cafe" description:@"base" timestamp:1000];
    OAFavoriteGroup *base = [self groupWithPoints:@[point] color:[self colorWithRed:1 green:0 blue:0]];
    OAFavoriteGroup *local = [self groupWithPoints:@[point] color:[self colorWithRed:1 green:0 blue:0]];
    UIColor *blue = [self colorWithRed:0 green:0 blue:1];
    OAFavoriteGroup *remote = [self groupWithPoints:@[point] color:blue];

    OAFavoritesFolderMergeResult *result = [OAFavoritesFolderMerger mergeLocal:local base:base remote:remote];

    XCTAssertTrue(result.resolved);
    XCTAssertEqual(result.group.color.toARGBNumber, blue.toARGBNumber);
}

@end
