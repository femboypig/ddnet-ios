#include "ios_main.h"

#include <base/dbg.h>
#include <base/fs.h>
#include <base/log.h>

// Keep our own main, SDL_main.h would rename it to SDL_main otherwise.
#define SDL_MAIN_HANDLED
#include <SDL.h>
#include <SDL_syswm.h>

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <execinfo.h>
#import <fcntl.h>

#include <cmath>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <unistd.h>
#include <sys/ucontext.h>

extern "C" const char *__crashreporter_info__ __attribute__((weak));
extern "C" int SDL_UIKitRunApp(int argc, char **argv, int (*mainFunction)(int, char **));
extern "C" int SDL_main(int argc, char **argv);

@interface DDNetRootViewController : UIViewController
@end

@implementation DDNetRootViewController
- (void)loadView
{
	CGRect bounds = [UIScreen mainScreen].bounds;
	self.view = [[UIView alloc] initWithFrame:bounds];
	self.view.backgroundColor = [UIColor blackColor];
}
- (BOOL)shouldAutorotate
{
	return YES;
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
	return UIInterfaceOrientationMaskAllButUpsideDown;
}
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation
{
	return UIInterfaceOrientationLandscapeRight;
}
- (BOOL)prefersStatusBarHidden
{
	return YES;
}
- (BOOL)prefersHomeIndicatorAutoHidden
{
	return YES;
}
@end

@interface SDLUIKitDelegate : NSObject <UIApplicationDelegate>
+ (id)sharedAppDelegate;
+ (NSString *)getAppDelegateClassName;
- (void)hideLaunchScreen;
- (void)postFinishLaunch;
- (void)sendDropFileForURL:(NSURL *)url;
@property (nonatomic) UIWindow *window;
@end

@interface DDNetSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

static UIWindowScene *s_pActiveWindowScene = nil;
static DDNetSceneDelegate *s_pActiveSceneDelegate = nil;
static UIWindow *s_pEarlyWindow = nil;

