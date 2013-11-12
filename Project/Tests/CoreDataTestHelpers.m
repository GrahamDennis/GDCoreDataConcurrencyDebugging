//
//  CoreDataTestHelpers.m
//  GDCoreDataConcurrencyDebugging
//
//  Created by Graham Dennis on 12/11/13.
//  Copyright (c) 2013 Graham Dennis. All rights reserved.
//

#import "CoreDataTestHelpers.h"
#import <GDCoreDataConcurrencyDebugging/GDCoreDataConcurrencyDebugging.h>

NSManagedObjectModel *managedObjectModel()
{
    static NSManagedObjectModel *model = nil;
    if (model != nil) {
        return model;
    }
    
    NSURL *modelURL = [[NSBundle bundleForClass:[CoreDataTestHelpers class]] URLForResource:@"Example" withExtension:@"momd"];
    model = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    
    return model;
}

NSManagedObjectContext *managedObjectContext()
{
    NSManagedObjectContext *context = nil;
    if (context != nil) {
        return context;
    }
    
    @autoreleasepool {
        context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        
        NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:managedObjectModel()];
        [context setPersistentStoreCoordinator:coordinator];
        
        NSString *STORE_TYPE = NSInMemoryStoreType;
        NSURL *storeURL = [NSURL fileURLWithPath:@"/tmp/foo.sqlite"];
        
        NSError *error;
        NSPersistentStore *newStore = [coordinator addPersistentStoreWithType:STORE_TYPE configuration:nil URL:storeURL options:nil error:&error];
        
        if (newStore == nil) {
            NSLog(@"Store Configuration Failure %@", ([error localizedDescription] != nil) ? [error localizedDescription] : @"Unknown Error");
        }
    }
    return context;
}

NSCountedSet *ConcurrencyFailures = nil;

void ConcurrencyFailure(SEL _cmd)
{
    static dispatch_queue_t access_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        access_queue = dispatch_queue_create("me.grahamdennis.GDCoreDataConcurrencyDebugging.Tests", DISPATCH_QUEUE_SERIAL);
    });
    
    dispatch_sync(access_queue, ^{
        [ConcurrencyFailures addObject:NSStringFromSelector(_cmd)];
    });
}

@implementation CoreDataTestHelpers

+ (void)load
{
    GDCoreDataConcurrencyDebuggingSetFailureHandler(ConcurrencyFailure);
    ConcurrencyFailures = [NSCountedSet new];
}

@end
