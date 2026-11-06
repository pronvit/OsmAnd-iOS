//
//  OASyncBackupTask.m
//  OsmAnd Maps
//
//  Created by Paul on 07.11.2022.
//  Copyright © 2022 OsmAnd. All rights reserved.
//

#import "OASyncBackupTask.h"
#import "OANetworkSettingsHelper.h"
#import "OAObservable.h"
#import "OAPrepareBackupResult.h"
#import "OAPrepareBackupTask.h"
#import "OAExportBackupTask.h"
#import "OAImportBackupTask.h"
#import "OAExportSettingsType.h"
#import "OABackupHelper.h"
#import "OASettingsItem.h"
#import "OABackupInfo.h"
#import "OARemoteFile.h"
#import "OALocalFile.h"
#import "OAFavoritesSettingsItem.h"
#import "OAFavoritesFolderMerger.h"
#import "OAFavoritesHelper.h"
#import "OsmAndSharedWrapper.h"
#import "OsmAndApp.h"
#import "OAAppSettings.h"
#import "OsmAnd_Maps-Swift.h"

#include <OsmAndCore/ResourcesManager.h>

@interface OASyncBackupTask () <OAOnPrepareBackupListener, OAImportListener, OABackupExportListener>

@end

@implementation OASyncBackupTask
{
    NSString *_key;
    OABackupHelper *_backupHelper;
    NSInteger _maxProgress;
    NSInteger _importProgress;
    NSInteger _exportProgress;
    NSInteger _lastProgress;
    
    EOABackupSyncOperationType _operation;
    BOOL _cancelled;
    BOOL _syncOperation;
    BOOL _startSyncPending;
}

- (instancetype)initWithKey:(NSString *)key operation:(EOABackupSyncOperationType)operation
{
    self = [super init];
    if (self)
    {
        _key = key;
        _operation = operation;
        _syncOperation = operation == EOABackupSyncOperationSync;
        _startSyncPending = YES;
        _importProgress = 0;
        _exportProgress = 0;
        _maxProgress = 0;
        _cancelled = NO;
        _backupHelper = OABackupHelper.sharedInstance;
        [_backupHelper addPrepareBackupListener:self];
    }
    return self;
}

- (void)dealloc
{
    [_backupHelper removePrepareBackupListener:self];
}

- (NSInteger) getGeneralProgress
{
    return _importProgress + _exportProgress;
}

- (void)startSync
{
    @synchronized (self) {
        if (!_startSyncPending)
            return;

        _startSyncPending = NO;
    }

    OAPrepareBackupResult *backup = _backupHelper.backup;
    OABackupInfo *info = backup.backupInfo;
    [self mergeFavoriteFolderConflicts:info];
    
    NSArray<OASettingsItem *> *settingsItems = [BackupUtils getItemsForRestore:info settingsItems:backup.settingsItems];

    if (_operation != EOABackupSyncOperationDownload)
        _maxProgress += ([self calculateExportMaxProgress] / 1024);
    if (_operation != EOABackupSyncOperationUpload)
        _maxProgress += [OAImportBackupTask calculateMaxProgress];
    
    [NSNotificationCenter.defaultCenter postNotificationName:kBackupSyncStartedNotification object:nil];
    if (settingsItems.count > 0 && _operation != EOABackupSyncOperationUpload)
    {
        [OANetworkSettingsHelper.sharedInstance importSettings:kRestoreItemsKey
                                                         items:settingsItems
                                                     filesType:EOARemoteFilesTypeUnique
                                                 forceReadData:YES
                                                      listener:self];
    }
    else if (_operation != EOABackupSyncOperationDownload)
    {
        [self uploadNewItems];
    }
    else
    {
        [self onSyncFinished:nil];
    }
}

