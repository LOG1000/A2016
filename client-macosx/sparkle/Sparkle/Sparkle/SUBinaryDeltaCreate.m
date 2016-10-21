//
//  SUBinaryDeltaCreate.m
//  Sparkle
//
//  Created by Mayur Pawashe on 4/9/15.
//  Copyright (c) 2015 Sparkle Project. All rights reserved.
//

#import "SUBinaryDeltaCreate.h"
#import <Foundation/Foundation.h>
#include "SUBinaryDeltaCommon.h"
#import <CommonCrypto/CommonDigest.h>
#include <fcntl.h>
#include <fts.h>
#include <libgen.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/param.h>
#include <sys/stat.h>
#include <unistd.h>
#include <xar/xar.h>

extern int bsdiff(int argc, const char **argv);

@interface CreateBinaryDeltaOperation : NSOperation
@property (copy) NSString *relativePath;
@property (strong) NSString *resultPath;
@property (strong) NSNumber *oldPermissions;
@property (strong) NSNumber *permissions;
@property (strong) NSString *_fromPath;
@property (strong) NSString *_toPath;
- (id)initWithRelativePath:(NSString *)relativePath oldTree:(NSString *)oldTree newTree:(NSString *)newTree oldPermissions:(NSNumber *)oldPermissions newPermissions:(NSNumber *)permissions;
@end

@implementation CreateBinaryDeltaOperation
@synthesize relativePath = _relativePath;
@synthesize resultPath = _resultPath;
@synthesize oldPermissions = _oldPermissions;
@synthesize permissions = _permissions;
@synthesize _fromPath = _fromPath;
@synthesize _toPath = _toPath;

- (id)initWithRelativePath:(NSString *)relativePath oldTree:(NSString *)oldTree newTree:(NSString *)newTree oldPermissions:(NSNumber *)oldPermissions newPermissions:(NSNumber *)permissions
{
    if ((self = [super init])) {
        self.relativePath = relativePath;
        self.oldPermissions = oldPermissions;
        self.permissions = permissions;
        self._fromPath = [oldTree stringByAppendingPathComponent:relativePath];
        self._toPath = [newTree stringByAppendingPathComponent:relativePath];
    }
    return self;
}

- (void)main
{
    NSString *temporaryFile = temporaryFilename(@"BinaryDelta");
    const char *argv[] = {"/usr/bin/bsdiff", [self._fromPath fileSystemRepresentation], [self._toPath fileSystemRepresentation], [temporaryFile fileSystemRepresentation]};
    int result = bsdiff(4, argv);
    if (!result)
        self.resultPath = temporaryFile;
}

@end

#define INFO_HASH_KEY @"hash"
#define INFO_TYPE_KEY @"type"
#define INFO_PERMISSIONS_KEY @"permissions"
#define INFO_SIZE_KEY @"size"

static NSDictionary *infoForFile(FTSENT *ent)
{
    NSData *hash = hashOfFileContents(ent);
    if (!hash) {
        return nil;
    }
    
    off_t size = (ent->fts_info != FTS_D) ? ent->fts_statp->st_size : 0;
    
    assert(ent->fts_statp != NULL);
    
    mode_t permissions = ent->fts_statp->st_mode & PERMISSION_FLAGS;
    
    return @{INFO_HASH_KEY: hash, INFO_TYPE_KEY: @(ent->fts_info), INFO_PERMISSIONS_KEY : @(permissions), INFO_SIZE_KEY: @(size)};
}

static bool aclExists(const FTSENT *ent)
{
    // OS X does not currently support ACLs for symlinks
    if (ent->fts_info == FTS_SL) {
        return NO;
    }
    
    acl_t acl = acl_get_link_np(ent->fts_path, ACL_TYPE_EXTENDED);
    if (acl != NULL) {
        acl_entry_t entry;
        int result = acl_get_entry(acl, ACL_FIRST_ENTRY, &entry);
        assert(acl_free((void *)acl) == 0);
        return (result == 0);
    }
    return false;
}

