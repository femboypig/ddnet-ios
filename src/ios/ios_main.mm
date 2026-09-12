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

static UIWindow *s_pEarlyWindow = nil;
static UIWindow *(*s_pOrigWindowFunc)(id, SEL) = NULL;
static void (*s_pOrigSetWindowFunc)(id, SEL, UIWindow *) = NULL;
static BOOL (*s_pOrigLaunchFunc)(id, SEL, UIApplication *, NSDictionary *) = NULL;

static UIWindow *EnsureEarlyWindow()
{
	if(s_pEarlyWindow != nil)
	{
		return s_pEarlyWindow;
	}

	CGRect bounds = [UIScreen mainScreen].bounds;
	if(bounds.size.width <= 0 || bounds.size.height <= 0)
	{
		bounds = CGRectMake(0, 0, 844, 390);
	}

	s_pEarlyWindow = [[UIWindow alloc] initWithFrame:bounds];
	s_pEarlyWindow.backgroundColor = [UIColor blackColor];

	DDNetRootViewController *rootVC = [[DDNetRootViewController alloc] init];
	s_pEarlyWindow.rootViewController = rootVC;

	if(@available(iOS 13.0, *))
	{
		for(UIScene *scene in [UIApplication sharedApplication].connectedScenes)
		{
			if([scene isKindOfClass:[UIWindowScene class]])
			{
				s_pEarlyWindow.windowScene = (UIWindowScene *)scene;
				printf("[DDNet] Connected early window to UIWindowScene %p\n", scene);
				break;
			}
		}
	}

	[s_pEarlyWindow makeKeyAndVisible];
	printf("[DDNet] Created early UIWindow (%dx%d, scene=%p)\n",
		(int)bounds.size.width, (int)bounds.size.height,
		(@available(iOS 13.0, *)) ? s_pEarlyWindow.windowScene : nil);
	fflush(stdout);

	return s_pEarlyWindow;
}

static UIWindow *DDNet_SDLUIKitDelegate_window(id self, SEL _cmd)
{
	if(s_pOrigWindowFunc)
	{
		UIWindow *w = s_pOrigWindowFunc(self, _cmd);
		if(w != nil)
		{
			if(s_pEarlyWindow != nil && s_pEarlyWindow != w)
			{
				s_pEarlyWindow.hidden = YES;
				s_pEarlyWindow = nil;
			}
			return w;
		}
	}
	return EnsureEarlyWindow();
}

static void DDNet_SDLUIKitDelegate_setWindow(id self, SEL _cmd, UIWindow *w)
{
	printf("[DDNet] SDLUIKitDelegate setWindow: %p\n", w);
	fflush(stdout);
	s_pEarlyWindow = w;
	if(s_pOrigSetWindowFunc)
	{
		s_pOrigSetWindowFunc(self, _cmd, w);
	}
}

static BOOL DDNet_SDLUIKitDelegate_didFinishLaunching(id self, SEL _cmd, UIApplication *app, NSDictionary *opts)
{
	printf("[DDNet] SDLUIKitDelegate didFinishLaunchingWithOptions\n");
	fflush(stdout);
	EnsureEarlyWindow();

	BOOL result = YES;
	if(s_pOrigLaunchFunc)
	{
		result = s_pOrigLaunchFunc(self, _cmd, app, opts);
	}
	return result;
}

static UIInterfaceOrientationMask DDNet_SDLUIKitDelegate_supportedOrientations(id self, SEL _cmd, UIApplication *app, UIWindow *window)
{
	if(window != nil && window != s_pEarlyWindow)
	{
		return UIInterfaceOrientationMaskLandscape;
	}
	return UIInterfaceOrientationMaskAllButUpsideDown;
}

static void (*s_pOrigMakeKeyAndVisible)(id, SEL) = NULL;

