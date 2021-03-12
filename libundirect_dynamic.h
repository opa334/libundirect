// Copyright (c) 2020-2021 Lars Fröder

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

#import <dlfcn.h>

#ifdef __cplusplus
extern "C" {
#endif

// dynamic header for when you don't want to link against libundirect
// for documentation, check out the non-dynamic header

__attribute__((unused))
static void libundirect_MSHookMessageEx(Class _class, SEL message, IMP hook, IMP *old)
{
	static void (*impl_libundirect_MSHookMessageEx)(Class, SEL, IMP, IMP *);
	if(!impl_libundirect_MSHookMessageEx)
	{
		void* handle = dlopen("/usr/lib/libundirect.dylib", RTLD_LAZY);
		impl_libundirect_MSHookMessageEx = dlsym(handle, "libundirect_MSHookMessageEx");
	}
	impl_libundirect_MSHookMessageEx(_class, message, hook, old);
}

__attribute__((unused))
static void libundirect_rebind(void* directPtr, Class _class, SEL selector, const char* format)
{
	static void (*impl_libundirect_rebind)(void*, Class, SEL, const char*);
	if(!impl_libundirect_rebind)
	{
		void* handle = dlopen("/usr/lib/libundirect.dylib", RTLD_LAZY);
		impl_libundirect_rebind = dlsym(handle, "libundirect_rebind");
	}
	impl_libundirect_rebind(directPtr, _class, selector, format);
}

__attribute__((unused))
static void* libundirect_find(NSString* imageName, unsigned char* bytesToSearch, size_t byteCount, unsigned char startByte)
{
	static void* (*impl_libundirect_find)(NSString*, unsigned char*, size_t, unsigned char);
	if(!impl_libundirect_find)
	{
		void* handle = dlopen("/usr/lib/libundirect.dylib", RTLD_LAZY);
		impl_libundirect_find = dlsym(handle, "libundirect_find");
	}
	return impl_libundirect_find(imageName, bytesToSearch, byteCount, startByte);
}

__attribute__((unused))
static void* libundirect_dsc_find(NSString* imageName, Class _class, SEL selector)
{
	static void* (*impl_libundirect_dsc_find)(NSString*, Class, SEL);
	if(!impl_libundirect_dsc_find)
	{
		void* handle = dlopen("/usr/lib/libundirect.dylib", RTLD_LAZY);
		impl_libundirect_dsc_find = dlsym(handle, "libundirect_dsc_find");
	}
	return impl_libundirect_dsc_find(imageName, _class, selector);
}

__attribute__((unused))
static void libundirect_dsc_rebind(NSString* imageName, Class _class, SEL selector, const char* format)
{
	static void (*impl_libundirect_dsc_rebind)(NSString*, Class, SEL, const char*);
	if(!impl_libundirect_dsc_rebind)
	{
		void* handle = dlopen("/usr/lib/libundirect.dylib", RTLD_LAZY);
		impl_libundirect_dsc_rebind = dlsym(handle, "libundirect_dsc_rebind");
	}
	return impl_libundirect_dsc_rebind(imageName, _class, selector, format);
}

__attribute__((unused))
static NSArray* libundirect_failedSelectors()
{
	static NSArray* (*impl_libundirect_failedSelectors)();
	if(!impl_libundirect_failedSelectors)
	{
		void* handle = dlopen("/usr/lib/libundirect.dylib", RTLD_LAZY);
		impl_libundirect_failedSelectors = dlsym(handle, "libundirect_failedSelectors");
	}
	return impl_libundirect_failedSelectors();
}

#ifdef __cplusplus
}
#endif

// macros to readd setters and getters for ivars, these can't be hooked as the application still calls the original direct getters and setters
// mainly useful to get existing code to just work without having to change everything to use the ivar instead
// can only be used from xmi files
#define LIBUNDIRECT_CLASS_ADD_GETTER(classname, type, ivarname, gettername) %hook classname %new - (type)gettername { return [self valueForKey:[NSString stringWithUTF8String:#ivarname]]; } %end
#define LIBUNDIRECT_CLASS_ADD_SETTER(classname, type, ivarname, settername) %hook classname %new - (void)settername:(type)toset { [self setValue:toset forKey:[NSString stringWithUTF8String:#ivarname]]; } %end