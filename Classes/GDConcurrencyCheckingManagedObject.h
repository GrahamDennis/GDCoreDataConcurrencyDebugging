//
//  GDConcurrencyCheckingManagedObject.h
//  Pods
//
//  Created by Graham Dennis on 7/09/13.
//
//

extern Class GDConcurrencyCheckingManagedObjectClassForClass(Class managedObjectClass);
extern void GDCoreDataConcurrencyDebuggingSetFailureHandler(void (*failureFunction)(SEL _cmd));

extern void GDCoreDataConcurrencyDebuggingBeginTrackingAutorelease();
extern void GDCoreDataConcurrencyDebuggingEndTrackingAutorelease();