- (void)mergeFavoriteFolderConflicts:(OABackupInfo *)info
{
    if (!info || _operation == EOABackupSyncOperationDownload || _operation == EOABackupSyncOperationDelete)
        return;
    NSArray<NSArray *> *pairs = [info.filteredFilesToMerge copy];
    if (pairs.count == 0)
        return;

    NSMutableArray<NSArray *> *unresolved = [NSMutableArray array];
    for (NSArray *pair in pairs)
    {
        if (![self mergeFavoritePair:pair info:info])
            [unresolved addObject:pair];
    }
    info.filteredFilesToMerge = unresolved;
}

- (BOOL)mergeFavoritePair:(NSArray *)pair info:(OABackupInfo *)info
{
    if (pair.count < 2)
        return NO;
    OALocalFile *localFile = pair.firstObject;
    OARemoteFile *remoteFile = pair.lastObject;
    if (![localFile isKindOfClass:OALocalFile.class] || ![remoteFile isKindOfClass:OARemoteFile.class])
        return NO;
    if (![localFile.item isKindOfClass:OAFavoritesSettingsItem.class])
        return NO;

    OAFavoriteGroup *liveGroup = ((OAFavoritesSettingsItem *) localFile.item).items.firstObject;
    if (![liveGroup isKindOfClass:OAFavoriteGroup.class])
        return NO;

    OAFavoriteGroup *baseGroup = nil;
    if (localFile.uploadTime > 0)
    {
        NSString *basePath = [self temporaryFavoriteDownloadPath];
        NSString *error = [_backupHelper downloadFile:basePath
                                                 type:remoteFile.type
                                                 name:remoteFile.name
                                         updatetimems:localFile.uploadTime
                                             listener:nil];
        if (error.length == 0)
            baseGroup = [OAFavoritesHelper favoriteGroupFromGpxFile:[self gpxFileAtPath:basePath] fallbackName:liveGroup.name];
        [NSFileManager.defaultManager removeItemAtPath:basePath error:nil];
    }

    OARemoteFile *remote = remoteFile;
    OAFavoritesFolderMergeResult *pending = nil;
    for (NSInteger attempt = 0; attempt < 3; attempt++)
    {
        NSString *remotePath = [self temporaryFavoriteDownloadPath];
        NSString *error = [_backupHelper downloadFile:remotePath remoteFile:remote listener:nil];
        OASGpxFile *remoteGpx = error.length == 0 ? [self gpxFileAtPath:remotePath] : nil;
        OAFavoriteGroup *remoteGroup = [OAFavoritesHelper favoriteGroupFromGpxFile:remoteGpx fallbackName:liveGroup.name];
        [NSFileManager.defaultManager removeItemAtPath:remotePath error:nil];
        if (!remoteGroup)
            return NO;

        OAFavoritesFolderMergeResult *merged = [OAFavoritesFolderMerger mergeLocal:liveGroup base:baseGroup remote:remoteGroup];
        if (!merged.resolved || !merged.group)
            return NO;

        pending = merged;
        OARemoteFile *latest = [_backupHelper latestRemoteFileWithName:remote.name type:remote.type];
        if (!latest || latest.updatetimems == remote.updatetimems)
            break;
        if (latest.isDeleted)
            return NO;
        remote = latest;
        pending = nil;
    }
    if (!pending.group)
        return NO;

    [OAFavoritesHelper replaceGroup:liveGroup withMergedGroup:pending.group];
    [info.filesToMerge removeObject:pair];
    if (info.filesToUpload && ![info.filesToUpload containsObject:localFile])
        [info.filesToUpload addObject:localFile];
    if (info.filteredFilesToUpload && ![info.filteredFilesToUpload containsObject:localFile])
        [info.filteredFilesToUpload addObject:localFile];
    if (localFile.item && info.itemsToUpload && ![info.itemsToUpload containsObject:localFile.item])
        [info.itemsToUpload addObject:localFile.item];
    return YES;
}

