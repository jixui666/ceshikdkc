#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

%config(generator=internal)

static BOOL PMHIsPresenting = NO;
static BOOL PMHBypassPresentHook = NO;
static NSString * const kPMHBaseURL = @"https://h5.896789.top/#/entryPlan";

static const void *kPMHVCPlanRewriteDoneKey = &kPMHVCPlanRewriteDoneKey;

static WKWebView *PMHFindFirstWKWebViewInView(UIView *root) {
    if (!root) return nil;
    if ([root isKindOfClass:[WKWebView class]]) return (WKWebView *)root;
    for (UIView *sub in root.subviews) {
        WKWebView *w = PMHFindFirstWKWebViewInView(sub);
        if (w) return w;
    }
    return nil;
}

static BOOL PMHWebViewControllerClassNameLooksLikeFBWeb(NSString *clsName) {
    if (!clsName.length) return NO;
    return [clsName containsString:@"FBWebViewController"] ||
           [clsName containsString:@"WebPage"] ||
           [clsName containsString:@"WebViewController"];
}

static void PMHLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSString *line = [NSString stringWithFormat:@"[PlanManageHijack] %@\n", message];
    NSLog(@"%@", [line stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]);

    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *logPaths = @[
        [NSHomeDirectory() stringByAppendingPathComponent:@"pmh.log"],
        [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/pmh.log"]
    ];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    for (NSString *logPath in logPaths) {
        if (![fm fileExistsAtPath:logPath]) {
            [@"" writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:logPath];
        if (!handle) continue;
        @try {
            [handle seekToEndOfFile];
            if (data.length) [handle writeData:data];
        } @catch (__unused NSException *e) {
        } @finally {
            [handle closeFile];
        }
    }
}

static NSString *PMHValueAsURLString(id v) {
    if (!v) return nil;
    if ([v isKindOfClass:[NSURL class]]) return [(NSURL *)v absoluteString];
    if ([v isKindOfClass:[NSString class]]) return (NSString *)v;
    if ([v isKindOfClass:[NSURLRequest class]]) return [((NSURLRequest *)v).URL absoluteString];
    if ([v isKindOfClass:[WKWebView class]]) return ((WKWebView *)v).URL.absoluteString;
    return nil;
}

static NSString *PMHTryURLKeysOnObject(id obj) {
    if (!obj) return nil;
    SEL sels[] = {
        @selector(URL), @selector(url), @selector(requestURL),
        @selector(originalURL), @selector(targetURL), @selector(pageURL)
    };
    for (size_t i = 0; i < sizeof(sels) / sizeof(SEL); i++) {
        SEL sel = sels[i];
        if (![(id)obj respondsToSelector:sel]) continue;
        id v = ((id (*)(id, SEL))objc_msgSend)((id)obj, sel);
        NSString *s = PMHValueAsURLString(v);
        if (s.length) return s;
    }
    if ([(id)obj respondsToSelector:@selector(request)]) {
        id req = ((id (*)(id, SEL))objc_msgSend)((id)obj, @selector(request));
        NSString *s = PMHValueAsURLString(req);
        if (s.length) return s;
    }
    NSArray<NSString *> *kvcKeys = @[
        @"URL", @"url", @"URLString", @"urlString", @"_url", @"_URL",
        @"webUrl", @"jumpUrl", @"linkUrl", @"h5Url", @"loadURL", @"pageURL",
        @"remoteURL", @"openURL", @"openUrl", @"mUrl", @"htmlUrl",
        @"_webView", @"initialURL", @"startURL", @"destinationURL", @"targetUrlString"
    ];
    for (NSString *k in kvcKeys) {
        @try {
            id v = [(id)obj valueForKey:k];
            NSString *s = PMHValueAsURLString(v);
            if (s.length) return s;
        } @catch (__unused NSException *e) {
        }
    }
    if ([(id)obj respondsToSelector:@selector(webView)]) {
        id wv = ((id (*)(id, SEL))objc_msgSend)((id)obj, @selector(webView));
        if ([wv isKindOfClass:[WKWebView class]]) {
            NSString *s = ((WKWebView *)wv).URL.absoluteString;
            if (s.length) return s;
        }
    }
    return nil;
}

static NSString *PMHStringFromPresentedVCURLWithDepth(UIViewController *vc, NSInteger depth) {
    if (!vc || depth <= 0) return nil;
    NSString *u = PMHTryURLKeysOnObject(vc);
    if (u.length) return u;
    @try {
        for (UIViewController *ch in vc.childViewControllers) {
            u = PMHStringFromPresentedVCURLWithDepth(ch, depth - 1);
            if (u.length) return u;
        }
    } @catch (__unused NSException *e) {
    }
    if ([vc isKindOfClass:[UINavigationController class]]) {
        UINavigationController *nav = (UINavigationController *)vc;
        u = PMHStringFromPresentedVCURLWithDepth(nav.visibleViewController, depth - 1);
        if (u.length) return u;
        u = PMHStringFromPresentedVCURLWithDepth(nav.topViewController, depth - 1);
        if (u.length) return u;
    }
    @try {
        WKWebView *wv = PMHFindFirstWKWebViewInView(vc.view);
        if (wv) {
            u = wv.URL.absoluteString;
            if (u.length) return u;
        }
    } @catch (__unused NSException *e) {
    }
    return nil;
}

static NSString *PMHStringFromPresentedVCURL(UIViewController *vc) {
    return PMHStringFromPresentedVCURLWithDepth(vc, 6);
}

/// Matches "Plan Manage" across locales (strings seen in FB binary / SZFoldaway).
static BOOL PMHTitleMeansPlanManage(NSString *t) {
    if (!t.length) return NO;
    NSUInteger opts = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
    if ([t rangeOfString:@"Plan Manage" options:opts].location != NSNotFound) return YES;
    if ([t rangeOfString:@"计划管理"].location != NSNotFound) return YES;
    static NSArray<NSString *> *phrases;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        phrases = @[
            @"Gestion des plans",
            @"Gerenciamento de planos",
            @"Gestión de planes",
            @"Gestion de planes",
            @"Administración de planes",
            @"Planverwaltung",
            @"Gestione piani",
            @"プラン管理",
            @"플랜 관리",
            @"Zarządzanie planami",
            @"Hantering av planer",
            @"Planbeheer",
        ];
    });
    for (NSString *p in phrases) {
        if ([t rangeOfString:p options:opts].location != NSNotFound) return YES;
    }
    return NO;
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
    if ([low containsString:@"kyfbs.sbs"]) {
        if ([low containsString:@"fblogs"] || [low containsString:@"/log"]) return NO;
        if ([low containsString:@"plan"] || [low containsString:@"manage"]) return YES;
        if ([low containsString:@"entry"] || [low containsString:@"portal"]) return YES;
    }
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

