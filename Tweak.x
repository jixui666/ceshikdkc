#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/message.h>

%config(generator=internal)

static BOOL PMHIsPresenting = NO;
static BOOL PMHBypassPresentHook = NO;
static NSString * const kPMHBaseURL = @"https://h5.896789.top/#/entryPlan";

static void PMHLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSString *line = [NSString stringWithFormat:@"[PlanManageHijack] %@\n", message];
    NSLog(@"%@", [line stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]);

    NSString *logPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/pmh.log"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:logPath]) {
        [@"" writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (!handle) return;
    @try {
        [handle seekToEndOfFile];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (data.length) [handle writeData:data];
    } @catch (__unused NSException *e) {
    } @finally {
        [handle closeFile];
    }
}

static NSString *PMHStringFromPresentedVCURL(UIViewController *vc) {
    if (!vc) return nil;
    SEL sels[] = { @selector(URL), @selector(url), @selector(requestURL) };
    for (size_t i = 0; i < sizeof(sels) / sizeof(SEL); i++) {
        SEL sel = sels[i];
        if (![vc respondsToSelector:sel]) continue;
        id v = ((id (*)(id, SEL))objc_msgSend)(vc, sel);
        if ([v isKindOfClass:[NSURL class]]) return [(NSURL *)v absoluteString];
        if ([v isKindOfClass:[NSString class]]) return (NSString *)v;
    }
    if ([vc respondsToSelector:@selector(request)]) {
        id req = ((id (*)(id, SEL))objc_msgSend)(vc, @selector(request));
        if ([req isKindOfClass:[NSURLRequest class]]) return [((NSURLRequest *)req).URL absoluteString];
    }
    if ([vc respondsToSelector:@selector(webView)]) {
        id wv = ((id (*)(id, SEL))objc_msgSend)(vc, @selector(webView));
        if ([wv isKindOfClass:[WKWebView class]]) return ((WKWebView *)wv).URL.absoluteString;
    }
    return nil;
}

static BOOL PMHTitleIsOtherFoldawayMenu(NSString *t) {
    if (!t.length) return NO;
    NSString *low = t.lowercaseString;
    if ([low containsString:@"ad network"] || [low containsString:@"adnetwork"]) return YES;
    if ([low containsString:@"exchange"]) return YES;
    if ([low containsString:@"forex"]) return YES;
    if ([low containsString:@"advertise"]) return YES;
    if ([low containsString:@"advertisement"]) return YES;
    if ([low containsString:@"广告"]) return YES;
    if ([low containsString:@"换汇"]) return YES;
    if ([low containsString:@"外汇"]) return YES;
    return NO;
}

static BOOL PMHURLIsOtherFoldawayMenu(NSString *low) {
    if (!low.length) return NO;
    if ([low containsString:@"advertisecenter"]) return YES;
    if ([low containsString:@"advertise-center"] || [low containsString:@"advertise_center"]) return YES;
    if ([low containsString:@"#/advertise"]) return YES;
    if ([low containsString:@"/advertise"]) return YES;
    if ([low containsString:@"adnetwork"]) return YES;
    if ([low containsString:@"exchange"]) return YES;
    if ([low containsString:@"forex"]) return YES;
    if ([low containsString:@"shop"]) return YES;
    return NO;
}

static BOOL PMHURLLooksLikePlanManagePage(NSString *urlString) {
    if (!urlString.length) return NO;
    NSString *low = urlString.lowercaseString;
    if (PMHURLIsOtherFoldawayMenu(low)) return NO;
    if ([low containsString:@"planmanage"]) return YES;
    if ([low containsString:@"plan_manage"]) return YES;
    if ([low containsString:@"plan%2fmanage"] || [low containsString:@"plan/manage"]) return YES;
    if ([low containsString:@"plan"] && [low containsString:@"manage"]) return YES;
    if ([low containsString:@"kyalliance.com"] && [low containsString:@"plan"]) return YES;
    return NO;
}

static NSString *PMHKVCString(id obj, NSString *key) {
    if (!obj || !key.length) return nil;
    @try {
        id v = [obj valueForKey:key];
        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) return (NSString *)v;
        if ([v isKindOfClass:[NSNumber class]]) return [(NSNumber *)v stringValue];
    } @catch (__unused NSException *e) {
    }
    return nil;
}

