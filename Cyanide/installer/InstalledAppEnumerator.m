//
//  InstalledAppEnumerator.m
//  Cyanide
//
//  MIP (mobile_installation_proxy) based installed-app enumeration with an
//  LSApplicationWorkspace fallback.
//
//  Why MIP first:
//    - The original Cyanide 1.2.24 IPA used mobile_installation_proxy.
//    - LSApplicationWorkspace from a non-SpringBoard process returns an empty
//      list on iOS 17+ (confirmed by the user's empty "Installed Apps" UI),
//      so it is only used as a last-resort fallback here.
//
//  MIP protocol (XPC service "com.apple.mobile.installation_proxy"):
//    -> {"Command": "Lookup", "ClientOptions": {"ApplicationType": "User"}}
//    <- {"LookupResult": [ {CFBundleIdentifier, CFBundleDisplayName,
//                           CFBundleShortVersionString, ...}, ... ]}
//

#import "InstalledAppEnumerator.h"
#import "../LogTextView.h"
#import "../kexploit/kexploit_opa334.h"
#import <xpc/xpc.h>
#import <dlfcn.h>

@implementation InstalledApp
@end

#pragma mark - MIP (mobile_installation_proxy) enumeration

static NSArray<InstalledApp *> *enumerateViaMobileInstallationProxy(void)
{
    NSMutableArray<InstalledApp *> *apps = [NSMutableArray array];

    xpc_connection_t conn = xpc_connection_create_mach_service(
        "com.apple.mobile.installation_proxy", NULL, 0);
    if (!conn) {
        log_user("[APPLIST] MIP: failed to create connection.\n");
        return apps;
    }

    xpc_connection_set_event_handler(conn, ^(xpc_object_t event) {
        // Errors/notifications only; Lookup is synchronous.
    });
    xpc_connection_resume(conn);

    xpc_object_t request = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_string(request, "Command", "Lookup");

    xpc_object_t options = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_string(options, "ApplicationType", "User");
    xpc_dictionary_set_value(request, "ClientOptions", options);

    xpc_object_t reply = xpc_connection_send_message_with_reply_sync(conn, request);
    if (!reply || xpc_get_type(reply) != XPC_TYPE_DICTIONARY) {
        log_user("[APPLIST] MIP: no reply (err=%s)\n",
                 reply ? xpc_dictionary_get_string(reply, "error") : "nil");
        xpc_connection_cancel(conn);
        return apps;
    }

    xpc_object_t results = xpc_dictionary_get_value(reply, "LookupResult");
    if (!results || xpc_get_type(results) != XPC_TYPE_ARRAY) {
        log_user("[APPLIST] MIP: no LookupResult in reply.\n");
        xpc_connection_cancel(conn);
        return apps;
    }

    xpc_array_apply(results, ^bool(size_t index, xpc_object_t value) {
        if (xpc_get_type(value) != XPC_TYPE_DICTIONARY) return true;
        const char *bundleID = xpc_dictionary_get_string(value, "CFBundleIdentifier");
        if (!bundleID) return true;
        const char *name = xpc_dictionary_get_string(value, "CFBundleDisplayName");
        if (!name) name = xpc_dictionary_get_string(value, "CFBundleName");
        const char *version = xpc_dictionary_get_string(value, "CFBundleShortVersionString");

        InstalledApp *app = [InstalledApp new];
        app.bundleID = [NSString stringWithUTF8String:bundleID];
        app.name = name ? [NSString stringWithUTF8String:name] : app.bundleID;
        app.version = version ? [NSString stringWithUTF8String:version] : @"";
        [apps addObject:app];
        return true;
    });

    xpc_connection_cancel(conn);
    return apps;
}

#pragma mark - LSApplicationWorkspace fallback

static NSArray<InstalledApp *> *enumerateViaLSApplicationWorkspace(void)
{
    NSMutableArray<InstalledApp *> *apps = [NSMutableArray array];

    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!workspaceClass) {
        log_user("[APPLIST] LSW: LSApplicationWorkspace unavailable.\n");
        return apps;
    }
    id workspace = [workspaceClass performSelector:NSSelectorFromString(@"defaultWorkspace")];
    if (!workspace) return apps;

    NSArray *proxies = [workspace performSelector:NSSelectorFromString(@"allInstalledApplications")];
    for (id proxy in proxies) {
        NSString *bundleID = [proxy performSelector:NSSelectorFromString(@"bundleIdentifier")];
        NSString *name     = [proxy performSelector:NSSelectorFromString(@"localizedName")];
        NSString *version  = [proxy performSelector:NSSelectorFromString(@"shortVersionString")];
        if (!bundleID.length) continue;

        InstalledApp *app = [InstalledApp new];
        app.bundleID = bundleID;
        app.name = name.length ? name : bundleID;
        app.version = version;
        [apps addObject:app];
    }
    return apps;
}

#pragma mark - Entry point

NSArray<InstalledApp *> *InstalledAppEnumeratorList(void)
{
    // 1) MIP — the original binary's path. Best on iOS 17+.
    NSArray<InstalledApp *> *mipApps = enumerateViaMobileInstallationProxy();
    if (mipApps.count > 0) {
        log_user("[APPLIST] Enumerated %lu apps via mobile_installation_proxy.\n",
                 (unsigned long)mipApps.count);
        return [mipApps sortedArrayUsingComparator:^NSComparisonResult(InstalledApp *a, InstalledApp *b) {
            return [a.name localizedCaseInsensitiveCompare:b.name];
        }];
    }

    // 2) LSApplicationWorkspace fallback (works on older iOS / with the right
    //    entitlements; returns empty on stock iOS 17+).
    NSArray<InstalledApp *> *lswApps = enumerateViaLSApplicationWorkspace();
    if (lswApps.count > 0) {
        log_user("[APPLIST] Enumerated %lu apps via LSApplicationWorkspace fallback.\n",
                 (unsigned long)lswApps.count);
        return [lswApps sortedArrayUsingComparator:^NSComparisonResult(InstalledApp *a, InstalledApp *b) {
            return [a.name localizedCaseInsensitiveCompare:b.name];
        }];
    }

    bool krwReady = kexploit_krw_ready();
    log_user("[APPLIST] WARNING: no installed apps enumerated (MIP + LSW both empty).\n"
             "          KRW ready: %s. This usually means the process lacks the required\n"
             "          entitlements — run the kernel exploit (KRW) first, then reopen\n"
             "          this screen.\n", krwReady ? "YES" : "NO");
    return @[];
}