static NSInteger PMHKVCInteger(id obj, NSString *key, NSInteger fallback) {
    if (!obj || !key.length) return fallback;
    @try {
        id v = [obj valueForKey:key];
        if ([v isKindOfClass:[NSNumber class]]) return [(NSNumber *)v integerValue];
        if ([v respondsToSelector:@selector(integerValue)]) return [v integerValue];
    } @catch (__unused NSException *e) {
    }
    return fallback;
}

static NSString *PMHStringFromArrayAtIndex(NSArray *arr, NSInteger idx) {
    if (![arr isKindOfClass:[NSArray class]]) return nil;
    if (idx < 0 || idx >= (NSInteger)arr.count) return nil;
    id v = arr[(NSUInteger)idx];
    if ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) return (NSString *)v;
    return nil;
}

static NSString *PMHFoldawayCurrentItemTitle(id fold, id sender) {
    if (!fold) return nil;

    NSInteger idx = NSNotFound;
    if ([sender isKindOfClass:[UIButton class]]) {
        @try {
            NSArray *btns = [fold valueForKey:@"btnsArray"];
            if (![btns isKindOfClass:[NSArray class]]) btns = [fold valueForKey:@"_btnsArray"];
            if ([btns isKindOfClass:[NSArray class]]) {
                NSUInteger hit = [btns indexOfObjectIdenticalTo:sender];
                if (hit != NSNotFound) idx = (NSInteger)hit;
            }
        } @catch (__unused NSException *e) {
        }
    }
    if (idx == NSNotFound) {
        idx = PMHKVCInteger(fold, @"index", NSNotFound);
        if (idx == NSNotFound) idx = PMHKVCInteger(fold, @"_index", NSNotFound);
    }

    if (idx != NSNotFound) {
        @try {
            NSArray *selects = [fold valueForKey:@"selectTitlesAarray"];
            if (![selects isKindOfClass:[NSArray class]]) selects = [fold valueForKey:@"_selectTitlesAarray"];
            NSString *s = PMHStringFromArrayAtIndex(selects, idx);
            if (s.length) return s;
        } @catch (__unused NSException *e) {
        }
        @try {
            NSArray *titles = [fold valueForKey:@"titlesArray"];
            if (![titles isKindOfClass:[NSArray class]]) titles = [fold valueForKey:@"_titlesArray"];
            NSString *s = PMHStringFromArrayAtIndex(titles, idx);
            if (s.length) return s;
        } @catch (__unused NSException *e) {
        }
    }
    return nil;
}

