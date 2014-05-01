//
//  NSEntityDescription+GDConcurrencyDebugging.m
//  GDCoreDataConcurrencyDebugging
//
//  Created by Graham Dennis on 7/09/13.
//  Copyright (c) 2013 Graham Dennis. All rights reserved.
//

#import "NSEntityDescription+GDConcurrencyDebugging.h"
#import "GDConcurrencyCheckingManagedObject.h"

#import <JRSwizzle/JRSwizzle.h>

@implementation NSEntityDescription (GDConcurrencyDebugging)

#ifndef GDCOREDATACONCURRENCYDEBUGGING_DISABLED
+ (void)load
{
    NSError *error = nil;
    if (![self jr_swizzleMethod:@selector(managedObjectClassName)
                     withMethod:@selector(gd_managedObjectClassName)
                          error:&error]) {
        NSLog(@"Failed to swizzle with error: %@", error);
    }
}
#endif

- (NSString *)gd_managedObjectClassName
{
    NSString *normalClassName = [self gd_managedObjectClassName];
    if ([self isAbstract]) return normalClassName;
    
    Class normalClass = NSClassFromString(normalClassName);
    Class subclass = GDConcurrencyCheckingManagedObjectClassForClass(normalClass);
    NSString *subclassName = NSStringFromClass(subclass);
    return subclassName ?: normalClassName;
}

@end