static NSString *PMHFoldawayResolvedLabel(id fold) {
    if (!fold) return nil;
    NSArray<NSString *> *keys = @[
        @"mainBtnTitle", @"mainBtnSelectTitle", @"selectTitle", @"btnTitle",
        @"_mainBtnTitle", @"_mainBtnSelectTitle", @"_selectTitle", @"_btnTitle"
    ];
    for (NSString *k in keys) {
        NSString *s = PMHKVCString(fold, k);
        if (s.length) return s;
    }
    if ([fold respondsToSelector:@selector(mainBtnTitle)]) {
        NSString *s = ((NSString * (*)(id, SEL))objc_msgSend)(fold, @selector(mainBtnTitle));
        if (s.length) return s;
    }
    if ([fold respondsToSelector:@selector(selectTitle)]) {
        NSString *s = ((NSString * (*)(id, SEL))objc_msgSend)(fold, @selector(selectTitle));
        if (s.length) return s;
    }
    if ([fold respondsToSelector:@selector(mainBtn)]) {
        UIButton *b = ((id (*)(id, SEL))objc_msgSend)(fold, @selector(mainBtn));
        if ([b isKindOfClass:[UIButton class]]) {
            for (NSUInteger st = 0; st < 8; st++) {
                NSString *tt = [b titleForState:(UIControlState)st];
                if (tt.length) return tt;
            }
        }
    }
    @try {
        NSArray *arr = [fold valueForKey:@"titlesArray"];
        if (![arr isKindOfClass:[NSArray class]]) arr = [fold valueForKey:@"_titlesArray"];
        if ([arr isKindOfClass:[NSArray class]]) {
            for (id x in arr) {
                if (![x isKindOfClass:[NSString class]]) continue;
                NSString *s = (NSString *)x;
                if (!s.length) continue;
                if ([s rangeOfString:@"Plan Manage" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                    [s rangeOfString:@"计划管理"].location != NSNotFound) {
                    return s;
                }
            }
        }
    } @catch (__unused NSException *e) {
    }
    return nil;
}

static BOOL PMHShouldHijackPresentedViewController(UIViewController *vc) {
    if (!vc) return NO;
    NSString *clsName = NSStringFromClass([vc class]);
    if (!([clsName containsString:@"FBWebViewController"] ||
          [clsName containsString:@"WebPage"] ||
          [clsName containsString:@"WebViewController"])) {
        return NO;
    }
    NSString *urlStr = PMHStringFromPresentedVCURL(vc);
    NSString *low = urlStr.lowercaseString;
    if (PMHURLIsOtherFoldawayMenu(low)) {
        PMHLog(@"skip present hijack (native flow e.g. Ad Network -> advertiseCenter): %@", urlStr ?: @"(nil)");
        return NO;
    }
    if (!PMHURLLooksLikePlanManagePage(urlStr)) {
        PMHLog(@"skip present hijack (not plan/manage URL): %@", urlStr ?: @"(nil)");
        return NO;
    }
    return YES;
}

static UIViewController *PMHGetTopViewController(void) {
    UIWindow *targetWindow = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                if (window.isKeyWindow) {
                    targetWindow = window;
                    break;
                }
            }
            if (targetWindow) break;
        }
    }

    if (!targetWindow) targetWindow = [UIApplication sharedApplication].windows.firstObject;

    UIViewController *topVC = targetWindow.rootViewController;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;
    return topVC;
}

static NSDictionary *PMHLoadUserInfoPlistDictionary(void) {
    NSArray<NSString *> *candidates = @[
        [NSHomeDirectory() stringByAppendingPathComponent:@"user_info.plist"],
        [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/user_info.plist"],
        [NSHomeDirectory() stringByAppendingPathComponent:@"Library/user_info.plist"]
    ];

    for (NSString *path in candidates) {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
        if (dict.count) {
            PMHLog(@"loaded user_info.plist: %@", path);
            return dict;
        }
    }
    PMHLog(@"user_info.plist not found or invalid");
    return nil;
}

static id PMHJSONSafeValue(id value) {
    if ([value isKindOfClass:[NSString class]] ||
        [value isKindOfClass:[NSNumber class]] ||
        [value isKindOfClass:[NSNull class]]) {
        return value;
    }
    if ([value isKindOfClass:[NSDate class]]) {
        return @([(NSDate *)value timeIntervalSince1970]);
    }
    if ([value isKindOfClass:[NSData class]]) {
        return [(NSData *)value base64EncodedStringWithOptions:0];
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        [(NSDictionary *)value enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) {
            if ([k isKindOfClass:[NSString class]]) {
                id sv = PMHJSONSafeValue(v);
                if (sv) out[k] = sv;
            }
        }];
        return out;
    }
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *out = [NSMutableArray array];
        for (id v in (NSArray *)value) {
            id sv = PMHJSONSafeValue(v);
            if (sv) [out addObject:sv];
        }
        return out;
    }
    return nil;
}

