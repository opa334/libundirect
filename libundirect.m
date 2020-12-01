#import "libundirect.h"
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach/mach.h>

#define libundirect_EXPORT __attribute__((visibility ("default")))

NSString* _libundirect_getSelectorString(BOOL classMethod, NSString* className, SEL selector)
{
    NSString* prefix;

    if(classMethod)
    {
        prefix = @"+";
    }
    else
    {
        prefix = @"-";
    }

    return [NSString stringWithFormat:@"%@[%@ %@]", prefix, className, NSStringFromSelector(selector)];
}

//only on ios

#import "substrate.h"

NSMutableDictionary* undirectedSelectorsAndValues;
NSMutableArray* failedSelectors;

libundirect_EXPORT void libundirect_MSHookMessageEx(Class _class, SEL message, IMP hook, IMP *old)
{
    if(undirectedSelectorsAndValues)
    {
        if(message)
        {
            NSString* selectorString = _libundirect_getSelectorString(class_isMetaClass(_class), NSStringFromClass(_class), message);

            NSValue* symbol = [undirectedSelectorsAndValues objectForKey:selectorString];
            if(symbol)
            {
                NSLog(@"[libundirect_MSHookMessageEx] received hook for %@ which is a direct method, redirecting to MSHookFunction...", selectorString);
                void* symbolPtr = [symbol pointerValue];
                MSHookFunction(symbolPtr, (void*)hook, (void**)old);

                return;
            }
        }
    }

    MSHookMessageEx(_class, message, hook, old);
}

//only on ios end

#ifdef __LP64__

void _libundirect_addToFailedSelectors(NSString* selectorString)
{
    static dispatch_once_t onceToken;
    dispatch_once (&onceToken, ^{
        failedSelectors = [NSMutableArray new];
    });

    [failedSelectors addObject:selectorString];
}

libundirect_EXPORT void libundirect_rebind(BOOL classMethod, void* directPtr, NSString* className, SEL selector, const char* format)
{
    NSString* selectorString = _libundirect_getSelectorString(classMethod, className, selector);

    NSLog(@"[libundirect_rebind] about to apply %@ with %s to %p", selectorString, format, directPtr);

    static dispatch_once_t onceToken;
    dispatch_once (&onceToken, ^{
        undirectedSelectorsAndValues = [NSMutableDictionary new];
    });

    // check whether the direct pointer is actually a valid function pointer
    Dl_info info;
    int rc = dladdr(directPtr, &info);

    if(rc == 0)
    {
        NSLog(@"[libundirect_rebind] failed, not a valid function pointer");
        _libundirect_addToFailedSelectors(selectorString);
        return;
    }

    Class classToUse = NSClassFromString(className);

    if(!classToUse)
    {
        NSLog(@"[libundirect_rebind] failed, class %@ not found", className);
        _libundirect_addToFailedSelectors(selectorString);
        return;
    }

    // use metaclass if class method and check whether method already exists
    if(classMethod)
    {
        classToUse = object_getClass(classToUse);
        if([classToUse respondsToSelector:selector])
        {
            NSLog(@"[libundirect_rebind] failed, method already exists, likely already undirected");
            return;
        }
    }
    else
    {
        if([classToUse instancesRespondToSelector:selector])
        {
            NSLog(@"[libundirect_rebind] failed, method already exists, likely already undirected");
            return;
        }
    }

    class_addMethod(
        classToUse, 
        selector,
        (IMP)directPtr, 
        format
    );

    NSValue* ptrValue = [NSValue valueWithPointer:directPtr];
    [undirectedSelectorsAndValues setObject:ptrValue forKey:selectorString];

    NSLog(@"[libundirect_rebind] %@ applied", selectorString);
}

void* _libundirect_find_in_region(vm_address_t startAddr, vm_offset_t regionLength, unsigned char* bytesToSearch, size_t byteCount)
{
    if(byteCount < 1)
    {
        return NULL;
    }

    unsigned char firstByte = bytesToSearch[0];

    vm_address_t curAddr = startAddr;

    while(curAddr < startAddr + regionLength)
    {
        size_t searchSize = (startAddr - curAddr) + regionLength;
        void* foundPtr = memchr((void*)curAddr,firstByte,searchSize);

        if(foundPtr == NULL)
        {
            NSLog(@"[_libundirect_find_in_region] foundPtr == NULL return");
            break;
        }

        vm_address_t foundAddr = (vm_address_t)foundPtr;

        size_t remainingBytes = regionLength - (foundAddr - startAddr);

        if(remainingBytes >= byteCount)
        {
            int memcmpRes = memcmp(foundPtr, bytesToSearch, byteCount);

            if(memcmpRes == 0)
            {
                NSLog(@"[_libundirect_find_in_region] foundPtr = %p", foundPtr);
                return foundPtr;
            }
        }
        else
        {
            break;
        }

        curAddr = foundAddr + 1;
    }

    return NULL;
}

void* _libundirect_seek_back(vm_address_t startAddr, unsigned char toByte, unsigned int maxSearch)
{
    vm_address_t curAddr = startAddr;

    while((startAddr - curAddr) < maxSearch)
    {
        void* curPtr = (void*)curAddr;
        unsigned char curChar = *(unsigned char*)curPtr;

        if(curChar == toByte)
        {
            return curPtr;
        }

        curAddr = curAddr - 1;
    }

    return NULL;
}

libundirect_EXPORT void* libundirect_find(NSString* imageName, unsigned char* bytesToSearch, size_t byteCount, unsigned char startByte)
{
    intptr_t baseAddr;
    struct mach_header_64* header;
    for (uint32_t i = 0; i < _dyld_image_count(); i++)
    {
        const char *name = _dyld_get_image_name(i);
        NSString *path = [NSString stringWithFormat:@"%s", name];
        if([path containsString:imageName])
        {
            baseAddr = _dyld_get_image_vmaddr_slide(i);
            header = (struct mach_header_64*)_dyld_get_image_header(i);
        }
    }

    const struct segment_command_64* cmd;

    uintptr_t addr = (uintptr_t)(header + 1);
    uintptr_t endAddr = addr + header->sizeofcmds;

    for(int ci = 0; ci < header->ncmds && addr <= endAddr; ci++)
	{
		cmd = (typeof(cmd))addr;

		addr = addr + cmd->cmdsize;

		if(cmd->cmd != LC_SEGMENT_64 || strcmp(cmd->segname, "__TEXT"))
		{
			continue;
		}

		void* result = _libundirect_find_in_region(cmd->vmaddr + baseAddr, cmd->vmsize, bytesToSearch, byteCount);

        if(result != NULL)
        {
            if(startByte)
            {
                void* backResult = _libundirect_seek_back((vm_address_t)result, startByte, 64);
                if(backResult)
                {
                    return backResult;
                }
                else
                {
                    return result;
                }
            }
            else
            {
                return result;
            }
        }
	}

    return NULL;
}

libundirect_EXPORT NSArray* libundirect_failedSelectors()
{
    return [failedSelectors copy];
}

#else

// Non 64 bit devices are so ancient that they probably don't need to use this library

libundirect_EXPORT void libundirect_rebind(BOOL classMethod, void* directPtr, NSString* className, SEL selector, const char* format)
{

}

libundirect_EXPORT void* libundirect_find(NSString* imageName, unsigned char* bytesToSearch, size_t byteCount, unsigned char startByte)
{
    return NULL;
}

libundirect_EXPORT NSArray* libundirect_failedSelectors()
{
    return nil;
}

#endif