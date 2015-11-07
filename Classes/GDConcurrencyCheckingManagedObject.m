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
#import <dlfcn.h>

#import <JRSwizzle/JRSwizzle.h>
#import <libkern/OSAtomic.h>

#import "fishhook.h"

static pthread_mutex_t gMutex;
static pthread_key_t gAutoreleaseTrackingStateKey;
static pthread_key_t gInAutoreleaseKey;
static NSMutableSet *gCustomSubclasses;
static NSMutableDictionary *gCustomSubclassMap; // maps regular classes to their custom subclasses
static NSMutableSet *gSwizzledEntityClasses;

static void *GDInAutoreleaseState_NotInAutorelease = NULL;
static void *GDInAutoreleaseState_InAutorelease = &GDInAutoreleaseState_InAutorelease;

NSUInteger GDOperationQueueConcurrencyType = 
#ifdef GDCOREDATACONCURRENCYDEBUGGING_DISABLED
NSConfinementConcurrencyType;
#else
42;
#endif

#ifdef GD_CORE_DATA_CONCURRENCE_DEBUGGING_ENABLE_EXCEPTION
static NSString *const GDInvalidConcurrentAccesOnReleaseException = @"GDInvalidConcurrentAccesOnReleaseException";
static NSString *const GDInvalidConcurrentAccesException = @"GDInvalidConcurrentAccesException";
#endif

#define WhileLocked(block) do { \
    pthread_mutex_lock(&gMutex); \
    block \
    pthread_mutex_unlock(&gMutex); \
    } while(0)

static Class CreateCustomSubclass(Class class);
static void RegisterCustomSubclass(Class subclass, Class superclass);

@interface GDAutoreleaseTracker : NSObject

+ (void)createTrackerForObject:(NSObject *)object callStack:(NSArray *)callStack;

@property (nonatomic, copy) NSArray *autoreleaseBacktrace;
@property (nonatomic, strong) NSObject *object;

@end


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

void GDCoreDataConcurrencyDebuggingSetFailureHandler(void (*failureFunction)(SEL _cmd))
{
    GDConcurrencyFailureFunction = failureFunction;
}

#pragma mark -

// COREDATA_CONCURRENCY_AVAILABLE is defined if the NSManagedObjectContext has the concurrencyType attribute
#if (__MAC_OS_X_VERSION_MIN_REQUIRED >= __MAC_10_7) || (__IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_5_0)
    #define COREDATA_CONCURRENCY_AVAILABLE
#endif

static Class GetCustomSubclass(Class class)
{
    WhileLocked({
        while(class && ![gCustomSubclasses containsObject: class])
            class = class_getSuperclass(class);
    });
    return class;
}

static Class GetRealSuperclass(id obj)
{
    Class class = GetCustomSubclass(object_getClass(obj));
    NSCAssert1(class, @"Coudn't find GDCoreDataConcurrencyDebugging subclass in hierarchy starting from %@, should never happen", object_getClass(obj));
    return class_getSuperclass(class);
}

static const void *ConcurrencyIdentifierKey = &ConcurrencyIdentifierKey;
static const void *ConcurrencyTypeKey = &ConcurrencyTypeKey;
static NSValue *ConcurrencyIdentifiersThreadDictionaryKey = nil;
static NSValue *ConcurrencyValidAutoreleaseThreadDictionaryKey = nil;

#define dispatch_current_queue() ({                                                    \
      _Pragma("clang diagnostic push");                                                \
      _Pragma("clang diagnostic ignored \"-Wdeprecated-declarations\"");               \
      dispatch_queue_t queue = dispatch_get_current_queue(); \
      _Pragma("clang diagnostic pop");                                                 \
      queue;                                                                           \
    })
static void BreakOnInvalidConcurrentAccessOnRelease(NSString *classStringRepresentation, NSArray *autoreleaseBacktrace, NSSet *invalidlyAccessedObjectsSet)