static void DDNet_UIWindow_makeKeyAndVisible(id self, SEL _cmd)
{
	UIWindow *w = (UIWindow *)self;
	if(@available(iOS 13.0, *))
	{
		if(w.windowScene == nil)
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

	if(s_pOrigMakeKeyAndVisible)
	{
		s_pOrigMakeKeyAndVisible(self, _cmd);
	}

	if(s_pEarlyWindow != nil && w != s_pEarlyWindow)
	{
		printf("[DDNet] Transitioned from early splash window %p to game window %p\n", s_pEarlyWindow, w);
		s_pEarlyWindow.hidden = YES;
		s_pEarlyWindow.rootViewController = nil;
		s_pEarlyWindow = nil;
	}
	fflush(stdout);
}

static void SetupSceneObserver()
{
	if(@available(iOS 13.0, *))
	{
		[[NSNotificationCenter defaultCenter] addObserverForName:UISceneWillConnectNotification
			object:nil
			queue:[NSOperationQueue mainQueue]
			usingBlock:^(NSNotification *note) {
				UIScene *scene = note.object;
				if([scene isKindOfClass:[UIWindowScene class]])
				{
					printf("[DDNet] UISceneWillConnectNotification for scene %p\n", scene);
					if(s_pEarlyWindow != nil && s_pEarlyWindow.windowScene == nil)
					{
						s_pEarlyWindow.windowScene = (UIWindowScene *)scene;
						[s_pEarlyWindow makeKeyAndVisible];
						printf("[DDNet] Attached early window to connected UIWindowScene %p\n", scene);
					}
					for(UIWindow *w in [UIApplication sharedApplication].windows)
					{
						if(w.windowScene == nil)
						{
							w.windowScene = (UIWindowScene *)scene;
							printf("[DDNet] Attached window %p to connected UIWindowScene %p\n", w, scene);
						}
					}
					fflush(stdout);
				}
			}];
	}
}

static void PatchUIWindow()
{
	Class cls = NSClassFromString(@"UIWindow");
	if(!cls)
	{
		return;
	}
	SwizzleOrAddMethod(cls, @selector(makeKeyAndVisible), (IMP)DDNet_UIWindow_makeKeyAndVisible, (IMP *)&s_pOrigMakeKeyAndVisible, "v@:");
}

static void SwizzleOrAddMethod(Class cls, SEL sel, IMP newImp, IMP *origImpOut, const char *types)
{
	Method origMethod = class_getInstanceMethod(cls, sel);
	if(origMethod)
	{
		IMP origImp = method_getImplementation(origMethod);
		if(origImpOut)
		{
			*origImpOut = origImp;
		}
		if(class_addMethod(cls, sel, newImp, method_getTypeEncoding(origMethod)))
		{
			Method subMethod = class_getInstanceMethod(cls, sel);
			if(origImpOut)
			{
				*origImpOut = origImp;
			}
		}
		else
		{
			method_setImplementation(origMethod, newImp);
		}
	}
	else
	{
		class_addMethod(cls, sel, newImp, types);
	}
}

static void PatchSDLUIKitDelegate()
{
	Class cls = NSClassFromString(@"SDLUIKitDelegate");
	if(!cls)
	{
		printf("PatchSDLUIKitDelegate: SDLUIKitDelegate class not found!\n");
		fflush(stdout);
		return;
	}

	SwizzleOrAddMethod(cls, @selector(window), (IMP)DDNet_SDLUIKitDelegate_window, (IMP *)&s_pOrigWindowFunc, "@@:");
	SwizzleOrAddMethod(cls, @selector(setWindow:), (IMP)DDNet_SDLUIKitDelegate_setWindow, (IMP *)&s_pOrigSetWindowFunc, "v@:@");
	SwizzleOrAddMethod(cls, @selector(application:didFinishLaunchingWithOptions:), (IMP)DDNet_SDLUIKitDelegate_didFinishLaunching, (IMP *)&s_pOrigLaunchFunc, "B@:@@");
	SwizzleOrAddMethod(cls, @selector(application:supportedInterfaceOrientationsForWindow:), (IMP)DDNet_SDLUIKitDelegate_supportedOrientations, NULL, "Q@:@@");

	SetupSceneObserver();

	printf("PatchSDLUIKitDelegate: Successfully hooked SDLUIKitDelegate window and lifecycle\n");
	fflush(stdout);
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
			[report appendFormat:@"PC: 0x%016llx  LR: 0x%016llx  SP: 0x%016llx  FP: 0x%016llx\n",
				(unsigned long long)uc->uc_mcontext->__ss.__pc,
				(unsigned long long)uc->uc_mcontext->__ss.__lr,
				(unsigned long long)uc->uc_mcontext->__ss.__sp,
				(unsigned long long)uc->uc_mcontext->__ss.__fp];
			for(int i = 0; i < 29; i += 2)
			{
				[report appendFormat:@"x%-2d: 0x%016llx  x%-2d: 0x%016llx\n",
					i, (unsigned long long)uc->uc_mcontext->__ss.__x[i],
					i + 1, (i + 1 < 29) ? (unsigned long long)uc->uc_mcontext->__ss.__x[i + 1] : 0ULL];
			}
		}
	}
#endif
	[report appendString:@"Call Stack:\n"];
	for(NSString *symbol in [NSThread callStackSymbols])
	{
		[report appendFormat:@"%@\n", symbol];
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
		PatchSDLUIKitDelegate();
		PatchUIWindow();
		if([UIApplication sharedApplication] != nil)
		{
			EnsureEarlyWindow();
		}
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
				pUiWindow = s_pEarlyWindow;
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