- (NSString *)temporaryFavoriteDownloadPath
{
    NSString *name = [NSString stringWithFormat:@"favorite-merge-%@.gpx", NSUUID.UUID.UUIDString];
    return [NSTemporaryDirectory() stringByAppendingPathComponent:name];
}

- (OASGpxFile *)gpxFileAtPath:(NSString *)path
{
    if (path.length == 0 || ![NSFileManager.defaultManager fileExistsAtPath:path])
        return nil;
    OASKFile *file = [[OASKFile alloc] initWithFilePath:path];
    return [OASGpxUtilities.shared loadGpxFileFile:file];
}

- (void)execute
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        if (![_backupHelper isBackupPreparing])
            [self startSync];
    });
}

- (void)uploadLocalItem:(OASettingsItem *)item
{
    [OANetworkSettingsHelper.sharedInstance exportSettings:[BackupUtils getItemFileName:item] items:@[item] itemsToDelete:@[] localItemsToDelete:@[] listener:self];
}

- (void)downloadItem:(OASettingsItem *)item
                type:(EOARemoteFilesType)filesType
       shouldReplace:(BOOL)shouldReplace
      restoreDeleted:(BOOL)restoreDeleted
{
    [item setShouldReplace:shouldReplace];
    [OANetworkSettingsHelper.sharedInstance importSettings:[BackupUtils getItemFileName:item] items:@[item] filesType:filesType forceReadData:YES shouldReplace:shouldReplace restoreDeleted:restoreDeleted listener:self];
}

- (void) deleteItem:(OASettingsItem *)item
{
    [OANetworkSettingsHelper.sharedInstance exportSettings:[BackupUtils getItemFileName:item] items:@[] itemsToDelete:@[item] localItemsToDelete:@[] listener:self];
}

- (void) deleteLocalItem:(OASettingsItem *)item
{
    [OANetworkSettingsHelper.sharedInstance exportSettings:[BackupUtils getItemFileName:item] items:@[] itemsToDelete:@[] localItemsToDelete:@[item] listener:self];
}

- (void)cancel
{
    _cancelled = YES;
    [self onSyncFinished:nil];
}

- (void) uploadNewItems
{
    if (_cancelled)
        return;
    @try
    {
        OABackupInfo *info = _backupHelper.backup.backupInfo;
        NSArray<OASettingsItem *> *itemsToUpload = info.itemsToUpload;
        NSArray<OASettingsItem *> *itemsToDelete = info.itemsToDelete;
        NSArray<OASettingsItem *> *localItemsToDelete = info.itemsToLocalDelete;
        if (itemsToUpload.count > 0 || itemsToDelete.count > 0 || localItemsToDelete.count > 0)
            [OANetworkSettingsHelper.sharedInstance exportSettings:kBackupItemsKey items:itemsToUpload itemsToDelete:itemsToDelete localItemsToDelete:localItemsToDelete listener:self];
        else
            [self onSyncFinished:nil];
    }
    @catch (NSException *e)
    {
        NSLog(@"Backup generation error: %@", e.reason);
    }
}

- (NSInteger) calculateExportMaxProgress
{
    OABackupInfo *info = _backupHelper.backup.backupInfo;
    if (info)
    {
        NSMutableArray<OASettingsItem *> *oldItemsToDelete = [NSMutableArray array];
        for (OASettingsItem *item in info.itemsToUpload)
        {
            OAExportSettingsType *exportType = [OAExportSettingsType findBySettingsItem:item];
            if (exportType && [BackupUtils getVersionHistoryTypePref:exportType].get)
                [oldItemsToDelete addObject:item];
        }
        return [OAExportBackupTask getEstimatedItemsSize:info.itemsToUpload itemsToDelete:info.itemsToDelete localItemsToDelete:info.itemsToLocalDelete oldItemsToDelete:oldItemsToDelete];
    }
    return 0;
}

// MARK: OAOnPrepareBackupListener