@implementation DDNetSceneDelegate
@synthesize window = _window;

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions
{
	if(![scene isKindOfClass:[UIWindowScene class]])
	{
		return;
	}

	UIWindowScene *windowScene = (UIWindowScene *)scene;
	s_pActiveWindowScene = windowScene;
	s_pActiveSceneDelegate = self;
	printf("[DDNet] scene:willConnectToSession with UIWindowScene %p\n", windowScene);
	fflush(stdout);

	CGRect bounds = windowScene.coordinateSpace.bounds;
	if(bounds.size.width <= 0 || bounds.size.height <= 0)
	{
		bounds = [UIScreen mainScreen].bounds;
	}
	if(bounds.size.width <= 0 || bounds.size.height <= 0)
	{
		bounds = CGRectMake(0, 0, 844, 390);
	}

	_window = [[UIWindow alloc] initWithWindowScene:windowScene];
	_window.frame = bounds;
	_window.backgroundColor = [UIColor blackColor];
	_window.rootViewController = [[DDNetRootViewController alloc] init];
	[_window makeKeyAndVisible];
	s_pEarlyWindow = _window;

	id appDel = [UIApplication sharedApplication].delegate;
	if([appDel respondsToSelector:@selector(setWindow:)])
	{
		[appDel setWindow:_window];
	}

	printf("[DDNet] Connected early window %p (%dx%d) to UIWindowScene %p\n",
		_window, (int)bounds.size.width, (int)bounds.size.height, windowScene);
	fflush(stdout);
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts
{
	for(UIOpenURLContext *context in URLContexts)
	{
		NSURL *url = context.URL;
		if(url)
		{
			printf("[DDNet] Scene openURLContext: %s\n", url.absoluteString.UTF8String);
			fflush(stdout);
			id delegate = [UIApplication sharedApplication].delegate;
			if([delegate respondsToSelector:@selector(sendDropFileForURL:)])
			{
				[delegate performSelector:@selector(sendDropFileForURL:) withObject:url];
			}
		}
	}
}

- (void)sceneDidDisconnect:(UIScene *)scene
{
	if(s_pActiveWindowScene == scene)
	{
		s_pActiveWindowScene = nil;
		s_pActiveSceneDelegate = nil;
	}
}
@end

@interface DDNetAppDelegate : SDLUIKitDelegate <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation DDNetAppDelegate
@synthesize window = _window;

- (instancetype)init
{
	if((self = [super init]))
	{
		printf("[DDNet] DDNetAppDelegate initialized\n");
		fflush(stdout);
	}
	return self;
}

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options
{
	printf("[DDNet] application:configurationForConnectingSceneSession: role=%s\n", connectingSceneSession.role.UTF8String);
	fflush(stdout);
	UISceneConfiguration *config = [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
	config.delegateClass = [DDNetSceneDelegate class];
	return config;
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions
{
	if(![scene isKindOfClass:[UIWindowScene class]])
	{
		return;
	}

	UIWindowScene *windowScene = (UIWindowScene *)scene;
	s_pActiveWindowScene = windowScene;
	printf("[DDNet] DDNetAppDelegate scene:willConnectToSession with UIWindowScene %p\n", windowScene);
	fflush(stdout);

	if(self.window != nil)
	{
		self.window.windowScene = windowScene;
		[self.window makeKeyAndVisible];
	}
	else
	{
		CGRect bounds = windowScene.coordinateSpace.bounds;
		if(bounds.size.width <= 0 || bounds.size.height <= 0)
		{
			bounds = [UIScreen mainScreen].bounds;
		}
		self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
		self.window.frame = bounds;
		self.window.backgroundColor = [UIColor blackColor];
		self.window.rootViewController = [[DDNetRootViewController alloc] init];
		[self.window makeKeyAndVisible];
		s_pEarlyWindow = self.window;
	}
	fflush(stdout);
}

- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window
{
	return UIInterfaceOrientationMaskAllButUpsideDown;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
	printf("[DDNet] DDNetAppDelegate didFinishLaunchingWithOptions\n");
	fflush(stdout);

	if(self.window == nil)
	{
		CGRect bounds = [UIScreen mainScreen].bounds;
		if(bounds.size.width <= 0 || bounds.size.height <= 0)
		{
			bounds = CGRectMake(0, 0, 844, 390);
		}
		self.window = [[UIWindow alloc] initWithFrame:bounds];
		self.window.backgroundColor = [UIColor blackColor];
		self.window.rootViewController = [[DDNetRootViewController alloc] init];
		[self.window makeKeyAndVisible];
		s_pEarlyWindow = self.window;
	}

	NSBundle *bundle = [NSBundle mainBundle];
	[[NSFileManager defaultManager] changeCurrentDirectoryPath:[bundle resourcePath]];

	SDL_SetMainReady();
	[self performSelector:@selector(postFinishLaunch) withObject:nil afterDelay:0.0];
	return YES;
}
@end

@interface SDLUIKitDelegate (DDNetSubclass)
@end

@implementation SDLUIKitDelegate (DDNetSubclass)
+ (NSString *)getAppDelegateClassName
{
	return @"DDNetAppDelegate";
}
@end

static void (*s_pOrigMakeKeyAndVisible)(id, SEL) = NULL;
static void (*s_pOrigSetHidden)(id, SEL, BOOL) = NULL;

static void DDNet_UIWindow_attachSceneIfNeeded(UIWindow *w)
{
	if(@available(iOS 13.0, *))
	{
		if(w.windowScene == nil)
		{
			if(s_pActiveWindowScene != nil)
			{
				w.windowScene = s_pActiveWindowScene;
				printf("[DDNet] Connected UIWindow %p to stored UIWindowScene %p\n", w, s_pActiveWindowScene);
			}
			else
			{
				for(UIScene *scene in [UIApplication sharedApplication].connectedScenes)
				{
					if([scene isKindOfClass:[UIWindowScene class]])
					{
						w.windowScene = (UIWindowScene *)scene;
						printf("[DDNet] Connected UIWindow %p to UIWindowScene %p\n", w, scene);
						break;
					}
				}
			}
		}
	}
}

static void DDNet_UIWindow_makeKeyAndVisible(id self, SEL _cmd)
{
	UIWindow *w = (UIWindow *)self;
	DDNet_UIWindow_attachSceneIfNeeded(w);

	if(s_pOrigMakeKeyAndVisible)
	{
		s_pOrigMakeKeyAndVisible(self, _cmd);
	}

	if(s_pEarlyWindow != nil && w != s_pEarlyWindow)
	{
		printf("[DDNet] Transitioned from early splash window %p to game window %p\n", s_pEarlyWindow, w);
		UIWindow *splash = s_pEarlyWindow;
		s_pEarlyWindow = nil;
		splash.hidden = YES;
		splash.rootViewController = nil;
	}

	DDNetAppDelegate *appDelegate = (DDNetAppDelegate *)[UIApplication sharedApplication].delegate;
	if([appDelegate isKindOfClass:[DDNetAppDelegate class]])
	{
		appDelegate.window = w;
	}
	if(s_pActiveSceneDelegate != nil)
	{
		s_pActiveSceneDelegate.window = w;
	}
	fflush(stdout);
}

static void DDNet_UIWindow_setHidden(id self, SEL _cmd, BOOL hidden)
{
	UIWindow *w = (UIWindow *)self;
	if(!hidden)
	{
		DDNet_UIWindow_attachSceneIfNeeded(w);
	}

	if(s_pOrigSetHidden)
	{
		s_pOrigSetHidden(self, _cmd, hidden);
	}
}

static void DDNet_SDLLaunchScreenController_loadView(id self, SEL _cmd)
{
	UIViewController *vc = (UIViewController *)self;
	CGRect bounds = [UIScreen mainScreen].bounds;
	vc.view = [[UIView alloc] initWithFrame:bounds];
	vc.view.backgroundColor = [UIColor blackColor];
}

static void PatchSDLLaunchScreenController()
{
	Class cls = NSClassFromString(@"SDLLaunchScreenController");
	if(cls)
	{
		Method m = class_getInstanceMethod(cls, @selector(loadView));
		if(m)
		{
			method_setImplementation(m, (IMP)DDNet_SDLLaunchScreenController_loadView);
		}
		else
		{
			class_addMethod(cls, @selector(loadView), (IMP)DDNet_SDLLaunchScreenController_loadView, "v@:");
		}
		printf("[DDNet] Patched SDLLaunchScreenController loadView\n");
		fflush(stdout);
	}
}

static void PatchUIWindow()
{
	Class cls = NSClassFromString(@"UIWindow");
	if(!cls)
	{
		return;
	}
	Method origMakeKey = class_getInstanceMethod(cls, @selector(makeKeyAndVisible));
	if(origMakeKey)
	{
		s_pOrigMakeKeyAndVisible = (void (*)(id, SEL))method_getImplementation(origMakeKey);
		method_setImplementation(origMakeKey, (IMP)DDNet_UIWindow_makeKeyAndVisible);
		printf("[DDNet] Patched UIWindow makeKeyAndVisible\n");
		fflush(stdout);
	}
	Method origSetHidden = class_getInstanceMethod(cls, @selector(setHidden:));
	if(origSetHidden)
	{
		s_pOrigSetHidden = (void (*)(id, SEL, BOOL))method_getImplementation(origSetHidden);
		method_setImplementation(origSetHidden, (IMP)DDNet_UIWindow_setHidden);
		printf("[DDNet] Patched UIWindow setHidden:\n");
		fflush(stdout);
	}
}

@interface DDNetAssertionHandler : NSAssertionHandler
@end

@implementation DDNetAssertionHandler
- (void)handleFailureInMethod:(SEL)selector object:(id)object file:(NSString *)fileName lineNumber:(NSInteger)line description:(NSString *)format, ...
{
	va_list args;
	va_start(args, format);
	NSString *desc = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);

	NSString *report = [NSString stringWithFormat:@"\n=== DDNet ASSERTION FAILURE ===\nMethod -[%s %s] (%@:%ld)\nReason: %@\n\n",
		object ? object_getClassName(object) : "nil",
		selector ? sel_getName(selector) : "nil",
		fileName ? fileName : @"unknown",
		(long)line,
		desc ? desc : @"none"];

	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	if(paths.count > 0)
	{
		NSString *crashPath = [paths[0] stringByAppendingPathComponent:@"crash.log"];
		FILE *f = fopen([crashPath UTF8String], "a");
		if(f)
		{
			fputs([report UTF8String], f);
			fflush(f);
			fclose(f);
		}
	}
	fprintf(stderr, "%s", [report UTF8String]);
	printf("%s", [report UTF8String]);
	fflush(stdout);
	fflush(stderr);
}

- (void)handleFailureInFunction:(NSString *)functionName file:(NSString *)fileName lineNumber:(NSInteger)line description:(NSString *)format, ...
{
	va_list args;
	va_start(args, format);
	NSString *desc = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);

	NSString *report = [NSString stringWithFormat:@"\n=== DDNet ASSERTION FAILURE ===\nFunction %s (%@:%ld)\nReason: %@\n\n",
		functionName ? functionName.UTF8String : "unknown",
		fileName ? fileName : @"unknown",
		(long)line,
		desc ? desc : @"none"];

	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	if(paths.count > 0)
	{
		NSString *crashPath = [paths[0] stringByAppendingPathComponent:@"crash.log"];
		FILE *f = fopen([crashPath UTF8String], "a");
		if(f)
		{
			fputs([report UTF8String], f);
			fflush(f);
			fclose(f);
		}
	}
	fprintf(stderr, "%s", [report UTF8String]);
	printf("%s", [report UTF8String]);
	fflush(stdout);
	fflush(stderr);
}
@end

static bool IsMemoryReadable(const void *ptr, size_t size)
{
	if(!ptr || (uintptr_t)ptr < 0x1000)
	{
		return false;
	}
	static int s_DevNull = -1;
	if(s_DevNull < 0)
	{
		s_DevNull = open("/dev/null", O_WRONLY);
	}
	if(s_DevNull >= 0)
	{
		return write(s_DevNull, ptr, size) >= 0;
	}
	return false;
}

static void DumpPointerInfo(NSMutableString *report, const char *label, uintptr_t val)
{
	if(!val || val < 0x1000)
	{
		return;
	}
	const void *ptr = (const void *)val;
	if(!IsMemoryReadable(ptr, 1))
	{
		return;
	}

	Dl_info dlinfo;
	if(dladdr(ptr, &dlinfo) && dlinfo.dli_sname)
	{
		[report appendFormat:@"  %s symbol: %s + 0x%lx (%s)\n",
			label, dlinfo.dli_sname, (uintptr_t)ptr - (uintptr_t)dlinfo.dli_saddr,
			dlinfo.dli_fname ? dlinfo.dli_fname : "unknown"];
	}

	@try
	{
		id obj = (__bridge id)ptr;
		Class cls = object_getClass(obj);
		if(cls)
		{
			const char *clsName = class_getName(cls);
			if(clsName && clsName[0] != '\0')
			{
				NSString *desc = [obj description];
				if(desc)
				{
					[report appendFormat:@"  %s (ObjC %s): %@\n", label, clsName, desc];
				}
			}
		}
	}
	@catch(NSException *) {}

	char buf[256];
	size_t len = 0;
	for(; len < sizeof(buf) - 1; len++)
	{
		if(!IsMemoryReadable((const char *)ptr + len, 1))
		{
			break;
		}
		char c = ((const char *)ptr)[len];
		if(c == '\0')
		{
			break;
		}
		if((unsigned char)c < 32 && c != '\n' && c != '\r' && c != '\t')
		{
			len = 0;
			break;
		}
		buf[len] = c;
	}
	buf[len] = '\0';
	if(len >= 3)
	{
		[report appendFormat:@"  %s (string): \"%s\"\n", label, buf];
	}
}

static void IosUncaughtExceptionHandler(NSException *exception)
{
	if(!exception)
	{
		return;
	}

	NSString *report = [NSString stringWithFormat:@"\n=== DDNet Uncaught Objective-C Exception ===\nName: %@\nReason: %@\nCall Stack:\n%@\n",
		[exception name], [exception reason], [[exception callStackSymbols] componentsJoinedByString:@"\n"]];

	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	if(paths.count > 0)
	{
		NSString *crashPath = [paths[0] stringByAppendingPathComponent:@"crash.log"];
		FILE *f = fopen([crashPath UTF8String], "a");
		if(f)
		{
			fputs([report UTF8String], f);
			fflush(f);
			fclose(f);
		}
	}
	fprintf(stderr, "%s", [report UTF8String]);
	fflush(stderr);
}

static void IosSignalHandler(int sig, siginfo_t *info, void *context)
{
	NSMutableString *report = [NSMutableString string];
	[report appendFormat:@"\n=== DDNet Fatal Signal %d (%s) ===\n", sig, strsignal(sig)];
	if(info && info->si_addr)
	{
		[report appendFormat:@"Fault address: %p\n", info->si_addr];
		Dl_info faultInfo;
		if(dladdr(info->si_addr, &faultInfo) && faultInfo.dli_sname)
		{
			[report appendFormat:@"Fault symbol: %s + 0x%lx (%s)\n",
				faultInfo.dli_sname,
				(uintptr_t)info->si_addr - (uintptr_t)faultInfo.dli_saddr,
				faultInfo.dli_fname ? faultInfo.dli_fname : "unknown"];
		}
	}
	if(__crashreporter_info__ && *__crashreporter_info__)
	{
		[report appendFormat:@"Crash Reporter Info: %s\n", __crashreporter_info__];
	}

#if defined(__arm64__) || defined(__aarch64__)
	if(context)
	{
		ucontext_t *uc = (ucontext_t *)context;
		if(uc && uc->uc_mcontext)
		{
			uint64_t pc = uc->uc_mcontext->__ss.__pc;
			uint64_t lr = uc->uc_mcontext->__ss.__lr;
			uint64_t sp = uc->uc_mcontext->__ss.__sp;
			uint64_t fp = uc->uc_mcontext->__ss.__fp;

			[report appendFormat:@"PC: 0x%016llx  LR: 0x%016llx  SP: 0x%016llx  FP: 0x%016llx\n",
				(unsigned long long)pc, (unsigned long long)lr,
				(unsigned long long)sp, (unsigned long long)fp];

			for(int i = 0; i < 29; i += 2)
			{
				[report appendFormat:@"x%-2d: 0x%016llx  x%-2d: 0x%016llx\n",
					i, (unsigned long long)uc->uc_mcontext->__ss.__x[i],
					i + 1, (i + 1 < 29) ? (unsigned long long)uc->uc_mcontext->__ss.__x[i + 1] : 0ULL];
			}

			[report appendString:@"Register Details:\n"];
			DumpPointerInfo(report, "PC", (uintptr_t)pc);
			DumpPointerInfo(report, "LR", (uintptr_t)lr);
			DumpPointerInfo(report, "x0", (uintptr_t)uc->uc_mcontext->__ss.__x[0]);
			DumpPointerInfo(report, "x1", (uintptr_t)uc->uc_mcontext->__ss.__x[1]);
			DumpPointerInfo(report, "x19", (uintptr_t)uc->uc_mcontext->__ss.__x[19]);
			DumpPointerInfo(report, "x20", (uintptr_t)uc->uc_mcontext->__ss.__x[20]);
			DumpPointerInfo(report, "x21", (uintptr_t)uc->uc_mcontext->__ss.__x[21]);
			DumpPointerInfo(report, "x22", (uintptr_t)uc->uc_mcontext->__ss.__x[22]);
			DumpPointerInfo(report, "x23", (uintptr_t)uc->uc_mcontext->__ss.__x[23]);
			DumpPointerInfo(report, "x24", (uintptr_t)uc->uc_mcontext->__ss.__x[24]);
			DumpPointerInfo(report, "x25", (uintptr_t)uc->uc_mcontext->__ss.__x[25]);
		}
	}
#endif

	[report appendString:@"Call Stack:\n"];
	void *callstack[128];
	int frames = backtrace(callstack, 128);
	char **strs = backtrace_symbols(callstack, frames);
	for(int i = 0; i < frames; i++)
	{
		Dl_info dlinfo;
		if(dladdr(callstack[i], &dlinfo) && dlinfo.dli_sname)
		{
			const char *fname = dlinfo.dli_fname ? strrchr(dlinfo.dli_fname, '/') ? strrchr(dlinfo.dli_fname, '/') + 1 : dlinfo.dli_fname : "???";
			[report appendFormat:@"%-2d  %-30s 0x%016lx %s + %lu\n",
				i, fname, (uintptr_t)callstack[i], dlinfo.dli_sname,
				(uintptr_t)callstack[i] - (uintptr_t)dlinfo.dli_saddr];
		}
		else if(strs && strs[i])
		{
			[report appendFormat:@"%s\n", strs[i]];
		}
		else
		{
			[report appendFormat:@"%-2d  0x%016lx\n", i, (uintptr_t)callstack[i]];
		}
	}
	if(strs)
	{
		free(strs);
	}

	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	if(paths.count > 0)
	{
		NSString *crashPath = [paths[0] stringByAppendingPathComponent:@"crash.log"];
		FILE *f = fopen([crashPath UTF8String], "a");
		if(f)
		{
			fputs([report UTF8String], f);
			fflush(f);
			fclose(f);
		}
	}
	fprintf(stderr, "%s", [report UTF8String]);
	fflush(stderr);

	signal(sig, SIG_DFL);
	raise(sig);
}

static void InstallCrashHandlers()
{
	static bool s_Installed = false;
	if(s_Installed)
	{
		return;
	}
	s_Installed = true;

	NSSetUncaughtExceptionHandler(&IosUncaughtExceptionHandler);

	[[[NSThread currentThread] threadDictionary] setObject:[[DDNetAssertionHandler alloc] init] forKey:NSAssertionHandlerKey];

	struct sigaction sa;
	memset(&sa, 0, sizeof(sa));
	sa.sa_sigaction = IosSignalHandler;
	sa.sa_flags = SA_SIGINFO;
	sigemptyset(&sa.sa_mask);

	sigaction(SIGSEGV, &sa, NULL);
	sigaction(SIGABRT, &sa, NULL);
	sigaction(SIGBUS, &sa, NULL);
	sigaction(SIGILL, &sa, NULL);
	sigaction(SIGFPE, &sa, NULL);
	sigaction(SIGTRAP, &sa, NULL);
}

static void RedirectStdioToLog()
{
	static bool s_Redirected = false;
	if(s_Redirected)
	{
		return;
	}
	s_Redirected = true;

	@autoreleasepool
	{
		NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
		if(paths.count == 0)
		{
			return;
		}

		NSString *documentsDir = paths[0];
		[[NSFileManager defaultManager] createDirectoryAtPath:documentsDir withIntermediateDirectories:YES attributes:nil error:nil];

		NSString *logPath = [documentsDir stringByAppendingPathComponent:@"boot.log"];
		const char *cLogPath = [logPath UTF8String];

		NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:logPath error:nil];
		if(attrs && [attrs fileSize] > 2 * 1024 * 1024)
		{
			unlink(cLogPath);
		}

		FILE *fOut = freopen(cLogPath, "a", stdout);
		FILE *fErr = freopen(cLogPath, "a", stderr);
		if(fOut)
		{
			setvbuf(stdout, NULL, _IONBF, 0);
		}
		if(fErr)
		{
			setvbuf(stderr, NULL, _IONBF, 0);
		}

		printf("\n=== DDNet iOS Launch: %s ===\n", [[NSDate date] description].UTF8String);
		fflush(stdout);
	}
}