{
#ifndef GD_CORE_DATA_CONCURRENCE_DEBUGGING_DISABLE_LOG
    NSLog(@"If you want to break on invalid concurrent access, add a breakpoint on symbol BreakOnInvalidConcurrentAccessOnRelease");
    NSLog(@"Invalid concurrent access to object of class '%@' caused by earlier autorelease.  The autorelease pool was drained outside of the appropriate context for some managed objects.  You need to add an @autoreleasepool{} directive to ensure this object is released within the NSManagedObject's queue.\nOriginal autorelease backtrace: %@; Invalidly accessed objects: %@"
          , classStringRepresentation
          , autoreleaseBacktrace
          , invalidlyAccessedObjectsSet);
#endif
    
#ifdef GD_CORE_DATA_CONCURRENCE_DEBUGGING_ENABLE_EXCEPTION
    [NSException raise:GDInvalidConcurrentAccesOnReleaseException
                format:@"Invalid concurrent access to object of class '%@' caused by earlier autorelease.  The autorelease pool was drained outside of the appropriate context for some managed objects.  You need to add an @autoreleasepool{} directive to ensure this object is released within the NSManagedObject's queue.\nOriginal autorelease backtrace: %@; Invalidly accessed objects: %@"
     , classStringRepresentation
     , autoreleaseBacktrace
     , invalidlyAccessedObjectsSet];
#endif
}

static void BreakOnInvalidConcurrentAccess(NSString *selectorStringRepresentation, NSArray *callStackSymbols)
{
#ifndef GD_CORE_DATA_CONCURRENCE_DEBUGGING_DISABLE_LOG
    NSLog(@"If you want to break on invalid concurrent access, add a breakpoint on symbol BreakOnInvalidConcurrentAccess");
    NSLog(@"Invalid concurrent access to managed object calling '%@'; Stacktrace: %@"
          , selectorStringRepresentation
          , callStackSymbols);
#endif
    
#ifdef GD_CORE_DATA_CONCURRENCE_DEBUGGING_ENABLE_EXCEPTION
    [NSException raise:GDInvalidConcurrentAccesException
                format:@"Invalid concurrent access to managed object calling '%@'; Stacktrace: %@"
     , selectorStringRepresentation
     , callStackSymbols];
#endif
}


static BOOL ValidateConcurrencyForObjectWithExpectedIdentifier(id object, void *expectedConcurrencyIdentifier)
{
    NSCParameterAssert(object);
    NSCParameterAssert(expectedConcurrencyIdentifier);
    
#ifdef COREDATA_CONCURRENCY_AVAILABLE
    NSManagedObjectContextConcurrencyType concurrencyType = (NSManagedObjectContextConcurrencyType)objc_getAssociatedObject(object, ConcurrencyTypeKey);
    if (concurrencyType == NSConfinementConcurrencyType) {
#endif
        return pthread_self() == expectedConcurrencyIdentifier;
#ifdef COREDATA_CONCURRENCY_AVAILABLE
    } else if (concurrencyType == GDOperationQueueConcurrencyType) {
        NSOperationQueue *operationQueue = [NSOperationQueue currentQueue];
        return (operationQueue == expectedConcurrencyIdentifier) && ([operationQueue maxConcurrentOperationCount] == 1);
    } else if (concurrencyType == NSMainQueueConcurrencyType && [NSThread isMainThread]) {
        return YES;
    } else {
        dispatch_queue_t current_queue = dispatch_current_queue();
        if (current_queue == expectedConcurrencyIdentifier) return YES;
        NSArray *concurrencyIdentifiers = [[[NSThread currentThread] threadDictionary] objectForKey:ConcurrencyIdentifiersThreadDictionaryKey];
        return [concurrencyIdentifiers containsObject:[NSValue valueWithPointer:expectedConcurrencyIdentifier]];
    }
#endif
}

static void *GetConcurrencyIdentifierForContext(NSManagedObjectContext *context)
{
    return objc_getAssociatedObject(context, ConcurrencyIdentifierKey);
}

static void *GetConcurrencyTypeForContext(NSManagedObjectContext *context)
{
    return objc_getAssociatedObject(context, ConcurrencyTypeKey);
}

