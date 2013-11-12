//
//  Tests.m
//  Tests
//
//  Created by Graham Dennis on 11/11/13.
//  Copyright (c) 2013 Graham Dennis. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CoreDataTestHelpers.h"
#import <GDCoreDataConcurrencyDebugging/GDConcurrencyCheckingManagedObject.h>
#import "EntityWithCustomClass.h"

@interface Tests : XCTestCase

@end

@interface NSManagedObject (EntityAccessors)

@property (nonatomic, strong) NSString *name;

@end



@implementation Tests

- (void)setUp
{
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.

    [ConcurrencyFailures removeAllObjects];
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testSimple
{
    NSManagedObjectContext *context = managedObjectContext();
    
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"Entity" inManagedObjectContext:context];
    
    __block NSManagedObject *objectInContext1 = nil;
    [context performBlockAndWait:^{
        objectInContext1 = [[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:context];
        objectInContext1.name = @"test";
        [context save:NULL];
    }];
    
    // Here's an obvious invalid access
    NSString *__unused name = objectInContext1.name;

    XCTAssertEqualObjects(ConcurrencyFailures, [NSCountedSet setWithArray:@[@"willAccessValueForKey:"]], @"Missed concurrency failure");
}



@end
