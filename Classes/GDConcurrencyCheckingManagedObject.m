//
//  GDConcurrencyCheckingManagedObject.m
//  Pods
//
//  Created by Graham Dennis on 7/09/13.
//
//

// The following includes modified versions of Mike Ash's MAZeroingWeakRef/MAZeroingWeakRef.m which is licensed under BSD.
// The license for that file is as follows:
//    MAZeroingWeakRef and all code associated with it is distributed under a BSD license, as listed below.
//
//
//    Copyright (c) 2010, Michael Ash
//    All rights reserved.
//
//    Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
//
//    Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
//
//    Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
//
//    Neither the name of Michael Ash nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
//
//    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


#import "GDConcurrencyCheckingManagedObject.h"

#import <CoreData/CoreData.h>
#import <pthread.h>
#import <objc/runtime.h>

#import <JRSwizzle/JRSwizzle.h>

static pthread_mutex_t gMutex;
static NSMutableSet *gCustomSubclasses;
static NSMutableDictionary *gCustomSubclassMap; // maps regular classes to their custom subclasses

#define WhileLocked(block) do { \
    pthread_mutex_lock(&gMutex); \
    block \
    pthread_mutex_unlock(&gMutex); \
    } while(0)

static Class CreateCustomSubclass(Class class);
static void RegisterCustomSubclass(Class subclass, Class superclass);

// Public interface
Class GDConcurrencyCheckingManagedObjectClassForClass(Class managedObjectClass)
{
    Class subclass = Nil;
    WhileLocked({
        subclass = [gCustomSubclassMap objectForKey:managedObjectClass];
        if (!subclass) {
            subclass = CreateCustomSubclass(managedObjectClass);
            RegisterCustomSubclass(subclass, managedObjectClass);
        }
    });
    return subclass;
}

static void (*GDConcurrencyFailureFunction)(SEL _cmd) = NULL;

void GDConcurrencyCheckingManagedObjectSetFailureHandler(void (*failureFunction)(SEL _cmd))
{
    GDConcurrencyFailureFunction = failureFunction;
}

#pragma mark -

// COREDATA_QUEUES_AVAILABLE is defined if the NSManagedObjectContext has the concurrencyType attribute
#if (__MAC_OS_X_VERSION_MIN_REQUIRED >= __MAC_10_7) || (__IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_5_0)
    #define COREDATA_CONCURRENCY_AVAILABLE
#endif

static Class GetCustomSubclass(id obj)
{
    Class class = object_getClass(obj);
    WhileLocked({
        while(class && ![gCustomSubclasses containsObject: class])
            class = class_getSuperclass(class);
    });
    return class;
}

static Class GetRealSuperclass(id obj)
{
    Class class = GetCustomSubclass(obj);
    NSCAssert1(class, @"Coudn't find ZeroingWeakRef subclass in hierarchy starting from %@, should never happen", object_getClass(obj));
    return class_getSuperclass(class);
}

static const void *ConcurrencyIdentifierKey = &ConcurrencyIdentifierKey;
static const void *ConcurrencyTypeKey = &ConcurrencyTypeKey;

static void *CurrentConcurrencyIdentifierForManagedObject(NSManagedObject *object)
{
    NSCParameterAssert(object);
    
#ifdef COREDATA_CONCURRENCY_AVAILABLE
    NSManagedObjectContextConcurrencyType concurrencyType = (NSManagedObjectContextConcurrencyType)objc_getAssociatedObject(object, ConcurrencyTypeKey);
    if (concurrencyType == NSConfinementConcurrencyType) {
#endif
        return pthread_self();
#ifdef COREDATA_CONCURRENCY_AVAILABLE
    } else if (concurrencyType == NSMainQueueConcurrencyType) {
        return dispatch_get_current_queue();
    } else if (concurrencyType == NSPrivateQueueConcurrencyType) {
        return dispatch_get_current_queue();
    } else {
        NSCAssert(NO, @"Unknown concurrency type %i", (int)concurrencyType);
        return NULL;
    }
#endif
}

