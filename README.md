# libundirect

objc_direct is a feature introduced with Xcode 12 that, when specified, turns an Objective C method into an unexported C function after compilation.

This makes it completely impossible to call the method from inside a dylib thats injected into the process, as it is also impossible to know the method name unless you have an earlier version of the binary, in which the method you're looking for was compiled without objc_direct, at hand.

Apple has started using objc_direct in system applications, daemons and frameworks starting in iOS 14.0. Some examples for affected binaries: MobileSafari, SafariServices.framework, CoreFoundation.framework...

The dyld shared cache retains all symbols of direct methods (mainly for symbolicating crash logs), this makes it extremely easy to rebind direct methods of every binary that's inside it (Frameworks, Control Center modules, etc...), instructions are [documented below](#dyld-shared-cache).

Before you can utilize libundirect, you will have to find the unexported function you're looking for via reverse engineering, this process won't be covered here. I have personally had success by searching for xrefs in an earlier binary without objc_direct, finding the methods that call your method in the new binary, hoping they are not also affected by objc_direct and finding the call to your method which will be a call to a sub_* C function now.

Examples:

![example 1](doc/libundirect_doc1.png?raw=true)

![example 2](doc/libundirect_doc2.png?raw=true)

## Installation
Run [install_to_theos.sh](install_to_theos.sh), then you can import it using `#import <libundirect/libundirect.h>`.
Also make sure to add it to your makefile:
```
<YOUR_TWEAK>_LIBRARIES = undirect
```
If you don't want to link against it, you can also use the dynamic header using `#import <libundirect/libundirect_dynamic.h>` and avoid adding it to the Makefile.

## Patchfinder

For the patchfinding process, it is important that you know the address of the unexported C function for at least one binary that you have, and that you have at least one other version of the binary where you don't know the address. This is important so you can make sure that the bytes stay the same accross different versions (as references to pointers usually change whenever the source code changes).

Now open the binary that you know the address of in a hex editor, jump to the address and start searching for unique bytes within the function. (E.g. copy a few bytes, search the binary for them, repeat until you only have one exact match inside your function for the whole binary). Once you have the bytes that may be unique, as mentioned earlier, now search for them in a different version of the binary and make sure you also only got one exact match. If you don't get a match in the other version, your bytes probably contain a sequence that changes between versions and you have to try out different bytes.

Once you have a unique byte sequence that stays the same between versions, the function [libundirect_find](libundirect.h#L25) can be used to locate your function. The start byte of the function also has to be supplied.

(Just because the byte sequence stays the same between versions it can still change in a future version if the specific instructions you're searching for are replaced with other instructions)

![example 3](doc/libundirect_doc3.png?raw=true)

(Note: While this patchfinders main intend is to find objc_direct methods, it can also be used to find any undefined C function)

## Rebinding methods

To provide backwards compatibility with older binaries, you can rebind the direct methods to the class using the [libundirect_rebind](libundirect.h#L22) function. Last argument is the [type encoding](https://nshipster.com/type-encodings/) of the method.

## Dyld Shared Cache

Finding and rebinding direct methods that are inside the dyld shared cache requires just the name of the method and the class it is on. [libundirect_dsc_find](libundirect.h#L27) and [libundirect_dsc_rebind](libundirect.h#L30) are available for this.

Example (Rebinds the direct method `-(void)handleSourceMessage:(id)arg1 replyHandler:(id)arg2;` of the `CFPrefsDaemon` class):
`libundirect_dsc_rebind(@"CoreFoundation", NSClassFromString(@"CFPrefsDaemon"), @selector(handleSourceMessage:replyHandler:), "v@:@@");`

## Hooking direct methods

After rebinding your method using libundirect_rebind, you now need to reroute all calls to MSHookMessageEx to libundirect_MSHookMessasgeEx, the easiest way to do it is by adding `#import <libundirect_hookoverwrite.h>` at the top of the file that has the hooks. libundirect_MSHookMessageEx detects whether the selector it is called with is a rebinded direct method and in that case it uses MSHookFunction instead, because direct methods are functions after being compiled and not methods.

If you don't need to use libundirect_rebind for backwards compatibility purposes, you can also directly call MSHookFunction yourself with the pointer returned by libundirect_find.

## Reimplementing Methods
If you only need to call a method and not hook it, it might be possible to just reimplement a method. libundirect offers two macros to reimplement [getters](libundirect.h#L37) and [setters](libundirect.h#L38).

## Usage Example
Check out the [Undirector.xmi file](https://github.com/opa334/SafariPlus/blob/master/MobileSafari/Undirector.xmi) of Safari Plus. (Note that it gets the libundirect functions at runtime so that devices below iOS 14 do not need to have it installed. This assumption is only correct for system applications. If an AppStore application uses objc_direct, it will be used on all iOS versions supported by the application.)