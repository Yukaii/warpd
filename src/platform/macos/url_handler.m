#import <Cocoa/Cocoa.h>

static NSString *const kWarpdURLScheme = @"warpd";

static NSString *warpd_mode_from_url(NSURL *url)
{
	NSString *mode = url.host;
	if (!mode || mode.length == 0) {
		NSString *path = url.path;
		if (path.length > 1 && [path hasPrefix:@"/"])
			path = [path substringFromIndex:1];
		mode = path.length ? path : nil;
	}

	return mode.lowercaseString;
}

static BOOL warpd_query_item_truthy(NSURLComponents *components, NSString *name)
{
	for (NSURLQueryItem *item in components.queryItems) {
		if (![item.name.lowercaseString isEqualToString:name])
			continue;
		if (!item.value)
			return YES;

		NSString *value = item.value.lowercaseString;
		if ([value isEqualToString:@"1"] || [value isEqualToString:@"true"] ||
		    [value isEqualToString:@"yes"] || [value isEqualToString:@"on"])
			return YES;
	}

	return NO;
}

static NSArray<NSString *> *warpd_arguments_for_url(NSURL *url)
{
	if (![[url.scheme lowercaseString] isEqualToString:kWarpdURLScheme])
		return nil;

	NSString *mode = warpd_mode_from_url(url);
	NSDictionary<NSString *, NSString *> *modes = @{
		@"hint": @"--hint",
		@"hint2": @"--hint2",
		@"find": @"--find",
		@"grid": @"--grid",
		@"normal": @"--normal",
		@"history": @"--history",
		@"screen": @"--screen",
	};

	NSString *mode_arg = modes[mode];
	if (!mode_arg)
		return nil;

	NSURLComponents *components = [NSURLComponents componentsWithURL:url
							 resolvingAgainstBaseURL:NO];
	NSMutableArray<NSString *> *args = [NSMutableArray arrayWithObject:mode_arg];
	if (components && warpd_query_item_truthy(components, @"oneshot"))
		[args addObject:@"--oneshot"];

	return args;
}

@interface WarpdURLHandler : NSObject
@end

@implementation WarpdURLHandler
- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event
		 withReplyEvent:(NSAppleEventDescriptor *)replyEvent
{
	NSString *url_string = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
	NSURL *url = url_string ? [NSURL URLWithString:url_string] : nil;
	NSArray<NSString *> *args = url ? warpd_arguments_for_url(url) : nil;
	if (!args) {
		NSLog(@"warpd-url-handler: unsupported url %@", url_string ?: @"(null)");
		[NSApp terminate:nil];
		return;
	}

	NSTask *task = [[NSTask alloc] init];
	NSMutableDictionary<NSString *, NSString *> *env =
		[NSMutableDictionary dictionaryWithDictionary:NSProcessInfo.processInfo.environment];
	env[@"PATH"] = @"/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
	[task setEnvironment:env];
	[task setLaunchPath:@"/usr/bin/env"];
	NSMutableArray<NSString *> *task_args = [NSMutableArray arrayWithObject:@"warpd"];
	[task_args addObjectsFromArray:args];
	[task setArguments:task_args];

	@try {
		[task launch];
	} @catch (NSException *exception) {
		NSLog(@"warpd-url-handler: failed to launch warpd (%@)", exception);
	}

	[NSApp terminate:nil];
}
@end

int main(int argc, const char *argv[])
{
	@autoreleasepool {
		WarpdURLHandler *handler = [[WarpdURLHandler alloc] init];
		NSAppleEventManager *manager = [NSAppleEventManager sharedAppleEventManager];
		[manager setEventHandler:handler
				 andSelector:@selector(handleGetURLEvent:withReplyEvent:)
			   forEventClass:kInternetEventClass
			      andEventID:kAEGetURL];

		[NSApplication sharedApplication];
		[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
		[NSApp run];
	}

	return 0;
}
