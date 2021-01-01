# libundirect (Documentation incomplete)

objc_direct is a feature introduced with Xcode 12 that, when specified, turns an Objective C method into an unexported C function after compilation.

This makes it completely impossible to call the method from inside a dylib thats injected into the process, as it is also impossible to know the method name unless you have an earlier version of the binary, in which the method you're looking for was compiled without objc_direct, at hand.

Apple has started using objc_direct in system applications, daemons and frameworks starting in iOS 14.0. Some examples for affected binaries: MobileSafari, SafariServices.framework, CoreFoundation.framework...

Before you can utilize libundirect, you will have to find the unexported function you're looking for via reverse engineering, this process won't be covered here. I have personally had success by searching for xrefs in an earlier binary without objc_direct, finding the methods that call your method in the new binary, hoping they are not also affected by objc_direct and finding the call to your method which will be a call to a sub_* C function now.



## Patchfinder

For the patchfinding process, it is important that you know the address of the unexported C function for at least one binary that you have, and you have at least one other version of the binary where you don't know the address. This is important so you can make sure that the bytes stay the same accross different versions (as references to pointers usually change whenever the source code changes).

Now open the binary that you know the address of in a hex editor, jump to the address and start searching for unique bytes within the function. (E.g. copy a few bytes, search the binary for them, repeat until you only have one exact match inside your function for the whole binary). Once you have the bytes that may be unique, as mentioned earlier, now search for them in a different version of the binary and make sure you also only got one exact match. If you don't get a match in the other version, your bytes probably contain a sequence that changes between versions and you have to try out different bytes.

Once you have a unique byte sequence that stays the same between versions, the function libundirect_find can be used to locate your function. The start byte of the function also has to be supplied.



## Rebinding methods

To provide backwards compatibility with older binaries, you can just readd the direct methods to the class

## Hooking direct methods

After rebinding your method using libundirect_rebind, you now set theos to use libundirect_MSHookMessageEx instead of the regular MSHookMessageEx. libundirect_MSHookMessageEx detects whether the selector it is called with is a rebinded direct method and in that case it uses MSHookFunction instead, because direct methods are functions after being compiled and not methods.

If you don't need to use libundirect_rebind for backwards compatibility purposes, you can also directly call MSHookFunction yourself with the pointer returned by libundirect_find.