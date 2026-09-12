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

#include <cmath>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <unistd.h>

extern "C" int SDL_UIKitRunApp(int argc, char **argv, int (*mainFunction)(int, char **));
extern "C" int SDL_main(int argc, char **argv);

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
