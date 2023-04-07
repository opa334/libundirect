#import <Foundation/Foundation.h>
#include <dlfcn.h>
#import "rootless.h"
#include <substrate.h>
#import "HookCompat.h"

int (*__LHHookFunctions)(const struct LHFunctionHook *hooks, int count);

int HCHookFunctions(const struct LHFunctionHook *hooks, int count)
{
	static dispatch_once_t onceToken;
	dispatch_once (&onceToken, ^{
		const char* lhPath = ROOT_PATH("/usr/lib/libhooker.dylib");
		if(access(lhPath, F_OK) == 0)
		{
			void* lhImage = dlopen(lhPath, RTLD_NOW);
			if(lhImage)
			{
				// this is unsupported according to coolstar but it works
				__LHHookFunctions = (void*)dlsym(lhImage, "LHHookFunctions");
			}
		}
	});

	// if libhooker is available, use it
	if(__LHHookFunctions)
	{
		return __LHHookFunctions(hooks, count);
	}
	// otherwise, fall back to substrate
	else
	{
		for(int i = 0; i < count; i++)
		{
			struct LHFunctionHook hook = hooks[i];
			MSHookFunction(hook.function, hook.replacement, hook.oldptr);
		}
		return 0;
	}
}