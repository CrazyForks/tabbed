#ifndef TABBED_BRIDGING_HEADER_H
#define TABBED_BRIDGING_HEADER_H

#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

typedef int CGSConnectionID;

CGSConnectionID _CGSDefaultConnection(void);
CFArrayRef CGSCopySpacesForWindows(CGSConnectionID cid, int mask, CFArrayRef windows);
CFArrayRef CGSCopyManagedDisplaySpaces(CGSConnectionID cid);
uint64_t CGSManagedDisplayGetCurrentSpace(CGSConnectionID cid, CFStringRef displayIdentifier);
CGError CGSMoveWindowsToManagedSpace(CGSConnectionID cid, CFArrayRef windows, uint64_t spaceID);

AXError _AXUIElementGetWindow(AXUIElementRef element, uint32_t *identifier);

#endif /* TABBED_BRIDGING_HEADER_H */
