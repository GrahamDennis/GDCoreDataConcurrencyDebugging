//
//  CoreDataTestHelpers.h
//  GDCoreDataConcurrencyDebugging
//
//  Created by Graham Dennis on 12/11/13.
//  Copyright (c) 2013 Graham Dennis. All rights reserved.
//

#import <Foundation/Foundation.h>

NSManagedObjectContext *managedObjectContext();

extern NSCountedSet *ConcurrencyFailures;

@interface CoreDataTestHelpers : NSObject

@end
