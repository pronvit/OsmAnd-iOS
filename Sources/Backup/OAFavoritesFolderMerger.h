#import <Foundation/Foundation.h>

@class OAFavoriteGroup;

NS_ASSUME_NONNULL_BEGIN

/// Result of a three-way merge of one favorites folder.
/// `resolved` is NO when the same point, or the same group appearance field, changed on both
/// sides and the timestamps do not order the two edits. The folder then stays in Conflicts.
@interface OAFavoritesFolderMergeResult : NSObject

@property (nonatomic, readonly) BOOL resolved;
@property (nonatomic, readonly, nullable) OAFavoriteGroup *group;

@end

@interface OAFavoritesFolderMerger : NSObject

/// `base` is the folder at the last shared cloud version. Pass nil when that version is gone:
/// the merge keeps a union of both sides and lets tombstones suppress points.
+ (OAFavoritesFolderMergeResult *)mergeLocal:(OAFavoriteGroup *)local
                                         base:(nullable OAFavoriteGroup *)base
                                       remote:(OAFavoriteGroup *)remote;

@end

NS_ASSUME_NONNULL_END
