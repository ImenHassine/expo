//  Copyright © 2021 650 Industries. All rights reserved.

#import <EXUpdates/EXUpdatesConfig.h>
#import <EXUpdates/EXUpdatesSelectionPolicyFilterAware.h>

NS_ASSUME_NONNULL_BEGIN

@interface EXUpdatesSelectionPolicyFilterAware ()

@property (nonatomic, strong) NSArray<NSString *> *runtimeVersions;

@end

@implementation EXUpdatesSelectionPolicyFilterAware

- (instancetype)initWithRuntimeVersions:(NSArray<NSString *> *)runtimeVersions
{
  if (self = [super init]) {
    _runtimeVersions = runtimeVersions;
  }
  return self;
}

- (instancetype)initWithRuntimeVersion:(NSString *)runtimeVersion
{
  return [self initWithRuntimeVersions:@[runtimeVersion]];
}

- (nullable EXUpdatesUpdate *)launchableUpdateWithUpdates:(NSArray<EXUpdatesUpdate *> *)updates filters:(nullable NSDictionary *)filters
{
  EXUpdatesUpdate *runnableUpdate;
  NSDate *runnableUpdateCommitTime;
  for (EXUpdatesUpdate *update in updates) {
    if (![_runtimeVersions containsObject:update.runtimeVersion] || [self isUpdate:update filteredWithFilters:filters]) {
      continue;
    }
    NSDate *commitTime = update.commitTime;
    if (!runnableUpdateCommitTime || [runnableUpdateCommitTime compare:commitTime] == NSOrderedAscending) {
      runnableUpdate = update;
      runnableUpdateCommitTime = commitTime;
    }
  }
  return runnableUpdate;
}

- (NSArray<EXUpdatesUpdate *> *)updatesToDeleteWithLaunchedUpdate:(EXUpdatesUpdate *)launchedUpdate updates:(NSArray<EXUpdatesUpdate *> *)updates filters:(nullable NSDictionary *)filters
{
  if (!launchedUpdate) {
    return @[];
  }

  NSMutableArray<EXUpdatesUpdate *> *updatesToDelete = [NSMutableArray new];
  // keep the launched update and one other, the next newest, to be safe and make rollbacks faster
  // keep the next newest update that matches all the manifest filters, unless no other updates do
  // in which case, keep the next newest across all updates
  EXUpdatesUpdate *nextNewestUpdate;
  EXUpdatesUpdate *nextNewestUpdateMatchingFilters;
  for (EXUpdatesUpdate *update in updates) {
    if ([launchedUpdate.commitTime compare:update.commitTime] == NSOrderedDescending) {
      [updatesToDelete addObject:update];
      if (!nextNewestUpdate || [update.commitTime compare:nextNewestUpdate.commitTime] == NSOrderedDescending) {
        nextNewestUpdate = update;
      }
      if (![self isUpdate:update filteredWithFilters:filters] &&
          (!nextNewestUpdateMatchingFilters || [update.commitTime compare:nextNewestUpdateMatchingFilters.commitTime] == NSOrderedDescending)) {
        nextNewestUpdateMatchingFilters = update;
      }
    }
  }

  if (nextNewestUpdateMatchingFilters) {
    [updatesToDelete removeObject:nextNewestUpdateMatchingFilters];
  } else if (nextNewestUpdate) {
    [updatesToDelete removeObject:nextNewestUpdate];
  }
  return updatesToDelete;
}

- (BOOL)shouldLoadNewUpdate:(nullable EXUpdatesUpdate *)newUpdate withLaunchedUpdate:(nullable EXUpdatesUpdate *)launchedUpdate filters:(nullable NSDictionary *)filters
{
  if (!newUpdate) {
    return NO;
  }
  if (!launchedUpdate) {
    return YES;
  }
  // if the current update doesn't pass the manifest filters
  // we should load the new update no matter the commitTime
  if ([self isUpdate:launchedUpdate filteredWithFilters:filters]) {
    return YES;
  } else {
    // if the new update doesn't pass the manifest filters AND the launched update does
    // (i.e. we're sure we have an update that passes), we should not load the new update
    if ([self isUpdate:newUpdate filteredWithFilters:filters]) {
      return NO;
    }
  }
  return [launchedUpdate.commitTime compare:newUpdate.commitTime] == NSOrderedAscending;
}

- (BOOL)isUpdate:(EXUpdatesUpdate *)update filteredWithFilters:(nullable NSDictionary *)filters
{
  if (!filters || !update.metadata) {
    return NO;
  }

  NSDictionary *updateMetadata = update.metadata[@"updateMetadata"];
  if (!updateMetadata || ![updateMetadata isKindOfClass:[NSDictionary class]]) {
    return NO;
  }

  __block BOOL passes = YES;
  [filters enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
    id valueFromManifest = updateMetadata[key];
    if (valueFromManifest) {
      passes = [obj isEqual:valueFromManifest];
    } else if ([key isKindOfClass:[NSString class]] && [(NSString *)key containsString:@"."]) {
      NSArray<NSString *> *components = [(NSString *)key componentsSeparatedByString:@"."];
      NSDictionary *nestedObject = updateMetadata;
      for (NSUInteger i = 0; i < components.count; i++) {
        NSString *component = components[i];
        id value = nestedObject[component];
        if (!value) {
          // if the nested key doesn't exist in the manifest, just skip this filter
          passes = YES;
          break;
        } else if (i + 1 == components.count) {
          passes = [obj isEqual:value];
        } else if (![value isKindOfClass:[NSDictionary class]]) {
          // if the full nested key doesn't exist/is cut short in the manifest, skip the filter
          passes = YES;
          break;
        } else {
          nestedObject = (NSDictionary *)value;
        }
      }
    }

    // once an update fails one filter, break early; we don't need to check the rest
    if (!passes) {
      *stop = YES;
    }
  }];

  return !passes;
}

@end

NS_ASSUME_NONNULL_END
