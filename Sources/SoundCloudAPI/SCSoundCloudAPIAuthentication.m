/*
 * Copyright 2010 nxtbgthng for SoundCloud Ltd.
 * 
 * Licensed under the Apache License, Version 2.0 (the "License"); you may not
 * use this file except in compliance with the License. You may obtain a copy of
 * the License at
 * 
 * http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
 * WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
 * License for the specific language governing permissions and limitations under
 * the License.
 *
 * For more information and documentation refer to
 * http://soundcloud.com/api
 * 
 */

#if TARGET_OS_IPHONE
#import "NXOAuth2.h"
#else
#import <OAuth2Client/NXOAuth2.h>
#endif

#import "SCSoundCloudAPIConfiguration.h"
#import "SCSoundCloudAPIAuthenticationDelegate.h"
#import "SCLoginViewController.h"


#import <sys/types.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>

#if !TARGET_OS_IPHONE
#ifndef __GESTALT__
#include <Gestalt.h>
#endif
#endif


#import "SCSoundCloudAPIAuthentication.h"


@interface SCSoundCloudAPIAuthentication () <NXOAuth2ClientDelegate>
@property (assign, getter=isAuthenticated) BOOL authenticated;
#if TARGET_OS_IPHONE
- (void)displayLoginViewControllerWithURL:(NSURL *)URL;
- (void)dismissLoginViewController:(UIViewController *)viewController;
#endif
- (NSString *)userAgentString;
- (NSString *)sysctlValueForName:(NSString *)name;
@end


@implementation SCSoundCloudAPIAuthentication

#pragma mark Lifecycle

- (id)initWithAuthenticationDelegate:(id<SCSoundCloudAPIAuthenticationDelegate>)aDelegate
					apiConfiguration:(SCSoundCloudAPIConfiguration *)aConfiguration;
{
	if (self = [super init]) {
		delegate = aDelegate;
        
		configuration = [aConfiguration retain];
		
		oauthClient = [[NXOAuth2Client alloc] initWithClientID:[configuration consumerKey]
												  clientSecret:[configuration consumerSecret]
												  authorizeURL:[configuration authURL]
													  tokenURL:[configuration accessTokenURL]
													  delegate:self];
		oauthClient.userAgent = [self userAgentString];
	}
	return self;
}

- (void)dealloc;
{
	[configuration release];
	[oauthClient release];
	[super dealloc];
}


#pragma mark Accessors

@synthesize oauthClient;
@synthesize configuration;
@synthesize authenticated;


#pragma mark Public

- (void)requestAuthentication;
{
	[oauthClient requestAccess];
}

- (void)resetAuthentication;
{
	oauthClient.accessToken = nil;
}

- (BOOL)handleRedirectURL:(NSURL *)redirectURL;
{
	return [oauthClient openRedirectURL:redirectURL];
}

- (void)authenticateWithUsername:(NSString *)username password:(NSString *)password;
{
	[oauthClient authenticateWithUsername:username password:password];
}


#pragma mark NXOAuth2ClientAuthDelegate

//TODO: Error handling if using the LoginViewController

- (void)oauthClientNeedsAuthentication:(NXOAuth2Client *)client;
{
	NSURL *authorizationURL = nil;
	if ([configuration callbackURL]) {
		authorizationURL = [client authorizationURLWithRedirectURL:[configuration callbackURL]];
	}
    if ([delegate respondsToSelector:@selector(soundCloudAPIPreparedAuthorizationURL:)]) {
        [delegate soundCloudAPIPreparedAuthorizationURL:authorizationURL];
    }
#if TARGET_OS_IPHONE
    [self displayLoginViewControllerWithURL:authorizationURL];
#endif
         
}

- (void)oauthClientDidLoseAccessToken:(NXOAuth2Client *)client;
{
	self.authenticated = NO;
    if ([delegate respondsToSelector:@selector(soundCloudAPIDidResetAuthentication)]){
        [delegate soundCloudAPIDidResetAuthentication];
    }
}

- (void)oauthClientDidGetAccessToken:(NXOAuth2Client *)client;
{
	self.authenticated = YES;
    if ([delegate respondsToSelector:@selector(soundCloudAPIDidAuthenticate)]) {
        [delegate soundCloudAPIDidAuthenticate];
    }
}

- (void)oauthClient:(NXOAuth2Client *)client didFailToGetAccessTokenWithError:(NSError *)error;
{
    if ([delegate respondsToSelector:@selector(soundCloudAPIDidFailToGetAccessTokenWithError:)]) {
        [delegate soundCloudAPIDidFailToGetAccessTokenWithError:error];
    }
}

#if TARGET_OS_IPHONE

#pragma mark Login ViewController

