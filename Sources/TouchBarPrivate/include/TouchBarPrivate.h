//
//  TouchBarPrivate.h
//  Declarations for Apple SPI that is not in the public SDK.
//
//  None of this is documented or supported. The symbols live in
//  AppKit and /System/Library/PrivateFrameworks/DFRFoundation.framework.
//  Shipping them rules the app out of the Mac App Store, and a macOS
//  update can remove them. Guard every call site with a runtime check.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Places an item in the Control Strip (the fixed cluster on the right of
/// the Touch Bar). This is how we get a permanent entry point that works
/// no matter which app is frontmost.
@interface NSTouchBarItem (TMBPrivate)
+ (void)addSystemTrayItem:(nullable NSTouchBarItem *)item;
+ (void)removeSystemTrayItem:(nullable NSTouchBarItem *)item;
@end

/// Presents a touch bar over the whole bar, outside the normal
/// responder-chain mechanism, so it stays up across app switches.
@interface NSTouchBar (TMBPrivate)
+ (void)presentSystemModalTouchBar:(nullable NSTouchBar *)touchBar
                         placement:(long long)placement
          systemTrayItemIdentifier:(nullable NSTouchBarItemIdentifier)identifier;
+ (void)dismissSystemModalTouchBar:(nullable NSTouchBar *)touchBar;
+ (void)minimizeSystemModalTouchBar:(nullable NSTouchBar *)touchBar;
@end

/// Controls whether the Control Strip shows our item.
extern void DFRElementSetControlStripPresenceForIdentifier(NSTouchBarItemIdentifier identifier,
                                                           BOOL present);

/// When YES, a system-modal bar gets an "x" to dismiss it. We want NO:
/// the bar should be ours until the user says otherwise.
extern void DFRSystemModalShowsCloseBoxWhenFrontMost(BOOL shows);

NS_ASSUME_NONNULL_END
