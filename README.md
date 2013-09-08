# GDCoreDataConcurrencyDebugging

[![Version](http://cocoapod-badges.herokuapp.com/v/GDCoreDataConcurrencyDebugging/badge.png)](http://cocoadocs.org/docsets/GDCoreDataConcurrencyDebugging)
[![Platform](http://cocoapod-badges.herokuapp.com/p/GDCoreDataConcurrencyDebugging/badge.png)](http://cocoadocs.org/docsets/GDCoreDataConcurrencyDebugging)

GDCoreDataConcurrencyDebugging helps you find cases where NSManagedObject's are being called on the wrong thread or dispatch queue.  Simply add it to your project and you will get a log message for every invalid access to an NSManagedObject.

For example the following code will trigger a console message:

    __block NSManagedObject *objectInContext1 = nil;
    [context1 performBlockAndWait:^{
        objectInContext1 = [[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:context1];
        objectInContext1.name = @"test";
        [context1 save:NULL];
    }];

    // Invalid access
    NSString *name = objectInContext2.name;
    

If you use ARC, you may see many invalid `-autorelease` messages being sent by code which is otherwise valid.  For example:

    // This code is safe even if not in a -performBlock...: method because only -objectID is being sent.
    NSMutableArray *objectIDs = [NSMutableArray new];
    for (NSManagedObject *object in results) {
        // IdentityFunction simply returns object, but the compiler will generate -autorelease calls (at least with optimisations turned off)
        [objectIDs addObject:[IdentityFunction(object) objectID]]; 
    }




## Usage

To run the example project; clone the repo, and run `pod install` from the Project directory first.

## Requirements

## Installation

GDCoreDataConcurrencyDebugging is available through [CocoaPods](http://cocoapods.org), to install
it simply add the following line to your Podfile:

    pod "GDCoreDataConcurrencyDebugging"

## Author

Graham Dennis, graham@grahamdennis.me

## License

GDCoreDataConcurrencyDebugging is available under the MIT license. See the LICENSE file for more info.

