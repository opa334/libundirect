// Copyright (c) 2020-2021 Lars Fröder

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

#import "libundirect.h"
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import "pac.h"

#define libundirect_EXPORT __attribute__((visibility ("default")))

NSString* _libundirect_getSelectorString(Class _class, SEL selector)
{
    NSString* prefix;

    if(class_isMetaClass(_class))
    {
        prefix = @"+";
    }
    else
    {
        prefix = @"-";
    }

    return [NSString stringWithFormat:@"%@[%@ %@]", prefix, NSStringFromClass(_class), NSStringFromSelector(selector)];
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
            NSString* selectorString = _libundirect_getSelectorString(_class, message);

            NSValue* symbol = [undirectedSelectorsAndValues objectForKey:selectorString];
            if(symbol)
            {
                HBLogDebug(@"received hook for %@ which is a direct method, redirecting to MSHookFunction...", selectorString);
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

int _libundirect_dyldIndexForImageName(NSString* imageName)
{
    for (uint32_t i = 0; i < _dyld_image_count(); i++)
    {
        const char *pathC = _dyld_get_image_name(i);
        NSString* path = [NSString stringWithUTF8String:pathC];
        NSString* cImageName = [path lastPathComponent];

        if([cImageName isEqualToString:imageName])
        {
            return i;
        }
    }

    return -1;
}

void _libundirect_addToFailedSelectors(NSString* selectorString)
{
    static dispatch_once_t onceToken;
    dispatch_once (&onceToken, ^{
        failedSelectors = [NSMutableArray new];
    });

    [failedSelectors addObject:selectorString];
}

libundirect_EXPORT void libundirect_rebind(void* directPtr, Class _class, SEL selector, const char* format)
{
    NSString* selectorString = _libundirect_getSelectorString(_class, selector);

    HBLogDebug(@"about to apply %@ with %s to %p", selectorString, format, directPtr);

    static dispatch_once_t onceToken;
    dispatch_once (&onceToken, ^{
        undirectedSelectorsAndValues = [NSMutableDictionary new];
    });

    // check whether the direct pointer is actually a valid function pointer
    Dl_info info;
    int rc = dladdr(directPtr, &info);

    if(rc == 0)
    {
        HBLogDebug(@"failed, not a valid function pointer");
        _libundirect_addToFailedSelectors(selectorString);
        return;
    }

    class_addMethod(
        _class, 
        selector,
        (IMP)make_sym_callable(directPtr), 
        format
    );

    NSValue* ptrValue = [NSValue valueWithPointer:directPtr];
    [undirectedSelectorsAndValues setObject:ptrValue forKey:selectorString];

    HBLogDebug(@"%@ applied", selectorString);
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
            HBLogDebug(@"foundPtr == NULL return");
            break;
        }

        vm_address_t foundAddr = (vm_address_t)foundPtr;

        size_t remainingBytes = regionLength - (foundAddr - startAddr);

        if(remainingBytes >= byteCount)
        {
            int memcmpRes = memcmp(foundPtr, bytesToSearch, byteCount);

            if(memcmpRes == 0)
            {
                HBLogDebug(@"foundPtr = %p", foundPtr);
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
    int imageIndex = _libundirect_dyldIndexForImageName(imageName);
    if(imageIndex == -1)
    {
        return NULL;
    }

    intptr_t baseAddr = _dyld_get_image_vmaddr_slide(imageIndex);
    struct mach_header_64* header = (struct mach_header_64*)_dyld_get_image_header(imageIndex);

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

libundirect_EXPORT void* libundirect_dsc_find(NSString* imageName, Class _class, SEL selector)
{
    NSString* symbol = _libundirect_getSelectorString(_class, selector);
    NSString* imagePath = nil;

    HBLogDebug(@"searching dyldSharedCache for symbol: %@", symbol);

    int imageIndex = -1;
    if(imageName)
    {
        imageIndex = _libundirect_dyldIndexForImageName(imageName);
    }

    if(imageIndex != -1)
    {
        const char *name = _dyld_get_image_name(imageIndex);
        imagePath = [NSString stringWithUTF8String:name];
    }

    MSImageRef image = NULL;
    if(imagePath)
    {
        image = MSGetImageByName(imagePath.UTF8String);
    }

    return MSFindSymbol(image, symbol.UTF8String);
}

libundirect_EXPORT void libundirect_dsc_rebind(NSString* imageName, Class _class, SEL selector, const char* format)
{
    void* ptr = libundirect_dsc_find(imageName, _class, selector);
    libundirect_rebind(ptr, _class, selector, format);
}

libundirect_EXPORT NSArray* libundirect_failedSelectors()
{
    return [failedSelectors copy];
}

#else

// Non 64 bit devices are so ancient that they probably don't need to use this library

libundirect_EXPORT void libundirect_rebind(void* directPtr, Class _class, SEL selector, const char* format)
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