static void SetConcurrencyIdentifierForContext(NSManagedObjectContext *context)
{
    void *concurrencyIdentifier = GetConcurrencyIdentifierForContext(context);
    if (concurrencyIdentifier) return;
    
#ifdef COREDATA_CONCURRENCY_AVAILABLE
    NSManagedObjectContextConcurrencyType concurrencyType = (NSManagedObjectContextConcurrencyType)GetConcurrencyTypeForContext(context);
    if (concurrencyType == NSConfinementConcurrencyType) {
#endif
        concurrencyIdentifier = pthread_self();
#ifdef COREDATA_CONCURRENCY_AVAILABLE
    } else if (concurrencyType == GDOperationQueueConcurrencyType) {
        NSOperationQueue *operationQueue = [NSOperationQueue currentQueue];
        NSCParameterAssert(operationQueue != nil);
        NSCParameterAssert([operationQueue maxConcurrentOperationCount] == 1);
        concurrencyIdentifier = (void *)operationQueue;
    } else if (concurrencyType == NSMainQueueConcurrencyType
               || concurrencyType == NSPrivateQueueConcurrencyType) {
        __block dispatch_queue_t confinementQueue = NULL;
        if (concurrencyType == NSMainQueueConcurrencyType)
            confinementQueue = dispatch_get_main_queue();
        else {
            // Get the context queue by running a block on it
            // Note that nested -performBlockAndWait calls are safe.
            [context performBlockAndWait:^{
                confinementQueue = dispatch_current_queue();
            }];
        }
        
        concurrencyIdentifier = confinementQueue;
    } else {
        NSCParameterAssert(NO);
    }
#endif
    objc_setAssociatedObject(context, ConcurrencyIdentifierKey, concurrencyIdentifier, OBJC_ASSOCIATION_ASSIGN);
}

static BOOL ValidateConcurrency(id object, SEL _cmd)
{
    void *desiredConcurrencyIdentifier = (void *)objc_getAssociatedObject(object, ConcurrencyIdentifierKey);
    if(nil == desiredConcurrencyIdentifier) {
        return YES;
    }
    BOOL concurrencyValid = ValidateConcurrencyForObjectWithExpectedIdentifier(object, desiredConcurrencyIdentifier);
    if (!concurrencyValid) {
        NSMutableSet *trackingState = pthread_getspecific(gAutoreleaseTrackingStateKey);
        if (trackingState != nil) {
            [trackingState addObject:object];
        } else if (GDConcurrencyFailureFunction) {
            GDConcurrencyFailureFunction(_cmd);
        } else {
            BreakOnInvalidConcurrentAccess(NSStringFromSelector(_cmd), [NSThread callStackSymbols]);
        }
    }
    return concurrencyValid;
}

#pragma mark - Dynamic Subclass method implementations

static void CustomSubclassRelease(id self, SEL _cmd)
{
    ValidateConcurrency(self, _cmd);
    Class superclass = GetRealSuperclass(self);
    IMP superRelease = class_getMethodImplementation(superclass, _cmd);
    ((void (*)(id, SEL))superRelease)(self, _cmd);
}

static id CustomSubclassAutorelease(id self, SEL _cmd)
{
    ValidateConcurrency(self, _cmd);
    Class superclass = GetRealSuperclass(self);
    IMP superAutorelease = class_getMethodImplementation(superclass, _cmd);
    return ((id (*)(id, SEL))superAutorelease)(self, _cmd);
}

static void CustomSubclassWillAccessValueForKey(id self, SEL _cmd, NSString *key)
{
    ValidateConcurrency(self, _cmd);
    Class superclass = GetRealSuperclass(self);
    IMP superWillAccessValueForKey = class_getMethodImplementation(superclass, _cmd);
    ((void (*)(id, SEL, id))superWillAccessValueForKey)(self, _cmd, key);
}

static void CustomSubclassWillChangeValueForKey(id self, SEL _cmd, NSString *key)
{
    ValidateConcurrency(self, _cmd);
    Class superclass = GetRealSuperclass(self);
    IMP superWillChangeValueForKey = class_getMethodImplementation(superclass, _cmd);
    ((void (*)(id, SEL, id))superWillChangeValueForKey)(self, _cmd, key);
}

static void CustomSubclassWillChangeValueForKeyWithSetMutationUsingObjects(id self, SEL _cmd, NSString *key, NSKeyValueSetMutationKind mutationkind, NSSet *inObjects)
{
    ValidateConcurrency(self, _cmd);
    Class superclass = GetRealSuperclass(self);
    IMP superWillChangeValueForKeyWithSetMutationUsingObjects = class_getMethodImplementation(superclass, _cmd);
    ((void (*)(id, SEL, id, NSKeyValueSetMutationKind, id))superWillChangeValueForKeyWithSetMutationUsingObjects)(self, _cmd, key, mutationkind, inObjects);
}