int main(int argc, char **argv)
{
	@autoreleasepool
	{
		RedirectStdioToLog();
		InstallCrashHandlers();
		PatchSDLLaunchScreenController();
		PatchUIWindow();
	}
	return SDL_UIKitRunApp(argc, argv, SDL_main);
}

void IosDisplayCutoutInsets(SDL_Window *pWindow, int *pLeft, int *pRight)
{
	*pLeft = 0;
	*pRight = 0;

	if(!pWindow)
	{
		return;
	}

	void (^queryInsetsBlock)(void) = ^{
		@try
		{
			SDL_SysWMinfo Info;
			SDL_VERSION(&Info.version);
			if(SDL_GetWindowWMInfo(pWindow, &Info) != SDL_TRUE)
			{
				return;
			}

			UIWindow *pUiWindow = Info.info.uikit.window;
			if(!pUiWindow)
			{
				DDNetAppDelegate *delegate = (DDNetAppDelegate *)[UIApplication sharedApplication].delegate;
				if([delegate isKindOfClass:[DDNetAppDelegate class]])
				{
					pUiWindow = delegate.window;
				}
			}
			if(!pUiWindow)
			{
				return;
			}

			UIViewController *pRootVc = pUiWindow.rootViewController;
			UIView *pView = pRootVc ? pRootVc.view : pUiWindow;
			if(!pView)
			{
				return;
			}

			const UIEdgeInsets Insets = pView.safeAreaInsets;
			CGFloat Scale = pView.contentScaleFactor;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
			if(Scale <= 0.0)
			{
				Scale = [UIScreen mainScreen].scale;
			}
			if(Scale <= 0.0)
			{
				Scale = 1.0;
			}

			UIInterfaceOrientation Orientation = UIInterfaceOrientationUnknown;
			if(@available(iOS 13.0, *))
			{
				UIWindowScene *pScene = pUiWindow.windowScene;
				if(pScene != nil)
				{
					Orientation = pScene.interfaceOrientation;
				}
			}

			if(Orientation == UIInterfaceOrientationUnknown)
			{
				Orientation = [UIApplication sharedApplication].statusBarOrientation;
			}
#pragma clang diagnostic pop

			if(Orientation == UIInterfaceOrientationLandscapeRight)
			{
				*pLeft = (int)std::ceil(Insets.left * Scale);
			}
			else if(Orientation == UIInterfaceOrientationLandscapeLeft)
			{
				*pRight = (int)std::ceil(Insets.right * Scale);
			}
			else
			{
				if(Insets.left > Insets.right)
				{
					*pLeft = (int)std::ceil(Insets.left * Scale);
				}
				else if(Insets.right > 0.0)
				{
					*pRight = (int)std::ceil(Insets.right * Scale);
				}
			}
		}
		@catch(NSException *exception)
		{
			NSLog(@"[DDNet] Exception in IosDisplayCutoutInsets: %@", exception);
		}
	};

	if([NSThread isMainThread])
	{
		queryInsetsBlock();
	}
	else
	{
		dispatch_sync(dispatch_get_main_queue(), queryInsetsBlock);
	}
}

const char *InitIos()
{
	RedirectStdioToLog();
	InstallCrashHandlers();

	char *pBasePath = SDL_GetBasePath();
	if(!pBasePath)
	{
		log_error("ios", "Failed to determine the app base path.");
		return "Failed to determine the app base path.";
	}
	if(fs_chdir(pBasePath) != 0)
	{
		log_error("ios", "Failed to change current directory to '%s'", pBasePath);
		SDL_free(pBasePath);
		return "Failed to change current directory to the app bundle.";
	}
	log_info("ios", "Changed current directory to '%s'", pBasePath);
	SDL_free(pBasePath);

	if(!fs_is_dir("data"))
	{
		log_error("ios", "Missing data directory in app bundle. Ensure data is packaged into the app.");
		return "Missing data directory in app bundle. Ensure data is packaged into the app.";
	}

	log_info("ios", "iOS initialization completed successfully");
	return nullptr;
}