static void *EnsureContextHasConcurrencyIdentifier(NSManagedObjectContext *context)
{
    void *concurrencyIdentifier = objc_getAssociatedObject(context, ConcurrencyIdentifierKey);
    if (concurrencyIdentifier) return concurrencyIdentifier;
    
#ifdef COREDATA_CONCURRENCY_AVAILABLE
    if (context.concurrencyType == NSConfinementConcurrencyType) {
#endif
        concurrencyIdentifier = pthread_self();
#ifdef COREDATA_CONCURRENCY_AVAILABLE
    } else if (context.concurrencyType == NSMainQueueConcurrencyType) {
        concurrencyIdentifier = dispatch_get_main_queue();
    } else if (context.concurrencyType == NSPrivateQueueConcurrencyType) {
        // Get the context queue by running a block on it
        // Note that nested -performBlockAndWait calls are safe.
        __block void *tempConcurrencyIdentifier = NULL;
        [context performBlockAndWait:^{
            tempConcurrencyIdentifier = dispatch_get_current_queue();
        }];
        concurrencyIdentifier = tempConcurrencyIdentifier;
    } else {
        NSCParameterAssert(NO);
    }
#endif
    objc_setAssociatedObject(context, ConcurrencyIdentifierKey, concurrencyIdentifier, OBJC_ASSOCIATION_ASSIGN);
    return concurrencyIdentifier;
}

static void ValidateConcurrency(NSManagedObject *object, SEL _cmd)
{
    void *desiredConcurrencyIdentifier = (void *)objc_getAssociatedObject(object, ConcurrencyIdentifierKey);
    BOOL concurrencyValid = (CurrentConcurrencyIdentifierForManagedObject(object) == desiredConcurrencyIdentifier);
    if (!concurrencyValid) {
        if (GDConcurrencyFailureFunction) GDConcurrencyFailureFunction(_cmd);
        else {
            NSCAssert(concurrencyValid, @"Invalid concurrent access to managed object calling '%@'", NSStringFromSelector(_cmd));
        }
    }
}

#pragma mark - Dynamic Subclass method implementations

static void CustomSubclassRelease(id self, SEL _cmd)
{
    ValidateConcurrency(self, _cmd);
    Class superclass = GetRealSuperclass(self);
    IMP superRelease = class_getMethodImplementation(superclass, @selector(release));
    ((void (*)(id, SEL))superRelease)(self, _cmd);
}

static id CustomSubclassAutorelease(id self, SEL _cmd)
{
    ValidateConcurrency(self, _cmd);
    Class superclass = GetRealSuperclass(self);
    IMP superAutorelease = class_getMethodImplementation(superclass, @selector(autorelease));
    return ((id (*)(id, SEL))superAutorelease)(self, _cmd);
}

static void CustomSubclassDealloc(id self, SEL _cmd)
{
    ValidateConcurrency(self, _cmd);
    Class superclass = GetRealSuperclass(self);
    IMP superDealloc = class_getMethodImplementation(superclass, @selector(dealloc));
    ((void (*)(id, SEL))superDealloc)(self, _cmd);
}

static void CustomSubclassWillAccessValueForKey(id self, SEL _cmd, NSString *key)
{
    ValidateConcurrency(self, _cmd);
    Class superclass = GetRealSuperclass(self);
    IMP superWillAccessValueForKey = class_getMethodImplementation(superclass, @selector(willAccessValueForKey:));
    ((void (*)(id, SEL, id))superWillAccessValueForKey)(self, _cmd, key);
}

static void CustomSubclassWillChangeValueForKey(id self, SEL _cmd, NSString *key)
{
    ValidateConcurrency(self, _cmd);
    Class superclass = GetRealSuperclass(self);
    IMP superWillChangeValueForKey = class_getMethodImplementation(superclass, @selector(willChangeValueForKey:));
    ((void (*)(id, SEL, id))superWillChangeValueForKey)(self, _cmd, key);
}

static void CustomSubclassWillChangeValueForKeyWithSetMutationUsingObjects(id self, SEL _cmd, NSString *key, NSKeyValueSetMutationKind mutationkind, NSSet *inObjects)
{
    ValidateConcurrency(self, _cmd);
    Class superclass = GetRealSuperclass(self);
    IMP superWillChangeValueForKeyWithSetMutationUsingObjects = class_getMethodImplementation(superclass, @selector(willChangeValueForKey:withSetMutation:usingObjects:));
    ((void (*)(id, SEL, id, NSKeyValueSetMutationKind, id))superWillChangeValueForKeyWithSetMutationUsingObjects)(self, _cmd, key, mutationkind, inObjects);
}