static NSString *PMHBuildDataBase64FromPlist(NSDictionary *source) {
    if (!source.count) return nil;

    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    [source enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) {
        if (![k isKindOfClass:[NSString class]]) return;
        id safe = PMHJSONSafeValue(v);
        if (safe) m[k] = safe;
    }];

    id customIDObj = m[@"customID"];
    if (!customIDObj) customIDObj = m[@"customId"];
    if (customIDObj) {
        [m removeObjectForKey:@"customID"];
        [m removeObjectForKey:@"customId"];
        NSString *fbVal = nil;
        if ([customIDObj isKindOfClass:[NSString class]]) fbVal = customIDObj;
        else if ([customIDObj isKindOfClass:[NSNumber class]]) fbVal = [(NSNumber *)customIDObj stringValue];
        if (fbVal.length) m[@"fb_id"] = fbVal;
    }

    NSError *err = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:m options:0 error:&err];
    if (!jsonData.length) {
        PMHLog(@"JSON serialize failed: %@", err.localizedDescription ?: @"unknown");
        return nil;
    }
    return [jsonData base64EncodedStringWithOptions:0];
}

static NSString *PMHPercentEncodeForFragmentQuery(NSString *value) {
    if (!value.length) return @"";
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: value;
}

static NSString *PMHBuildCustomURLString(void) {
    NSDictionary *plist = PMHLoadUserInfoPlistDictionary();
    NSString *dataB64 = PMHBuildDataBase64FromPlist(plist);
    if (!dataB64.length) return kPMHBaseURL;

    NSString *encoded = PMHPercentEncodeForFragmentQuery(dataB64);
    return [NSString stringWithFormat:@"%@?data=%@", kPMHBaseURL, encoded];
}

static void PMHOpenCustomWebView(void) {
    if (PMHIsPresenting) return;
    PMHIsPresenting = YES;

    NSString *urlString = PMHBuildCustomURLString();
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        PMHIsPresenting = NO;
        return;
    }

    WKWebView *webView = [[WKWebView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    [webView loadRequest:[NSURLRequest requestWithURL:url]];

    UIViewController *topVC = PMHGetTopViewController();
    if (!topVC) {
        PMHIsPresenting = NO;
        return;
    }

    UIViewController *vc = [UIViewController new];
    vc.view = webView;
    PMHBypassPresentHook = YES;
    [topVC presentViewController:vc animated:YES completion:^{
        PMHBypassPresentHook = NO;
        PMHIsPresenting = NO;
    }];
    PMHLog(@"present custom webview: %@", urlString);
}

%hook SZFoldawayButton
- (void)clickMainButtonBack {
    id fold = (id)self;
    NSString *t = PMHFoldawayResolvedLabel(fold);
    PMHLog(@"foldaway clickMainButtonBack resolved label: %@", t ?: @"(nil)");
    if (PMHTitleIsOtherFoldawayMenu(t)) {
        PMHLog(@"skip foldaway hijack (other menu title): %@", t ?: @"(nil)");
        %orig;
        return;
    }
    BOOL ok = t.length && ([t rangeOfString:@"Plan Manage" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                           [t rangeOfString:@"计划管理"].location != NSNotFound);
    if (ok) {
        PMHOpenCustomWebView();
        return;
    }
    PMHLog(@"foldaway no Plan Manage label, try original");
    %orig;
}
%end

%hook UIControl
- (void)sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    if (![self isKindOfClass:[UIButton class]]) {
        %orig;
        return;
    }
    UIButton *btn = (UIButton *)self;
    NSString *t = [btn titleForState:UIControlStateNormal];
    NSString *acc = btn.accessibilityLabel;
    if (PMHTitleIsOtherFoldawayMenu(t) || PMHTitleIsOtherFoldawayMenu(acc)) {
        %orig;
        return;
    }
    BOOL hitTitle = t.length && ([t rangeOfString:@"Plan Manage" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                   [t rangeOfString:@"计划管理"].location != NSNotFound);
    BOOL hitAcc = acc.length && ([acc rangeOfString:@"Plan Manage" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                   [acc rangeOfString:@"计划管理"].location != NSNotFound);
    if (hitTitle || hitAcc) {
        PMHOpenCustomWebView();
        return;
    }
    %orig;
}
%end

%hook UIViewController
- (void)presentViewController:(UIViewController *)viewControllerToPresent
                     animated:(BOOL)flag
                   completion:(void (^)(void))completion {
    if (!PMHBypassPresentHook && PMHShouldHijackPresentedViewController(viewControllerToPresent)) {
        PMHOpenCustomWebView();
        return;
    }
    %orig;
}
%end
