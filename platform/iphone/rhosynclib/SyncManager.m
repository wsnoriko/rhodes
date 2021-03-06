/*
 *  SyncManager.m
 *  RhoSyncClient
 *
 *  Copyright (C) 2008 Rhomobile, Inc. All rights reserved.
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
#import <UIKit/UIKit.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <SystemConfiguration/SCNetworkReachability.h>
#import <Foundation/Foundation.h>
#include "Constants.h"
#include "SyncJSONReader.h"
#include "SyncUtil.h"
#include "SyncEngine.h"

extern int logged_in();
extern void logout();
extern NSString *get_session();
extern int has_network_impl();
extern int isNetworkAvailableFlags(SCNetworkReachabilityFlags *outFlags);

/*
 An enumeration that defines the return values of the network state
 of the device.
 */
typedef enum {
	NotReachable = 0,
	ReachableViaCarrierDataNetwork,
	ReachableViaWiFiNetwork
} NetworkStatus;

/* 
 * Pulls the latest object_values list 
 * for a given source and populates a list
 * of sync objects in memory and the database.
 */
char *fetch_remote_data(char *url_string) {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSString *session;
	session = get_session(url_string);
	if (session || strstr(url_string, "clientcreate")) {
		printf("Fetching data from %s\n", url_string);
		char *ret_data;
		[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
		NSURL *url = [NSURL URLWithString:[[[NSString alloc] initWithUTF8String:url_string] autorelease]];
		
		NSMutableURLRequest *request = [[[NSMutableURLRequest alloc] init] autorelease];
		NSError *error = nil;
		NSHTTPURLResponse* response;
		[request setURL:url];
		[request setHTTPMethod:@"GET"];
		if (session) {
			[request setValue:session forHTTPHeaderField:@"Cookie"];
		}
		
		NSString *logData;
		NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
		NSInteger code = [response statusCode];
		NSInteger errorCode = [error code];
		code = [response statusCode];
		[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
		if (code != 200) {
			NSLog(@"An error occured connecting to the sync source: %i returned", code);
			if (errorCode == NSURLErrorUserCancelledAuthentication || 
				errorCode == NSURLErrorUserAuthenticationRequired) {
				logout();
			}
			[pool drain];
			[pool release];
			return NULL;
		}  else {
			logData = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
		}
		ret_data = str_assign((char *)[logData UTF8String]);
		[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
		[pool drain];
		[pool release];
		return ret_data;
	} else {
		[pool drain];
		[pool release];
		return NULL;
	}
}

/*
 * Login with given login/password
 * If return success if cookie is stored into shared
 * cookie storage NSHTTPCookieStorage
 */
int login(const char *login, const char *password) {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	pSource *source_list;
	NSString *session;
	int retval = 0, i, source_length, cookie_size = 0;
	source_list = malloc(MAX_SOURCES*sizeof(pSource));
	source_length = get_sources_from_database(source_list, get_database(), MAX_SOURCES);
	for(i = 0; i < source_length; i++) {
		char login_string[4096] = "";
		sprintf(login_string, 
				"%s/client_login", 
				source_list[i]->_source_url);
		session = get_session(source_list[i]->_source_url);
		if (!session) {
			[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
			NSMutableURLRequest *request = [[[NSMutableURLRequest alloc] init] autorelease];
			NSError *error = [[[NSError alloc] init] autorelease];
			NSHTTPURLResponse *response = [[[NSHTTPURLResponse alloc] init] autorelease];
			NSString *linkString = [[NSString alloc] initWithUTF8String:login_string];
			NSMutableString *postBody = [[NSMutableString alloc] initWithString:@"login="];
			[postBody appendString:[[NSString alloc] initWithUTF8String:login]];
			[postBody appendString:@"&password="];
			[postBody appendString:[[NSString alloc] initWithUTF8String:password]];
			[postBody appendString:@"&remember_me=1"];
			[request setURL:[NSURL URLWithString:linkString]];
			[request setHTTPMethod:@"POST"];
			[request setHTTPBody:[postBody dataUsingEncoding:NSUTF8StringEncoding]];
			NSURLConnection *conn=[[NSURLConnection alloc] initWithRequest:request delegate:nil];
			if (conn) {
				[NSURLConnection sendSynchronousRequest: request returningResponse:&response error: &error];
				NSInteger errorCode = [error code];
				NSInteger code = [response statusCode];
				[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
				if (code != 200) {
					NSLog(@"An error occured connecting to the sync source: %i returned", code);
					if (errorCode == NSURLErrorUserCancelledAuthentication || 
						errorCode == NSURLErrorUserAuthenticationRequired ||
						errorCode == NSURLErrorBadServerResponse) {
						logout();
					}
				} else {
					NSHTTPCookieStorage *store = [NSHTTPCookieStorage sharedHTTPCookieStorage];
					NSArray *cookies = [NSHTTPCookie cookiesWithResponseHeaderFields:[(NSHTTPURLResponse*)response allHeaderFields] 
																			  forURL:[NSURL URLWithString:linkString]];
					NSEnumerator *c = [cookies objectEnumerator];
					id cookie;
					while (cookie = [c nextObject]) {
						NSLog(@"Storing Cookie: Name: %@, Value: %@",
							  [cookie name],
							  [cookie value]);				
						[store setCookie:cookie];
						cookie_size++;
					}
				}
			}
		} else {
			printf("Found existing session for url...\n");
		}
	}
	if (cookie_size == 0) {
		retval = 0;
	} else {
		retval = 1;
	}
	[pool drain];
	[pool release];
	return retval;
}

/*
 * Pushes changes from list to rhosync server
 */
int push_remote_data(char* url, char* data, size_t data_size,char* contentType) {
	int retval = SYNC_PUSH_CHANGES_OK;
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	if (data_size == 0 || data == NULL) {
		[pool release];
		return SYNC_PUSH_CHANGES_OK;
	}
	NSString *session = get_session(url);
	if (session) {
		[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
		NSMutableURLRequest *request = [[[NSMutableURLRequest alloc] init] autorelease];
		NSError *error = nil;
		NSHTTPURLResponse *response;
		NSString *linkString = [[NSString alloc] initWithUTF8String:url];
		NSMutableData *postBody = [NSMutableData dataWithBytes:data length:data_size];
		[request setURL:[NSURL URLWithString:linkString]];
		[request setHTTPMethod:@"POST"];
		
		if (contentType){
			NSString *temp = [[NSString alloc] initWithUTF8String:contentType];
			[request setValue:temp forHTTPHeaderField:@"Content-Type"];
		}
		
		if (session) {
			[request setValue:session forHTTPHeaderField:@"Cookie"];
		}
		[request setHTTPBody:postBody];
		NSURLConnection *conn=[[NSURLConnection alloc] initWithRequest:request delegate:nil];
		if (conn) {
			NSData *returnData = [ NSURLConnection sendSynchronousRequest: request returningResponse:&response error: &error ];
			NSInteger errorCode = [error code];
			NSInteger code = [response statusCode];
			[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
			if (code != 200) {
				NSLog(@"An error occured connecting to the sync source: %i returned", code);
				if (errorCode == NSURLErrorUserCancelledAuthentication || 
					errorCode == NSURLErrorUserAuthenticationRequired) {
					logout();
				}
				retval = SYNC_PUSH_CHANGES_ERROR;
			} else {
				NSString *output = [NSString stringWithCString:[returnData bytes]];
				NSLog(@"RESPONSE: %@", output);
			}
		}
		[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
		retval = SYNC_PUSH_CHANGES_OK;
	} else {
		retval = SYNC_PUSH_CHANGES_ERROR;
	}
	[pool drain];
	[pool release];
	return retval;
}

NSArray *get_all_cookies() {
	NSHTTPCookieStorage *cookieStore = [NSHTTPCookieStorage sharedHTTPCookieStorage];
	NSArray *cookies = [cookieStore cookies];
	return cookies;
}

int logged_in() {
	int i,retval = 0;
	NSArray *cookies;
	cookies = get_all_cookies();
	int count = [cookies count];
	// Iterate over all cookies and see if we have a rhosync_session
	for (i = 0; i < count; i++) {
		if ([[[cookies objectAtIndex:i] name] isEqualToString:@"rhosync_session"]) retval = 1;
	}
	return retval;
}

void logout() {
	int i;
	NSArray *cookies;
	cookies = get_all_cookies();
	int count = [cookies count];
	for (i = 0; i < count; i++) {
		NSHTTPCookie *cookie = [cookies objectAtIndex:i];
		NSString *name = [cookie name];
		if ([name isEqualToString:@"rhosync_session"] || [name isEqualToString:@"auth_token"]) {
			[[NSHTTPCookieStorage sharedHTTPCookieStorage] deleteCookie:cookie];
		}
	}
}

/*
 * Retrieve cookie from shared cookie storage
 */
NSString *get_session(char *url_string) {
	NSString *session = NULL;
	NSString *ns_url_string = [[[NSString alloc] initWithUTF8String:url_string] autorelease];
	NSHTTPCookieStorage *cookieStore = [NSHTTPCookieStorage sharedHTTPCookieStorage];
	if (cookieStore && ns_url_string) {
		NSURL *url = [NSURL URLWithString:[ns_url_string stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
		// In the case where url_string is not properly encoded, url will be nil
		if(url) {
			NSArray *cookies = [cookieStore cookiesForURL:url];
			NSString *cookie = [[NSHTTPCookie requestHeaderFieldsWithCookies:cookies] objectForKey:@"Cookie"];
			
			if (cookie) {
				session = [[[NSString alloc] initWithString:cookie] autorelease];
			}
		}
	}
	return session;
}

// Determines network connectivity
int has_network_impl() {
	SCNetworkReachabilityFlags defaultRouteFlags;
	int defaultRouteIsAvailable = isNetworkAvailableFlags(&defaultRouteFlags);
	if (defaultRouteIsAvailable == 1) {
		if (defaultRouteFlags & kSCNetworkReachabilityFlagsIsDirect) {
			// Ad-Hoc network, not available
			return 0;
		}
		else if (defaultRouteFlags & ReachableViaCarrierDataNetwork) {
			// Cell network available
			return 1;
		}
		// WIFI available
		return 1;
	}
	return 0;
}

int isNetworkAvailableFlags(SCNetworkReachabilityFlags *outFlags)
{
	struct sockaddr_in zeroAddress;
	BOOL isReachable = FALSE;
	int reachable = 0;
	SCNetworkReachabilityRef defaultRouteReachability;
	NSString *hostNameOrAddress; 
	bzero(&zeroAddress, sizeof(zeroAddress));
	zeroAddress.sin_len = sizeof(zeroAddress);
	zeroAddress.sin_family = AF_INET;
	
	defaultRouteReachability = SCNetworkReachabilityCreateWithAddress(NULL, (struct sockaddr *)&zeroAddress);
	hostNameOrAddress = @"0.0.0.0";
	
	SCNetworkReachabilityFlags flags;
	BOOL gotFlags = SCNetworkReachabilityGetFlags(defaultRouteReachability, &flags);
	if (!gotFlags) {
		CFRelease(defaultRouteReachability);
        return reachable;
    }
    
	isReachable = flags & kSCNetworkReachabilityFlagsReachable;
	BOOL noConnectionRequired = !(flags & kSCNetworkReachabilityFlagsConnectionRequired);
	if ((flags & kSCNetworkReachabilityFlagsIsWWAN)) {
		noConnectionRequired = YES;
	}
	
	reachable = (isReachable && noConnectionRequired) ? 1 : 0;
	
	// Callers of this method might want to use the reachability flags, so if an 'out' parameter
	// was passed in, assign the reachability flags to it.
	if (outFlags) {
		*outFlags = flags;
	}
	CFRelease(defaultRouteReachability);
	return reachable;
}
