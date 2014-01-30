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
    NSString *name = objectInContext1.name;
    

If you want to customise the logging you can call `GDCoreDataConcurrencyDebuggingSetFailureHandler` to set your own concurrency failure handler with function prototype `void ConcurrencyFailureHandler(SEL _cmd);`.  For example:

    #import <GDCoreDataConcurrencyDebugging/GDCoreDataConcurrencyDebugging.h>
    
    static void CoreDataConcurrencyFailureHandler(SEL _cmd)
    {
        // Simply checking _cmd == @selector(autorelease) won't work in ARC code.
        // You really shouldn't ignore -autorelease messages sent on the wrong thread,
        // but if you want to live on the wild side...
        if (_cmd == NSSelectorFromString(@"autorelease")) return;
        NSLog(@"CoreData concurrency failure: Selector '%@' called on wrong queue/thread.", NSStringFromSelector(_cmd));
    }
    
    int main()
    {
        GDCoreDataConcurrencyDebuggingSetFailureHandler(CoreDataConcurrencyFailureHandler);
    }

See my [blog post][blog-post] for more information.

## Usage

To run the example project; clone the repo, and run `pod install` from the Project directory first.  The example demonstrates some invalid CoreData code.  A particularly nasty case demonstrated is when an autorelease pool pops after the owning `NSManagedObjectContext` has been reset or dealloc'ed.

## Requirements

Mac OS X 10.6+, iOS 3.1+, [JRSwizzle]

## Installation

GDCoreDataConcurrencyDebugging is available through [CocoaPods](http://cocoapods.org), to install
it simply add the following line to your Podfile:

    pod "GDCoreDataConcurrencyDebugging"

If you're installing manually, be sure to make sure ARC is turned off for the GDCoreDataConcurrencyDebugging sources (use the `-fno-objc-arc` flag).  GDCoreDataConcurrencyDebugging can be safely linked against ARC code.  See the Example.

## How does it work?

GDCoreDataConcurrencyDebugging uses dynamic subclassing to create a custom `NSManagedObject` subclass which tracks access to instance variables and when they are modified.  Note that GDCoreDataConcurrencyDebugging does not check that CoreData faulting collections (used for relationships) are accessed correctly after they have been retrieved from an NSManagedObject.

GDCoreDataConcurrencyDebugging is based on Mike Ash's dynamic subclassing code in [MAZeroingWeakRef].

## Author

Graham Dennis, graham@grahamdennis.me



## License

GDCoreDataConcurrencyDebugging is available under the MIT license. See the LICENSE file for more info.


[MAZeroingWeakRef]: https://github.com/mikeash/MAZeroingWeakRef
[blog-post]: http://www.grahamdennis.me/blog/2013/09/09/debugging-concurrency-with-core-data/
[JRSwizzle]: https://github.com/rentzsch/jrswizzle