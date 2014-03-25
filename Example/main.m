//
//  main.m
//  Example
//
//  Created by Graham Dennis on 7/09/13.
//  Copyright (c) 2013 Graham Dennis. All rights reserved.
//

#import "EntityWithCustomClass.h"
#import <GDCoreDataConcurrencyDebugging/GDConcurrencyCheckingManagedObject.h>

static NSManagedObjectModel *managedObjectModel()
{
    static NSManagedObjectModel *model = nil;
    if (model != nil) {
        return model;
    }
    
    NSString *path = @"Example";
    path = [path stringByDeletingPathExtension];
    NSURL *modelURL = [NSURL fileURLWithPath:[path stringByAppendingPathExtension:@"momd"]];
    model = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    
    return model;
}

static NSManagedObjectContext *managedObjectContext()
{
    static NSManagedObjectContext *context = nil;
    if (context != nil) {
        return context;
    }

    @autoreleasepool {
        context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        
        NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:managedObjectModel()];
        [context setPersistentStoreCoordinator:coordinator];
        
        NSString *STORE_TYPE = NSSQLiteStoreType;
        
        NSString *path = [[NSProcessInfo processInfo] arguments][0];
        path = [path stringByDeletingPathExtension];
        NSURL *url = [NSURL fileURLWithPath:[path stringByAppendingPathExtension:@"sqlite"]];
        
        NSError *error;
        NSPersistentStore *newStore = [coordinator addPersistentStoreWithType:STORE_TYPE configuration:nil URL:url options:nil error:&error];
        
        if (newStore == nil) {
            NSLog(@"Store Configuration Failure %@", ([error localizedDescription] != nil) ? [error localizedDescription] : @"Unknown Error");
        }
    }
    return context;
}

@interface NSManagedObject (EntityAccessors)

@property (nonatomic, strong) NSString *name;

@end

void ConcurrencyFailure(SEL _cmd)
{
    NSLog(@"CoreData concurrency failure with selector: %@; stack: %@", NSStringFromSelector(_cmd), [NSThread callStackSymbols]);
}

// With optimisations turned off, the compiler will generate an autorelease method for this method
NSManagedObject *IdentityFunction(NSManagedObject *object)
{
    return object;
}