- (void)onBackupPrepared:(nonnull OAPrepareBackupResult *)backupResult
{
    if (_syncOperation)
        [self startSync];
}

- (void)onBackupPreparing
{
}

// MARK: OAImportListener

- (void)onImportFinished:(BOOL)succeed needRestart:(BOOL)needRestart items:(NSArray<OASettingsItem *> *)items
{
    if (_cancelled)
        return;
    if (succeed)
        [BackupUtils updateCacheForItems:items];
    if (!_syncOperation)
        return [self onSyncFinished:nil];
    else
        [self uploadNewItems];
}

- (void)onImportItemFinished:(NSString *)type fileName:(NSString *)fileName
{
    [NSNotificationCenter.defaultCenter postNotificationName:kBackupItemFinishedNotification object:nil userInfo:@{@"type": type, @"name": fileName}];
}

- (void)onImportItemProgress:(NSString *)type fileName:(NSString *)fileName value:(int)value
{
    [NSNotificationCenter.defaultCenter  postNotificationName:kBackupItemProgressNotification object:nil userInfo:@{@"type": type, @"name": fileName, @"value": @(value)}];
}

- (void)onImportItemStarted:(NSString *)type fileName:(NSString *)fileName work:(int)work
{
    [NSNotificationCenter.defaultCenter  postNotificationName:kBackupItemStartedNotification object:nil userInfo:@{@"type": type, @"name": fileName, @"work": @(work)}];
}

- (void)onImportProgressUpdate:(NSInteger)value uploadedKb:(NSInteger)uploadedKb
{
    _importProgress = uploadedKb;
    float progress = (float) self.getGeneralProgress / _maxProgress;
    progress = progress > 1 ? 1 : progress;
    [NSNotificationCenter.defaultCenter postNotificationName:kBackupProgressUpdateNotification object:nil userInfo:@{@"progress": @(progress)}];
}

- (void)onSyncFinished:(NSDictionary *)info
{
    [OANetworkSettingsHelper.sharedInstance.syncBackupTasks removeObjectForKey:_key];
    [NSNotificationCenter.defaultCenter postNotificationName:kBackupSyncFinishedNotification object:nil userInfo:info];
}

// MARK: OABackupExportListener

- (void)onBackupExportFinished:(NSString *)error
{
    NSDictionary *info = nil;
    if (error)
        info = @{@"error": error};
    [self onSyncFinished:info];
}

- (void)onBackupExportProgressUpdate:(NSInteger)value
{
    OAExportBackupTask *exportTask = [OANetworkSettingsHelper.sharedInstance getExportTask:kBackupItemsKey];
    _exportProgress += exportTask.generalProgress - _lastProgress;
    float progress = (float) self.getGeneralProgress / _maxProgress;
    progress = progress > 1 ? 1 : progress;
    [NSNotificationCenter.defaultCenter postNotificationName:kBackupProgressUpdateNotification object:nil userInfo:@{@"progress": @(progress)}];
    _lastProgress = exportTask.generalProgress;
}

- (void)onBackupExportItemFinished:(NSString *)type fileName:(NSString *)fileName
{
    [NSNotificationCenter.defaultCenter postNotificationName:kBackupItemFinishedNotification object:nil userInfo:@{@"type": type, @"name": fileName}];
}

- (void)onBackupExportItemProgress:(NSString *)type fileName:(NSString *)fileName value:(NSInteger)value
{
    [NSNotificationCenter.defaultCenter postNotificationName:kBackupItemProgressNotification object:nil userInfo:@{@"type": type, @"name": fileName, @"value": @(value)}];
}

- (void)onBackupExportItemStarted:(NSString *)type fileName:(NSString *)fileName work:(NSInteger)work
{
    [NSNotificationCenter.defaultCenter postNotificationName:kBackupItemStartedNotification object:nil userInfo:@{@"type": type, @"name": fileName, @"work": @(work)}];
}

- (void)onBackupExportStarted
{
}

@end