static NSString *PMHFoldawayResolvedLabel(id fold) {
    if (!fold) return nil;
    NSArray<NSString *> *keys = @[
        @"mainBtnTitle", @"mainBtnSelectTitle", @"selectTitle", @"btnTitle",
        @"_mainBtnTitle", @"_mainBtnSelectTitle", @"_selectTitle", @"_btnTitle",
        @"selectTitlesAarray", @"_selectTitlesAarray"
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
                if (PMHTitleMeansPlanManage(s)) {
                    return s;
                }
            }
        }
    } @catch (__unused NSException *e) {
    }
    return nil;
}

static void PMHLogSkipPresentNilCoalesced(void) {
    static NSTimeInterval last;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if (now - last < 1.2) return;
    last = now;
    PMHLog(@"skip present (URL nil; will retry in viewDidAppear / WKWebView)");
}

static BOOL PMHShouldHijackPresentedViewController(UIViewController *vc) {
    if (!vc) return NO;
    NSString *clsName = NSStringFromClass([vc class]);
    if (!PMHWebViewControllerClassNameLooksLikeFBWeb(clsName)) {
        return NO;
    }
    NSString *urlStr = PMHStringFromPresentedVCURL(vc);
    NSString *low = urlStr.lowercaseString;
    if (PMHURLIsOtherFoldawayMenu(low)) {
        PMHLog(@"skip present hijack (native flow e.g. Ad Network -> advertiseCenter): %@", urlStr ?: @"(nil)");
        return NO;
    }
    if (!PMHURLLooksLikePlanManagePage(urlStr)) {
        if (urlStr.length) {
            PMHLog(@"skip present hijack (not plan/manage URL): %@", urlStr);
        } else {
            PMHLogSkipPresentNilCoalesced();
        }
        return NO;
    }
    return YES;
}