static NSString *absolutePath(NSString *path)
{
    NSURL *url = [[NSURL alloc] initFileURLWithPath:path];
    return  [[url absoluteURL] path];
}

static NSString *temporaryPatchFile(NSString *patchFile)
{
    NSString *path = absolutePath(patchFile);
    NSString *directory = [path stringByDeletingLastPathComponent];
    NSString *file = [path lastPathComponent];
    return [NSString stringWithFormat:@"%@/.%@.tmp", directory, file];
}

#define MIN_FILE_SIZE_FOR_CREATING_DELTA 4096

static BOOL shouldSkipDeltaCompression(NSDictionary* originalInfo, NSDictionary *newInfo)
{
    unsigned long long fileSize = [newInfo[INFO_SIZE_KEY] unsignedLongLongValue];
    if (fileSize < MIN_FILE_SIZE_FOR_CREATING_DELTA) {
        return YES;
    }

    if (!originalInfo) {
        return YES;
    }

    if ([originalInfo[INFO_TYPE_KEY] unsignedShortValue] != [newInfo[INFO_TYPE_KEY] unsignedShortValue]) {
        return YES;
    }
    
    if ([originalInfo[INFO_HASH_KEY] isEqual:newInfo[INFO_HASH_KEY]]) {
        // this is possible if just the permissions have changed
        return YES;
    }

    return NO;
}

static BOOL shouldDeleteThenExtract(NSDictionary* originalInfo, NSDictionary *newInfo)
{
    if (!originalInfo) {
        return NO;
    }

    if ([originalInfo[INFO_TYPE_KEY] unsignedShortValue] != [newInfo[INFO_TYPE_KEY] unsignedShortValue]) {
        return YES;
    }

    return NO;
}

static BOOL shouldSkipExtracting(NSDictionary *originalInfo, NSDictionary *newInfo)
{
    if (!originalInfo) {
        return NO;
    }
    
    if ([originalInfo[INFO_TYPE_KEY] unsignedShortValue] != [newInfo[INFO_TYPE_KEY] unsignedShortValue]) {
        return NO;
    }
    
    if (![originalInfo[INFO_HASH_KEY] isEqual:newInfo[INFO_HASH_KEY]]) {
        return NO;
    }
    
    return YES;
}

static BOOL shouldChangePermissions(NSDictionary *originalInfo, NSDictionary *newInfo)
{
    if (!originalInfo) {
        return NO;
    }
    
    if ([originalInfo[INFO_TYPE_KEY] unsignedShortValue] != [newInfo[INFO_TYPE_KEY] unsignedShortValue]) {
        return NO;
    }
    
    if ([originalInfo[INFO_PERMISSIONS_KEY] unsignedShortValue] == [newInfo[INFO_PERMISSIONS_KEY] unsignedShortValue]) {
        return NO;
    }
    
    return YES;
}