- (void)displayLoginViewControllerWithURL:(NSURL *)URL;
{    
    SCLoginViewController *loginViewController = [[[SCLoginViewController alloc] initWithURL:URL authentication:self] autorelease];
    
    /*
    UINavigationController *navController = [[[UINavigationController alloc] initWithRootViewController:loginViewController] autorelease];
    navController.navigationBar.tintColor = [UIColor orangeColor];
    if ([navController respondsToSelector:@selector(setModalPresentationStyle:)]){
        [navController setModalPresentationStyle:UIModalPresentationFormSheet];
    } */
	
	if ([delegate respondsToSelector:@selector(soundCloudAPIWillDisplayLoginViewController:)]) {
		[delegate soundCloudAPIWillDisplayLoginViewController:loginViewController];
	}
	
    if ([delegate respondsToSelector:@selector(soundCloudAPIDisplayViewController:)]) {
        [delegate soundCloudAPIDisplayViewController:loginViewController];
        
    } else if (![delegate respondsToSelector:@selector(soundCloudAPIPreparedAuthorizationURL:)]) {
        //do the presentation yourself when the delegate really does not respond to any of the callbacks for doing it himself
        NSArray *windows = [[UIApplication sharedApplication] windows];
        UIWindow *window = nil;
        if (windows.count > 0) window = [windows objectAtIndex:0];
        if ([window respondsToSelector:@selector(rootViewController)]) {
            UIViewController *rootViewController = [window rootViewController];
            [rootViewController presentModalViewController: loginViewController animated:YES];
        } else {
			NSAssert(NO, @"If you're not on iOS4 you need to implement -soundCloudAPIDisplayViewController: or show your own authentication controller in -soundCloudAPIPreparedAuthorizationURL:");
        }
    }
}

- (void)dismissLoginViewController:(UIViewController *)viewController;
{
    if ([delegate respondsToSelector:@selector(soundCloudAPIDismissViewController:)]) {
        [delegate soundCloudAPIDismissViewController:viewController];
    }
    
    else if (![delegate respondsToSelector:@selector(soundCloudAPIPreparedAuthorizationURL:)]
        && ![delegate respondsToSelector:@selector(soundCloudAPIDisplayViewController:)]) {
        NSArray *windows = [[UIApplication sharedApplication] windows];
        UIWindow *window = nil;
        if (windows.count > 0) window = [windows objectAtIndex:0];
        if ([window respondsToSelector:@selector(rootViewController)]) {
            UIViewController *rootViewController = [window rootViewController];
            [rootViewController dismissModalViewControllerAnimated:YES];
        } else {
			NSAssert(NO, @"If you're not on iOS4 you need to implement -soundCloudAPIDismissViewController: or show your own authentication controller in -soundCloudAPIPreparedAuthorizationURL:");
		}
    }
}

#endif


#pragma mark User Agent String

- (NSString *)userAgentString;
{
	NSMutableString *userAgentString = [NSMutableString string];
	NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
	NSString *appVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
	[userAgentString appendFormat:@"%@/%@;", appName, appVersion];
	
	NSString *apiWrapperName = @"SCSoundCloudAPI";
	NSString *apiWrapperVersion = SCAPI_VERSION;
	[userAgentString appendFormat:@" %@/%@;", apiWrapperName, apiWrapperVersion];
	
	NSString *hwModel = nil;
	NSString *hwMachine = [self sysctlValueForName:@"hw.machine"];
#if TARGET_OS_IPHONE
	UIDevice *device = [UIDevice currentDevice];
	hwModel = [device model]; // we take model for device
#else
	hwModel = @"Mac";
#endif
	if (hwModel && hwMachine) {
		[userAgentString appendFormat:@" %@/%@;", hwModel, hwMachine];
	}
	
	NSString *osType = nil;
	NSString *osRelease = nil;
#if TARGET_OS_IPHONE
	osType = [device systemName];
	osRelease = [device systemVersion];
#else
	osType = @"Mac OS X";
	SInt32 versMajor, versMinor, versBugFix;
	Gestalt(gestaltSystemVersionMajor, &versMajor);
	Gestalt(gestaltSystemVersionMinor, &versMinor);
	Gestalt(gestaltSystemVersionBugFix, &versBugFix);
	osRelease = [NSString stringWithFormat:@"%d.%d.%d", versMajor, versMinor, versBugFix];
#endif
	if (osType && osRelease) {
		[userAgentString appendFormat:@" %@/%@;", osType, osRelease];
	}
	
	NSString *darwinType = [self sysctlValueForName:@"kern.ostype"];
	NSString *darwinRelease = [self sysctlValueForName:@"kern.osrelease"];
	if (darwinType && darwinRelease) {
		[userAgentString appendFormat:@" %@/%@", darwinType, darwinRelease];
	}
	
	return userAgentString;
}

- (NSString *)sysctlValueForName:(NSString *)name;
{
	size_t size;
	const char* cName = [name UTF8String];
    if (sysctlbyname(cName, NULL, &size, NULL, 0) != noErr) return nil;
	
	NSString *value = nil;
    char *cValue = malloc(size);
    if (sysctlbyname(cName, cValue, &size, NULL, 0) == noErr) {
		value = [NSString stringWithCString:cValue encoding:NSUTF8StringEncoding];
	}
    free(cValue);
    return value;
}

@end