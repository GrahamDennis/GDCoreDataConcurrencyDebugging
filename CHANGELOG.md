# GDCoreDataConcurrencyDebugging CHANGELOG

## 0.0.6

Fixed validation of NSMainQueueConcurrencyType

## 0.0.5

Fixed false positive caused by Core Data deallocating NSManagedObjects on a background queue

## 0.0.4

More robust setting of the concurrency identifier of NSManagedObjectContext's by setting at at init time.

## 0.0.3

Fixed concurrency validation when nested contexts are used and added a testsuite.

## 0.0.1

Initial release.