int createBinaryDelta(NSString *source, NSString *destination, NSString *patchFile, SUBinaryDeltaMajorVersion majorVersion, BOOL verbose)
{
    if (majorVersion < FIRST_DELTA_DIFF_MAJOR_VERSION) {
        fprintf(stderr, "Version provided (%u) is not valid\n", majorVersion);
        return 1;
    }
    
    if (majorVersion > LATEST_DELTA_DIFF_MAJOR_VERSION) {
        fprintf(stderr, "This program is too old to create a version %u patch, or the version number provided is invalid\n", majorVersion);
        return 1;
    }
    
    SUBinaryDeltaMinorVersion minorVersion = latestMinorVersionForMajorVersion(majorVersion);
    
    NSMutableDictionary *originalTreeState = [NSMutableDictionary dictionary];

    const char *sourcePaths[] = {[source fileSystemRepresentation], 0};
    FTS *fts = fts_open((char* const*)sourcePaths, FTS_PHYSICAL | FTS_NOCHDIR, compareFiles);
    if (!fts) {
        perror("fts_open");
        return 1;
    }

    if (verbose) {
        fprintf(stderr, "Creating version %u.%u patch...\n", majorVersion, minorVersion);
        fprintf(stderr, "Processing %s...", [source fileSystemRepresentation]);
    }
    
    FTSENT *ent = 0;
    while ((ent = fts_read(fts))) {
        if (ent->fts_info != FTS_F && ent->fts_info != FTS_SL && ent->fts_info != FTS_D) {
            continue;
        }

        NSString *key = pathRelativeToDirectory(source, stringWithFileSystemRepresentation(ent->fts_path));
        if (![key length]) {
            continue;
        }

        NSDictionary *info = infoForFile(ent);
        if (!info) {
            fprintf(stderr, "\nFailed to retrieve info for file %s\n", ent->fts_path);
            return 1;
        }
        originalTreeState[key] = info;
        
        if (aclExists(ent)) {
            fprintf(stderr, "\nDiffing ACLs are not supported. Detected ACL in before-tree on file %s\n", ent->fts_path);
            return 1;
        }
    }
    fts_close(fts);
    
    NSString *beforeHash = hashOfTreeWithVersion(source, majorVersion);

    if (!beforeHash) {
        fprintf(stderr, "\nFailed to generate hash for tree %s\n", [source fileSystemRepresentation]);
        return 1;
    }

    NSMutableDictionary *newTreeState = [NSMutableDictionary dictionary];
    for (NSString *key in originalTreeState)
    {
        newTreeState[key] = [NSNull null];
    }

    if (verbose) {
        fprintf(stderr, "\nProcessing %s...", [destination fileSystemRepresentation]);
    }
    
    sourcePaths[0] = [destination fileSystemRepresentation];
    fts = fts_open((char* const*)sourcePaths, FTS_PHYSICAL | FTS_NOCHDIR, compareFiles);
    if (!fts) {
        perror("fts_open");
        return 1;
    }


    while ((ent = fts_read(fts))) {
        if (ent->fts_info != FTS_F && ent->fts_info != FTS_SL && ent->fts_info != FTS_D) {
            continue;
        }

        NSString *key = pathRelativeToDirectory(destination, stringWithFileSystemRepresentation(ent->fts_path));
        if (![key length]) {
            continue;
        }

        NSDictionary *info = infoForFile(ent);
        if (!info) {
            fprintf(stderr, "\nFailed to retrieve info from file %s\n", ent->fts_path);
            return 1;
        }
        
        // We should validate permissions and ACLs even if we don't store the info in the diff in the case of ACLs,
        // or in the case of permissions if the patch version is 1
        
        mode_t permissions = [info[INFO_PERMISSIONS_KEY] unsignedShortValue];
        if (!IS_VALID_PERMISSIONS(permissions)) {
            fprintf(stderr, "\nInvalid file permissions after-tree on file %s\nOnly permissions with modes 0755 and 0644 are supported\n", ent->fts_path);
            return 1;
        }
        
        if (aclExists(ent)) {
            fprintf(stderr, "\nDiffing ACLs are not supported. Detected ACL in after-tree on file %s\n", ent->fts_path);
            return 1;
        }
        
        NSDictionary *oldInfo = originalTreeState[key];

        if ([info isEqual:oldInfo]) {
            [newTreeState removeObjectForKey:key];
        } else {
            newTreeState[key] = info;
            
            if (oldInfo && [oldInfo[INFO_TYPE_KEY] unsignedShortValue] == FTS_D && [info[INFO_TYPE_KEY] unsignedShortValue] != FTS_D) {
                NSArray *parentPathComponents = key.pathComponents;

                for (NSString *childPath in originalTreeState) {
                    NSArray *childPathComponents = childPath.pathComponents;
                    if (childPathComponents.count > parentPathComponents.count &&
                        [parentPathComponents isEqualToArray:[childPathComponents subarrayWithRange:NSMakeRange(0, parentPathComponents.count)]]) {
                        [newTreeState removeObjectForKey:childPath];
                    }
                }
            }
        }
    }
    fts_close(fts);

    NSString *afterHash = hashOfTreeWithVersion(destination, majorVersion);
    if (!afterHash) {
        fprintf(stderr, "\nFailed to generate hash for tree %s\n", [destination fileSystemRepresentation]);
        return 1;
    }
    
    if (verbose) {
        fprintf(stderr, "\nGenerating delta...");
    }

    NSString *temporaryFile = temporaryPatchFile(patchFile);
    xar_t x = xar_open([temporaryFile fileSystemRepresentation], WRITE);
    xar_opt_set(x, XAR_OPT_COMPRESSION, "bzip2");
    
    xar_subdoc_t attributes = xar_subdoc_new(x, BINARY_DELTA_ATTRIBUTES_KEY);
    
    xar_subdoc_prop_set(attributes, MAJOR_DIFF_VERSION_KEY, [[NSString stringWithFormat:@"%u", majorVersion] UTF8String]);
    xar_subdoc_prop_set(attributes, MINOR_DIFF_VERSION_KEY, [[NSString stringWithFormat:@"%u", minorVersion] UTF8String]);
    
    // Version 1 patches don't have a major or minor version field, so we need to differentiate between the hash keys
    const char *beforeHashKey =
        MAJOR_VERSION_IS_AT_LEAST(majorVersion, SUBeigeMajorVersion) ? BEFORE_TREE_SHA1_KEY : BEFORE_TREE_SHA1_OLD_KEY;
    const char *afterHashKey =
        MAJOR_VERSION_IS_AT_LEAST(majorVersion, SUBeigeMajorVersion) ? AFTER_TREE_SHA1_KEY : AFTER_TREE_SHA1_OLD_KEY;
    
    xar_subdoc_prop_set(attributes, beforeHashKey, [beforeHash UTF8String]);
    xar_subdoc_prop_set(attributes, afterHashKey, [afterHash UTF8String]);

    NSOperationQueue *deltaQueue = [[NSOperationQueue alloc] init];
    NSMutableArray *deltaOperations = [NSMutableArray array];

    // Sort the keys by preferring the ones from the original tree to appear first
    // We want to enforce deleting before extracting in the case paths differ only by case
    NSArray *keys = [[newTreeState allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *key1, NSString *key2) {
        NSComparisonResult insensitiveCompareResult = [key1 caseInsensitiveCompare:key2];
        if (insensitiveCompareResult != NSOrderedSame) {
            return insensitiveCompareResult;
        }

        return originalTreeState[key1] ? NSOrderedAscending : NSOrderedDescending;
    }];
    for (NSString* key in keys) {
        id value = [newTreeState valueForKey:key];

        if ([value isEqual:[NSNull null]]) {
            xar_file_t newFile = xar_add_frombuffer(x, 0, [key fileSystemRepresentation], (char *)"", 1);
            assert(newFile);
            xar_prop_set(newFile, DELETE_KEY, "true");
            
            if (verbose) {
                fprintf(stderr, "\n❌  %s %s", VERBOSE_REMOVED, [key fileSystemRepresentation]);
            }
            continue;
        }

        NSDictionary *originalInfo = originalTreeState[key];
        NSDictionary *newInfo = newTreeState[key];
        if (shouldSkipDeltaCompression(originalInfo, newInfo)) {
            if (MAJOR_VERSION_IS_AT_LEAST(majorVersion, SUBeigeMajorVersion) && shouldSkipExtracting(originalInfo, newInfo)) {
                if (shouldChangePermissions(originalInfo, newInfo)) {
                    xar_file_t newFile = xar_add_frombuffer(x, 0, [key fileSystemRepresentation], (char *)"", 1);
                    assert(newFile);
                    xar_prop_set(newFile, MODIFY_PERMISSIONS_KEY, [[NSString stringWithFormat:@"%u", [newInfo[INFO_PERMISSIONS_KEY] unsignedShortValue]] UTF8String]);
                    
                    if (verbose) {
                        fprintf(stderr, "\n👮  %s %s (0%o -> 0%o)", VERBOSE_MODIFIED, [key fileSystemRepresentation], [originalInfo[INFO_PERMISSIONS_KEY] unsignedShortValue], [newInfo[INFO_PERMISSIONS_KEY] unsignedShortValue]);
                    }
                }
            } else {
                NSString *path = [destination stringByAppendingPathComponent:key];
                xar_file_t newFile = xar_add_frompath(x, 0, [key fileSystemRepresentation], [path fileSystemRepresentation]);
                assert(newFile);
                
                if (shouldDeleteThenExtract(originalInfo, newInfo)) {
                    if (MAJOR_VERSION_IS_AT_LEAST(majorVersion, SUBeigeMajorVersion)) {
                        xar_prop_set(newFile, DELETE_KEY, "true");
                    } else {
                        xar_prop_set(newFile, DELETE_THEN_EXTRACT_OLD_KEY, "true");
                    }
                }
                
                if (MAJOR_VERSION_IS_AT_LEAST(majorVersion, SUBeigeMajorVersion)) {
                    xar_prop_set(newFile, EXTRACT_KEY, "true");
                }
                
                if (verbose) {
                    if (originalInfo) {
                        fprintf(stderr, "\n✏️  %s %s", VERBOSE_UPDATED, [key fileSystemRepresentation]);
                    } else {
                        fprintf(stderr, "\n✅  %s %s", VERBOSE_ADDED, [key fileSystemRepresentation]);
                    }
                }
            }
        } else {
            NSNumber *permissions =
                (MAJOR_VERSION_IS_AT_LEAST(majorVersion, SUBeigeMajorVersion) && shouldChangePermissions(originalInfo, newInfo)) ?
                newInfo[INFO_PERMISSIONS_KEY] :
                nil;
            CreateBinaryDeltaOperation *operation = [[CreateBinaryDeltaOperation alloc] initWithRelativePath:key oldTree:source newTree:destination oldPermissions:originalInfo[INFO_PERMISSIONS_KEY] newPermissions:permissions];
            [deltaQueue addOperation:operation];
            [deltaOperations addObject:operation];
        }
    }

    [deltaQueue waitUntilAllOperationsAreFinished];

    for (CreateBinaryDeltaOperation *operation in deltaOperations) {
        NSString *resultPath = [operation resultPath];
        if (!resultPath) {
            fprintf(stderr, "\nFailed to create patch from source %s and destination %s\n", [[operation relativePath] fileSystemRepresentation], [resultPath fileSystemRepresentation]);
            return 1;
        }
        
        if (verbose) {
            fprintf(stderr, "\n🔨  %s %s", VERBOSE_DIFFED, [[operation relativePath] fileSystemRepresentation]);
        }
        
        xar_file_t newFile = xar_add_frompath(x, 0, [[operation relativePath] fileSystemRepresentation], [resultPath fileSystemRepresentation]);
        assert(newFile);
        xar_prop_set(newFile, BINARY_DELTA_KEY, "true");
        unlink([resultPath fileSystemRepresentation]);
        
        if (operation.permissions) {
            xar_prop_set(newFile, MODIFY_PERMISSIONS_KEY, [[NSString stringWithFormat:@"%u", [operation.permissions unsignedShortValue]] UTF8String]);
            
            if (verbose) {
                fprintf(stderr, "\n👮  %s %s (0%o -> 0%o)", VERBOSE_MODIFIED, [[operation relativePath] fileSystemRepresentation], operation.oldPermissions.unsignedShortValue, operation.permissions.unsignedShortValue);
            }
        }
    }

    xar_close(x);

    unlink([patchFile fileSystemRepresentation]);
    link([temporaryFile fileSystemRepresentation], [patchFile fileSystemRepresentation]);
    unlink([temporaryFile fileSystemRepresentation]);
    
    if (verbose) {
        fprintf(stderr, "\nDone!\n");
    }

    return 0;
}