#pragma mark - Dynamic subclass creation and registration

static Class CreateCustomSubclass(Class class)
{
    NSString *newName = [NSString stringWithFormat: @"%s_GDCoreDataConcurrencyDebugging", class_getName(class)];
    const char *newNameC = [newName UTF8String];
    
    Class subclass = objc_allocateClassPair(class, newNameC, 0);
    
    Method release = class_getInstanceMethod(class, @selector(release));
    Method autorelease = class_getInstanceMethod(class, @selector(autorelease));
    Method dealloc = class_getInstanceMethod(class, @selector(dealloc));
    Method willAccessValueForKey = class_getInstanceMethod(class, @selector(willAccessValueForKey:));
    Method willChangeValueForKey = class_getInstanceMethod(class, @selector(willChangeValueForKey:));
    Method willChangeValueForKeyWithSetMutationUsingObjects = class_getInstanceMethod(class, @selector(willChangeValueForKey:withSetMutation:usingObjects:));
    
//    class_addMethod(subclass, @selector(release), (IMP)CustomSubclassRelease, method_getTypeEncoding(release));
    class_addMethod(subclass, @selector(autorelease), (IMP)CustomSubclassAutorelease, method_getTypeEncoding(autorelease));
    class_addMethod(subclass, @selector(dealloc), (IMP)CustomSubclassDealloc, method_getTypeEncoding(dealloc));
    class_addMethod(subclass, @selector(willAccessValueForKey:), (IMP)CustomSubclassWillAccessValueForKey, method_getTypeEncoding(willAccessValueForKey));
    class_addMethod(subclass, @selector(willChangeValueForKey:), (IMP)CustomSubclassWillChangeValueForKey, method_getTypeEncoding(willChangeValueForKey));
    class_addMethod(subclass, @selector(willChangeValueForKey:withSetMutation:usingObjects:), (IMP)CustomSubclassWillChangeValueForKeyWithSetMutationUsingObjects, method_getTypeEncoding(willChangeValueForKeyWithSetMutationUsingObjects));
    
    objc_registerClassPair(subclass);
    
    return subclass;
}

// Our pthread mutex must be held for this function
static void RegisterCustomSubclass(Class subclass, Class superclass)
{
    [gCustomSubclassMap setObject: subclass forKey: (id <NSCopying>) superclass];
    [gCustomSubclasses addObject: subclass];
}


@interface NSManagedObject (GDCoreDataConcurrencyChecking)

@end

@implementation NSManagedObject (GDCoreDataConcurrencyChecking)

+ (void)load
{
    pthread_mutexattr_t mutexattr;
    pthread_mutexattr_init(&mutexattr);
    pthread_mutexattr_settype(&mutexattr, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&gMutex, &mutexattr);
    pthread_mutexattr_destroy(&mutexattr);
    
    gCustomSubclasses = [NSMutableSet new];
    gCustomSubclassMap = [NSMutableDictionary new];
    
    NSError *error = nil;
    if (![self jr_swizzleMethod:@selector(initWithEntity:insertIntoManagedObjectContext:) withMethod:@selector(gd_initWithEntity:insertIntoManagedObjectContext:) error:&error]) {
        NSLog(@"Failed to swizzle with error: %@", error);
    }
}

- (id)gd_initWithEntity:(NSEntityDescription *)entity insertIntoManagedObjectContext:(NSManagedObjectContext *)context
{
    self = [self gd_initWithEntity:entity insertIntoManagedObjectContext:context];
    if (context)
    {
        void *concurrencyIdentifier = EnsureContextHasConcurrencyIdentifier(context);
        objc_setAssociatedObject(self, ConcurrencyIdentifierKey, concurrencyIdentifier, OBJC_ASSOCIATION_ASSIGN);
#ifdef COREDATA_CONCURRENCY_AVAILABLE
        objc_setAssociatedObject(self, ConcurrencyTypeKey, (void *)context.concurrencyType, OBJC_ASSOCIATION_ASSIGN);
#endif
    }
    return self;
}


@end
