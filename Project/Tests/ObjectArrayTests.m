//
//  ObjectArrayTests.m
//  GDCoreDataConcurrencyDebugging
//
//  Created by Graham Dennis on 12/11/13.
//  Copyright (c) 2013 Graham Dennis. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CoreDataTestHelpers.h"
#import "EntityWithCustomClass.h"

@interface ObjectArrayTests : XCTestCase

@property (nonatomic, strong) NSManagedObjectContext *context;
@property (nonatomic, copy) NSArray *objects;

@end

@implementation ObjectArrayTests

- (void)setUp
{
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.

    self.context = managedObjectContext();
    
    [self.context performBlockAndWait:^{
        @autoreleasepool {
            
            for (NSString *name in @[@"a", @"b", @"c"]) {
                EntityWithCustomClass *object = [EntityWithCustomClass insertInManagedObjectContext:self.context];
                object.name = name;
            }
            
            NSFetchRequest *fetchRequest = [NSFetchRequest new];
            fetchRequest.entity = [EntityWithCustomClass entityInManagedObjectContext:self.context];
            fetchRequest.includesPendingChanges = YES;
            NSArray *tempResults = [self.context executeFetchRequest:fetchRequest error:NULL];
            
            self.objects = [[tempResults mutableCopy] copy]; // We can be sure that 'objects' is not a magic CoreData NSArray
        }
    }];

    [ConcurrencyFailures removeAllObjects];
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
    
    [self.context performBlockAndWait:^{
        self.objects = nil;
    }];
}

// With optimisations turned off, the compiler will generate an autorelease method for this method
NSManagedObject *IdentityFunction(NSManagedObject *object)
{
    return object;
}

- (void)testUnsafeRelease
{
    self.objects = nil;
    
    NSCountedSet *expectedFailures = [NSCountedSet setWithArray:@[@"release", @"release", @"release"]];
    
    XCTAssertEqualObjects(ConcurrencyFailures, expectedFailures, @"Incorrect number of release messages");
}

- (void)testSafeAccess
{
    @autoreleasepool {
        // This code is safe because we are just calling -objectID
        // But it's only safe as long as the context isn't reset (or deallocated) before the autorelease pool pops.
        NSMutableArray *objectIDs = [NSMutableArray new];
        for (EntityWithCustomClass *object in self.objects) {
            [objectIDs addObject:object.objectID];
        }
    }
    
    XCTAssertEqualObjects(ConcurrencyFailures, [NSCountedSet set], @"This should be safe");
}

- (void)testNestedContextSave
{
    NSManagedObjectContext *childContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    childContext.parentContext = self.context;
    
    [childContext performBlockAndWait:^{
        @autoreleasepool {
            EntityWithCustomClass *object = [EntityWithCustomClass insertInManagedObjectContext:childContext];
            object.name = @"test";
            
            [childContext save:NULL];
        }
    }];
    
    XCTAssertEqualObjects(ConcurrencyFailures, [NSCountedSet set], @"This should be safe");
}

@end