int main(int argc, const char * argv[])
{
    GDCoreDataConcurrencyDebuggingBeginTrackingAutorelease();
    
    @autoreleasepool {
        GDCoreDataConcurrencyDebuggingSetFailureHandler(ConcurrencyFailure);
        // Create the managed object context
        NSManagedObjectContext *context1 = managedObjectContext();
        
        NSManagedObjectContext *context2 = managedObjectContext();
        
        NSEntityDescription *entity = [NSEntityDescription entityForName:@"Entity" inManagedObjectContext:context1];
        
        __block NSManagedObject *objectInContext1 = nil;
        [context1 performBlockAndWait:^{
            objectInContext1 = [[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:context1];
            objectInContext1.name = @"test";
            [context1 save:NULL];
        }];
        
        @autoreleasepool {
            [context1 performBlockAndWait:^{
                NSEntityDescription *childEntityDescription = [NSEntityDescription entityForName:@"ChildEntity"
                                                                          inManagedObjectContext:context1];
                NSManagedObject *childEntity = [[NSManagedObject alloc] initWithEntity:childEntityDescription insertIntoManagedObjectContext:context1];
                [objectInContext1 setValue:childEntity forKey:@"relatedEntity"];
                [context1 save:NULL];
            }];
        }
        
        // Here's an obvious invalid access
        NSString *name = objectInContext1.name;
        NSLog(@"name: %@", name);
        
        __block NSArray *results = nil;
        
        @autoreleasepool {
            [context2 performBlockAndWait:^{
                
                for (NSString *name in @[@"a", @"b", @"c"]) {
                    EntityWithCustomClass *object = [EntityWithCustomClass insertInManagedObjectContext:context2];
                    object.name = name;
                }
                
                NSFetchRequest *fetchRequest = [NSFetchRequest new];
                fetchRequest.entity = [EntityWithCustomClass entityInManagedObjectContext:context2];
                fetchRequest.includesPendingChanges = YES;
                NSArray *tempResults = [context2 executeFetchRequest:fetchRequest error:NULL];
                
                results = [[tempResults mutableCopy] copy]; // We can be sure that 'results' is not a magic CoreData NSArray
            }];
        }

        @autoreleasepool {
            // This code is safe because we are just calling -objectID
            // But it's only safe as long as the context isn't reset (or deallocated) before the autorelease pool pops.
            NSMutableArray *objectIDs = [NSMutableArray new];
            for (EntityWithCustomClass *object in results) {
                [objectIDs addObject:IdentityFunction(object).objectID];
            }
        }

        @autoreleasepool {
            // Here's an example of unsafe code
            NSMutableArray *objectIDs = [NSMutableArray new];
            for (EntityWithCustomClass *object in results) {
                [objectIDs addObject:IdentityFunction(object).objectID];
            }
            // This code is not safe because the autoreleased object's will be cleaned up after the context is reset.
            // This is even worse if we interacted with the NSManagedObject's on a random dispatch queue, because they
            // pop their autorelease pools at unspecified times.
            results = nil;
            [context2 performBlockAndWait:^{
                [context2 reset];
            }];
        }
        
        
        
        // Custom code here...
        // Save the managed object context
        [context1 performBlock:^{
            NSError *error = nil;
            if (![context1 save:&error]) {
                NSLog(@"Error while saving %@", ([error localizedDescription] != nil) ? [error localizedDescription] : @"Unknown Error");
                exit(1);
            }
        }];
        
        {
            NSManagedObjectContext *mainQueueContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
            
            NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:managedObjectModel()];
            [mainQueueContext setPersistentStoreCoordinator:coordinator];
            
            NSString *STORE_TYPE = NSSQLiteStoreType;
            
            NSString *path = [[NSProcessInfo processInfo] arguments][0];
            path = [path stringByDeletingPathExtension];
            NSURL *url = [NSURL fileURLWithPath:[path stringByAppendingPathExtension:@"sqlite"]];
            
            NSError *error;
            NSPersistentStore *newStore = [coordinator addPersistentStoreWithType:STORE_TYPE configuration:nil URL:url options:nil error:&error];
            
            if (newStore == nil) {
                NSLog(@"Store Configuration Failure %@", ([error localizedDescription] != nil) ? [error localizedDescription] : @"Unknown Error");
            }
            
            NSFetchRequest *fetchRequest = [NSFetchRequest new];
            fetchRequest.entity = [EntityWithCustomClass entityInManagedObjectContext:mainQueueContext];
            fetchRequest.includesPendingChanges = YES;
            NSArray *tempResults = [mainQueueContext executeFetchRequest:fetchRequest error:NULL];
            
            for (EntityWithCustomClass *o in tempResults) {
                [o willAccessValueForKey:nil];
            }
            
            results = [[tempResults mutableCopy] copy]; // We can be sure that 'results' is not a magic CoreData NSArray
            results = nil;
        }

        {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSConfinementConcurrencyType];
                
                NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:managedObjectModel()];
                [context setPersistentStoreCoordinator:coordinator];
                
                NSString *STORE_TYPE = NSSQLiteStoreType;
                
                NSString *path = [[NSProcessInfo processInfo] arguments][0];
                path = [path stringByDeletingPathExtension];
                NSURL *url = [NSURL fileURLWithPath:[path stringByAppendingPathExtension:@"sqlite"]];
                
                NSError *error;
                NSPersistentStore *newStore = [coordinator addPersistentStoreWithType:STORE_TYPE configuration:nil URL:url options:nil error:&error];
                
                if (newStore == nil) {
                    NSLog(@"Store Configuration Failure %@", ([error localizedDescription] != nil) ? [error localizedDescription] : @"Unknown Error");
                }
                
                NSFetchRequest *fetchRequest = [NSFetchRequest new];
                fetchRequest.entity = [EntityWithCustomClass entityInManagedObjectContext:context];
                fetchRequest.includesPendingChanges = YES;
                NSArray *tempResults = [context executeFetchRequest:fetchRequest error:NULL];
                
                for (EntityWithCustomClass *o in tempResults) {
                    [o willAccessValueForKey:nil];
                }
                
                results = [[tempResults mutableCopy] copy]; // We can be sure that 'results' is not a magic CoreData NSArray
            });
            
        }

        
        [[NSRunLoop mainRunLoop] run];
    }
    GDCoreDataConcurrencyDebuggingEndTrackingAutorelease();
    return 0;
}