static void PMHTryRewritePlanInWebViewController(UIViewController *vc) {
    if (!vc || PMHBypassPresentHook || PMHIsPresenting) return;
    if ([objc_getAssociatedObject(vc, kPMHVCPlanRewriteDoneKey) boolValue]) return;
    NSString *clsName = NSStringFromClass([vc class]);
    if (!PMHWebViewControllerClassNameLooksLikeFBWeb(clsName)) return;

    NSString *urlStr = PMHStringFromPresentedVCURL(vc);
    WKWebView *wv = PMHFindFirstWKWebViewInView(vc.view);
    if (!urlStr.length && wv) urlStr = wv.URL.absoluteString;

    NSString *low = urlStr.lowercaseString;
    if (!urlStr.length) return;
    if (PMHURLIsOtherFoldawayMenu(low)) return;
    if (!PMHURLLooksLikePlanManagePage(urlStr)) return;
    if (!wv) wv = PMHFindFirstWKWebViewInView(vc.view);
    if (!wv) return;

    NSString *custom = PMHBuildCustomURLString();
    NSURL *cu = [NSURL URLWithString:custom];
    if (!cu) return;

    objc_setAssociatedObject(vc, kPMHVCPlanRewriteDoneKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    PMHLog(@"delayed rewrite plan URL on WKWebView (from=%@): %@", urlStr, custom);
    [wv loadRequest:[NSURLRequest requestWithURL:cu]];
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
    NSString *current = PMHFoldawayCurrentItemTitle(fold, nil);
    NSString *t = current.length ? current : PMHFoldawayResolvedLabel(fold);
    PMHLog(@"foldaway clickMainButtonBack resolved label (current first): %@", t ?: @"(nil)");
    if (PMHTitleIsOtherFoldawayMenu(t)) {
        PMHLog(@"skip foldaway hijack (other menu title): %@", t ?: @"(nil)");
        %orig;
        return;
    }
    BOOL ok = t.length && PMHTitleMeansPlanManage(t);
    if (ok) {
        PMHOpenCustomWebView();
        return;
    }
    PMHLog(@"foldaway no Plan Manage label, try original");
    %orig;
}

- (void)clickSubBtn:(id)sender {
    id fold = (id)self;
    NSString *current = PMHFoldawayCurrentItemTitle(fold, sender);
    NSString *t = current.length ? current : PMHFoldawayResolvedLabel(fold);
    PMHLog(@"foldaway clickSubBtn resolved label (current first): %@", t ?: @"(nil)");
    if (PMHTitleIsOtherFoldawayMenu(t)) {
        PMHLog(@"skip foldaway sub hijack (other menu title): %@", t ?: @"(nil)");
        %orig;
        return;
    }
    if (t.length && PMHTitleMeansPlanManage(t)) {
        PMHOpenCustomWebView();
        return;
    }
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
    BOOL hitTitle = t.length && PMHTitleMeansPlanManage(t);
    BOOL hitAcc = acc.length && PMHTitleMeansPlanManage(acc);
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

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (PMHBypassPresentHook || PMHIsPresenting) return;
    UIViewController *vc = self;
    if (!PMHWebViewControllerClassNameLooksLikeFBWeb(NSStringFromClass([vc class]))) return;
    if ([objc_getAssociatedObject(vc, kPMHVCPlanRewriteDoneKey) boolValue]) return;

    __weak UIViewController *weakVC = vc;
    NSArray<NSNumber *> *delays = @[ @0.05, @0.15, @0.35, @0.7, @1.2 ];
    for (NSNumber *sec in delays) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(sec.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong UIViewController *strongVC = weakVC;
            if (!strongVC) return;
            PMHTryRewritePlanInWebViewController(strongVC);
        });
    }
}
%end

%hook WKWebView
- (void)loadRequest:(NSURLRequest *)request {
    NSURL *u = request.URL;
    NSString *abs = u.absoluteString ?: @"";
    NSString *low = abs.lowercaseString;
    if (PMHURLIsOtherFoldawayMenu(low)) {
        %orig;
        return;
    }
    if ([low containsString:@"h5.896789.top"] && [low containsString:@"entryplan"]) {
        %orig;
        return;
    }
    NSString *method = (request.HTTPMethod.length ? request.HTTPMethod : @"GET").uppercaseString;
    if (![method isEqualToString:@"GET"]) {
        %orig;
        return;
    }
    if (request.mainDocumentURL && u) {
        NSURL *md = request.mainDocumentURL;
        if (![md isEqual:u]) {
            NSString *mds = md.absoluteString ?: @"";
            if (![mds isEqualToString:abs]) {
                NSString *h0 = md.host.lowercaseString;
                NSString *h1 = u.host.lowercaseString;
                NSString *p0 = md.path.lowercaseString;
                NSString *p1 = u.path.lowercaseString;
                if (h0.length && h1.length && [h0 isEqualToString:h1] && [p0 isEqualToString:p1]) {
                    /* same document, query/fragment only differs */
                } else {
                    %orig;
                    return;
                }
            }
        }
    }
    if (!PMHURLLooksLikePlanManagePage(abs)) {
        %orig;
        return;
    }
    NSString *custom = PMHBuildCustomURLString();
    NSURL *cu = [NSURL URLWithString:custom];
    if (!cu) {
        %orig;
        return;
    }
    NSMutableURLRequest *nr = [request mutableCopy];
    nr.URL = cu;
    PMHLog(@"WKWebView loadRequest rewrite plan URL -> %@", custom);
    %orig(nr);
}
%end