static BOOL CustomSubclassIsKindOfClass(id self, SEL _cmd, Class class)
{
    Class superclass = GetRealSuperclass(self);
    IMP superIsKindOfClass = class_getMethodImplementation(superclass, _cmd);
    BOOL result = ((BOOL (*)(id, SEL, Class))superIsKindOfClass)(self, _cmd, class);
    if (result) return result;
    
    Class customSubclassOfClass = GetCustomSubclass(class);
    if (customSubclassOfClass) {
        class = class_getSuperclass(customSubclassOfClass);
        return ((BOOL (*)(id, SEL, Class))superIsKindOfClass)(self, _cmd, class);
    }
    return result;
}

#pragma mark - Dynamic subclass creation and registration

static Class CreateCustomSubclass(Class class)
{
    NSString *newName = [NSString stringWithFormat: @"%s_GDCoreDataConcurrencyDebugging", class_getName(class)];
    const char *newNameC = [newName UTF8String];
    
    Class subclass = objc_allocateClassPair(class, newNameC, 0);
    
    Method release = class_getInstanceMethod(class, @selector(release));
    Method autorelease = class_getInstanceMethod(class, @selector(autorelease));
    Method willAccessValueForKey = class_getInstanceMethod(class, @selector(willAccessValueForKey:));
    Method willChangeValueForKey = class_getInstanceMethod(class, @selector(willChangeValueForKey:));
    Method willChangeValueForKeyWithSetMutationUsingObjects = class_getInstanceMethod(class, @selector(willChangeValueForKey:withSetMutation:usingObjects:));
    Method isKindOfClass = class_getInstanceMethod(class, @selector(isKindOfClass:));
    
    // We do not override dealloc because if a context has more than 300 objects it has references to, the objects will be deallocated on a background queue
    // This would normally be considered unsafe access, but as its Core Data doing this, we must assume it to be safe.
    // We shouldn't get miss any unsafe concurrency because in normal circumstances, -release will be called on the objects, which itself would trigger deallocation.
    
    class_addMethod(subclass, @selector(release), (IMP)CustomSubclassRelease, method_getTypeEncoding(release));
    class_addMethod(subclass, @selector(autorelease), (IMP)CustomSubclassAutorelease, method_getTypeEncoding(autorelease));
    class_addMethod(subclass, @selector(willAccessValueForKey:), (IMP)CustomSubclassWillAccessValueForKey, method_getTypeEncoding(willAccessValueForKey));
    class_addMethod(subclass, @selector(willChangeValueForKey:), (IMP)CustomSubclassWillChangeValueForKey, method_getTypeEncoding(willChangeValueForKey));
    class_addMethod(subclass, @selector(willChangeValueForKey:withSetMutation:usingObjects:), (IMP)CustomSubclassWillChangeValueForKeyWithSetMutationUsingObjects, method_getTypeEncoding(willChangeValueForKeyWithSetMutationUsingObjects));
    class_addMethod(subclass, @selector(isKindOfClass:), (IMP)CustomSubclassIsKindOfClass, method_getTypeEncoding(isKindOfClass));
    
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

+ (Class)classForEntity:(NSEntityDescription *)entity;

- (id)gd_initWithEntity:(NSEntityDescription *)entity insertIntoManagedObjectContext:(NSManagedObjectContext *)context;

- (Class)grd_class;

@end

@interface NSManagedObjectContext (GDCoreDataConcurrencyChecking)

#ifdef COREDATA_CONCURRENCY_AVAILABLE
- (id)gd_initWithConcurrencyType:(NSManagedObjectContextConcurrencyType)type;
#else
- (id)gd_init;
#endif

@end

@interface NSObject (AutoreleaseTracking)

- (id)gd_autorelease;

@end

struct DispatchWrapperState {
    void *context;
    void (*function)(void *);
    NSSet *concurrencyIdentifiers;
    dispatch_block_t block;
};

static void DispatchTargetFunctionWrapper(void *context)
{
    struct DispatchWrapperState *state = (struct DispatchWrapperState *)context;
    
    NSMutableDictionary *threadDictionary = [[NSThread currentThread] threadDictionary];
    
    // Save the old concurrency identifier array, if there was one.
    id oldConcurrencyIdentifiers = [[threadDictionary objectForKey:ConcurrencyIdentifiersThreadDictionaryKey] retain];
    
    [threadDictionary setObject:state->concurrencyIdentifiers forKey:ConcurrencyIdentifiersThreadDictionaryKey];
    
    if (state->function)
        state->function(state->context);
    else
        state->block();
    
    // Restore the old concurrency identifier array, if there was one.
    if (oldConcurrencyIdentifiers)
        [threadDictionary setObject:oldConcurrencyIdentifiers forKey:ConcurrencyIdentifiersThreadDictionaryKey];
    else
        [threadDictionary removeObjectForKey:ConcurrencyIdentifiersThreadDictionaryKey];
    
    [oldConcurrencyIdentifiers release];
}

static void DispatchSyncWrapper(dispatch_queue_t queue, void *context, void (*function)(void *), dispatch_block_t block, void *dispatch_call)
{
    // Create or obtain an array of valid concurrency identifiers for the callee block
    // This list of concurrency identifiers is basically a stack of the current set of queues that we are logically synchronously executing on,
    // even if we aren't executing on that thread.  For example, if we dispatch_sync from a background queue to the main queue, the two queues will
    // presently be running on different threads, but the block on the main queue is essentially operating on the background queue too.
    NSSet *concurrencyIdentifiers = [[[NSThread currentThread] threadDictionary] objectForKey:ConcurrencyIdentifiersThreadDictionaryKey];
    if (!concurrencyIdentifiers) {
        concurrencyIdentifiers = [NSSet set];
    }
    concurrencyIdentifiers = [concurrencyIdentifiers setByAddingObject:[NSValue valueWithPointer:dispatch_current_queue()]];
    
    [concurrencyIdentifiers retain];
    
    struct DispatchWrapperState state = {context, function, concurrencyIdentifiers, block};
    
    // Passing 'state' on the stack frame is OK because this is a sync function call
    if (function) {
        ((void (*)(dispatch_queue_t, void*, void (*)(void *)))dispatch_call)(queue, &state, DispatchTargetFunctionWrapper);
    } else {
        ((void (*)(dispatch_queue_t, dispatch_block_t))dispatch_call)(queue, ^{
            DispatchTargetFunctionWrapper((void *)&state);
        });
    }
    
    [concurrencyIdentifiers release];
}

#define DISPATCH_WRAPPER(dispatch_function)                                                                     \
static void (*original_ ## dispatch_function) (dispatch_queue_t, void *, void (*)(void *));                     \
static void wrapper_ ## dispatch_function (dispatch_queue_t queue, void *context, void (*function)(void *))     \
{                                                                                                               \
    DispatchSyncWrapper(queue, context, function, nil, original_ ## dispatch_function);                         \
}

#define DISPATCH_BLOCK_WRAPPER(dispatch_function)                                                               \
static void (*original_ ## dispatch_function) (dispatch_queue_t, dispatch_block_t);                             \
static void wrapper_ ## dispatch_function (dispatch_queue_t queue, dispatch_block_t block)                      \
{                                                                                                               \
    DispatchSyncWrapper(queue, NULL, NULL, block, original_ ## dispatch_function);                              \
}

DISPATCH_WRAPPER(dispatch_sync_f);
DISPATCH_WRAPPER(dispatch_barrier_sync_f);
DISPATCH_BLOCK_WRAPPER(dispatch_sync);
DISPATCH_BLOCK_WRAPPER(dispatch_barrier_sync);

static void EmptyFunction() {}

__attribute__ ((constructor))
static void Initialise()
{
    pthread_key_create(&gAutoreleaseTrackingStateKey, NULL);
    pthread_key_create(&gInAutoreleaseKey, NULL);
}

static void GDCoreDataConcurrencyDebuggingInitialise()
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Instrument dispatch_sync calls to keep track of the stack of synchronous queues.
        {
            ConcurrencyIdentifiersThreadDictionaryKey = [[NSValue valueWithPointer:&ConcurrencyIdentifiersThreadDictionaryKey] retain];
            ConcurrencyValidAutoreleaseThreadDictionaryKey = [[NSValue valueWithPointer:&ConcurrencyValidAutoreleaseThreadDictionaryKey] retain];
            
            Dl_info info;
            
            // We need to make sure every function that we're rebinding has been called in this module before they are rebound.
            // This ensures that when rebind_symbols is called, it will find the correct value for the symbol in the lookup table
            // for this module.  This is then used to set the original_dispatch_* function pointers.
            {
                dispatch_queue_t q = dispatch_queue_create("foo", DISPATCH_QUEUE_SERIAL);
                dispatch_sync_f(q, NULL, EmptyFunction);
                dispatch_barrier_sync_f(q, NULL, EmptyFunction);
                dispatch_sync(q, ^{});
                dispatch_barrier_sync(q, ^{});
                dispatch_release(q);
            }
            
            // We need to get our module name so we know which module we know has the symbol resolved.
            dladdr(EmptyFunction, &info);
            
            struct rebinding rebindings[] = {
                {"dispatch_sync_f",         wrapper_dispatch_sync_f,            info.dli_fname, (void**)&original_dispatch_sync_f},
                {"dispatch_barrier_sync_f", wrapper_dispatch_barrier_sync_f,    info.dli_fname, (void**)&original_dispatch_barrier_sync_f},
                {"dispatch_sync",           wrapper_dispatch_sync,              info.dli_fname, (void**)&original_dispatch_sync},
                {"dispatch_barrier_sync",   wrapper_dispatch_barrier_sync,      info.dli_fname, (void**)&original_dispatch_barrier_sync}
            };
            
            int retval = rebind_symbols(rebindings, sizeof(rebindings)/sizeof(struct rebinding));
            NSCAssert(retval == 0, @"ERROR: Failed to rebind symbols.  Concurrency debugging will not work!");
        }
        
        // Locks for the custom subclasses
        pthread_mutexattr_t mutexattr;
        pthread_mutexattr_init(&mutexattr);
        pthread_mutexattr_settype(&mutexattr, PTHREAD_MUTEX_RECURSIVE);
        pthread_mutex_init(&gMutex, &mutexattr);
        pthread_mutexattr_destroy(&mutexattr);
        
        gCustomSubclasses = [NSMutableSet new];
        gCustomSubclassMap = [NSMutableDictionary new];
        gSwizzledEntityClasses = [NSMutableSet new];

    });
}

static void AssignExpectedIdentifiersToObjectFromContext(id object, NSManagedObjectContext *context)
{
    if (context) {
        // Assign expected concurrency identifier
        objc_setAssociatedObject(object, ConcurrencyIdentifierKey, GetConcurrencyIdentifierForContext(context), OBJC_ASSOCIATION_ASSIGN);
#ifdef COREDATA_CONCURRENCY_AVAILABLE
        // Assign concurrency type in case the context is released before this object is.
        objc_setAssociatedObject(object, ConcurrencyTypeKey, GetConcurrencyTypeForContext(context), OBJC_ASSOCIATION_ASSIGN);
#endif
    }
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"
@implementation NSManagedObject (GDCoreDataConcurrencyChecking)
#pragma clang diagnostic pop

#ifndef GDCOREDATACONCURRENCYDEBUGGING_DISABLED
+ (void)load
{
    // Swizzle some methods so we can set up when a MOC or managed object is created.
    NSError *error = nil;
    if (![self jr_swizzleMethod:@selector(initWithEntity:insertIntoManagedObjectContext:) withMethod:@selector(gd_initWithEntity:insertIntoManagedObjectContext:) error:&error]) {
        NSLog(@"Failed to swizzle with error: %@", error);
    }
#ifdef COREDATA_CONCURRENCY_AVAILABLE
    if (![NSManagedObjectContext jr_swizzleMethod:@selector(initWithConcurrencyType:) withMethod:@selector(gd_initWithConcurrencyType:) error:&error])
#else
    if (![NSManagedObjectContext jr_swizzleMethod:@selector(init) withMethod:@selector(gd_init) error:&error])
#endif
    {
        NSLog(@"Failed to swizzle with error: %@", error);
    }
    
    if (![NSObject jr_swizzleMethod:@selector(autorelease) withMethod:@selector(gd_autorelease) error:&error])
    {
        NSLog(@"Failed to swizzle with error: %@", error);
    }
    
    if (![self jr_swizzleClassMethod:@selector(classForEntity:) withClassMethod:@selector(grd_classForEntity:) error:&error]) {
        NSLog(@"Failed to swizzle with error: %@", error);
    }
}
#endif

+ (Class)grd_classForEntity:(NSEntityDescription *)entity
{
    Class entityClass = [self grd_classForEntity:entity];
    
    WhileLocked({
        if (![gSwizzledEntityClasses containsObject:entityClass]) {
            NSError *error = nil;
            if (![entityClass jr_swizzleMethod:@selector(class) withMethod:@selector(grd_class) error:&error]) {
                NSLog(@"Failed to swizzle entity class %@ due to error: %@", entityClass, error);
            } else {
                [gSwizzledEntityClasses addObject:entityClass];
            }
        }
    });
    
    return entityClass;
}

- (id)gd_initWithEntity:(NSEntityDescription *)entity insertIntoManagedObjectContext:(NSManagedObjectContext *)context
{
    self = [self gd_initWithEntity:entity insertIntoManagedObjectContext:context];

    GDCoreDataConcurrencyDebuggingInitialise();
    
    AssignExpectedIdentifiersToObjectFromContext(self, context);
    return self;
}

- (Class)grd_class
{
    return GetRealSuperclass(self);
}

@end

@implementation NSManagedObjectContext (GDCoreDataConcurrencyChecking)

#ifdef COREDATA_CONCURRENCY_AVAILABLE
- (id)gd_initWithConcurrencyType:(NSManagedObjectContextConcurrencyType)type
{
    NSManagedObjectContextConcurrencyType underlyingConcurrencyType = type;
    if (type == GDOperationQueueConcurrencyType)
        underlyingConcurrencyType = NSConfinementConcurrencyType;
    
    self = [self gd_initWithConcurrencyType:underlyingConcurrencyType];
    objc_setAssociatedObject(self, ConcurrencyTypeKey, (void *)type, OBJC_ASSOCIATION_ASSIGN);
#else
- (id)gd_init
{
    self = [self gd_init];
#if 0
}}
#endif
#endif
    
    GDCoreDataConcurrencyDebuggingInitialise();

    SetConcurrencyIdentifierForContext(self);

    return self;
}

@end

@implementation GDAutoreleaseTracker

+ (void)createTrackerForObject:(NSObject *)object callStack:(NSArray *)callStack
{
    [[[GDAutoreleaseTracker alloc] initWithObject:object callStack:callStack] autorelease];
}

- (void)dealloc
{
    NSMutableSet *invalidlyAccessedObjectsSet = [NSMutableSet new];
    pthread_setspecific(gAutoreleaseTrackingStateKey, invalidlyAccessedObjectsSet);

    Class cls = object_getClass(_object);
    
    self.object = nil;
    BOOL wasValidRelease = [invalidlyAccessedObjectsSet count] == 0;
    
    if (!wasValidRelease) {
        BreakOnInvalidConcurrentAccessOnRelease(NSStringFromClass(cls), self.autoreleaseBacktrace, invalidlyAccessedObjectsSet);
    }
    pthread_setspecific(gAutoreleaseTrackingStateKey, nil);
    self.autoreleaseBacktrace = nil;
    
    [super dealloc];
}

- (id)initWithObject:(NSObject *)object callStack:(NSArray *)callStack
{
    if ((self = [super init])) {
        self.object = object;
        self.autoreleaseBacktrace = callStack;
    }
    
    return self;
}

@end

static int32_t GDTrackAutoreleaseCounter = 0;

void GDCoreDataConcurrencyDebuggingBeginTrackingAutorelease()
{
    OSAtomicIncrement32Barrier(&GDTrackAutoreleaseCounter);
}

void GDCoreDataConcurrencyDebuggingEndTrackingAutorelease()
{
    OSAtomicDecrement32Barrier(&GDTrackAutoreleaseCounter);
}

@implementation NSObject (AutoreleaseTracking)

- (id)gd_autorelease
{
    if (GDTrackAutoreleaseCounter == 0) { return [self gd_autorelease]; }
    
    BOOL inAutorelease = pthread_getspecific(gInAutoreleaseKey) == GDInAutoreleaseState_InAutorelease;
    if (!inAutorelease) {
        pthread_setspecific(gInAutoreleaseKey, GDInAutoreleaseState_InAutorelease);
        [GDAutoreleaseTracker createTrackerForObject:self callStack:[NSThread callStackSymbols]];

        pthread_setspecific(gInAutoreleaseKey, GDInAutoreleaseState_NotInAutorelease);
        return self;
    } else {
        return [self gd_autorelease];
    }
}

@end