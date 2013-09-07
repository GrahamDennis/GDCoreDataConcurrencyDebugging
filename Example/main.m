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


int main(int argc, const char * argv[])
{

    @autoreleasepool {
        GDConcurrencyCheckingManagedObjectSetFailureHandler(ConcurrencyFailure);
        // Create the managed object context
        NSManagedObjectContext *context1 = managedObjectContext();
        //        id proxy = GDFastProxyForObject(context1);
        
        NSManagedObjectContext *context2 = managedObjectContext();
        
        [[NSNotificationCenter defaultCenter] addObserverForName:NSManagedObjectContextDidSaveNotification object:context1 queue:nil
                                                      usingBlock:^(NSNotification *note) {
                                                          [context2 performBlockAndWait:^{
                                                              [context2 mergeChangesFromContextDidSaveNotification:note];
                                                          }];
                                                      }];
        
        NSEntityDescription *entity = [NSEntityDescription entityForName:@"Entity" inManagedObjectContext:context1];
        
        __block NSManagedObject *objectInContext1 = nil;
        [context1 performBlockAndWait:^{
            objectInContext1 = [[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:context1];
            objectInContext1.name = @"test";
            [context1 save:NULL];
        }];
        
        __block NSManagedObject *objectInContext2 = nil;
        [context2 performBlockAndWait:^{
            objectInContext2 = [context2 objectRegisteredForID:[objectInContext1 objectID]];
        }];
        
        // Invalid access
        NSString *name = objectInContext2.name;
        NSLog(@"name: %@", name);
        
        [context1 performBlockAndWait:^{
            [context1 deleteObject:objectInContext1];
            [context1 save:NULL];
        }];
        
        __block NSArray *results = nil;
        
        [context2 performBlockAndWait:^{
            
            for (NSString *name in @[@"a", @"b", @"c"]) {
                EntityWithCustomClass *object = [EntityWithCustomClass insertInManagedObjectContext:context2];
                object.name = name;
            }
            
            [context2 save:NULL];
            
            NSFetchRequest *fetchRequest = [NSFetchRequest new];
            fetchRequest.entity = [EntityWithCustomClass entityInManagedObjectContext:context2];
            NSArray *tempResults = [context2 executeFetchRequest:fetchRequest error:NULL];
            
            results = [[tempResults mutableCopy] copy]; // We can be sure that 'results' is not a magic CoreData NSArray
        }];

        @autoreleasepool {
            // This code happens to be safe...
            NSMutableArray *objectIDs = [NSMutableArray new];
            for (EntityWithCustomClass *object in results) {
                [objectIDs addObject:object.objectID];
            }
        }

        @autoreleasepool {
            // But this code isn't because 'object' is autoreleased and could be sent -release or -dealloc on the wrong thread.
            NSMutableArray *objectIDs = [NSMutableArray new];
            [results enumerateObjectsUsingBlock:^(EntityWithCustomClass *object, NSUInteger idx, BOOL *stop) {
                [objectIDs addObject:object.objectID];
            }];
            
            objectIDs = nil;
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
        
        [[NSRunLoop mainRunLoop] run];
    }
    return 0;
}

