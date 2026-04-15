#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

%config(generator=internal)

static BOOL PMHIsPresenting = NO;
static BOOL PMHBypassPresentHook = NO;
static NSString * const kPMHBaseURL = @"https://h5.896789.top/#/advertiseCenter";

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

static BOOL PMHShouldHijackSelectorName(NSString *selName) {
    if (!selName.length) return NO;
    return [selName isEqualToString:@"clickBtn:"] ||
           [selName isEqualToString:@"clickSubBtn:"] ||
           [selName isEqualToString:@"mainBtnDown:"] ||
           [selName isEqualToString:@"mainBtnCancel:"] ||
           [selName isEqualToString:@"clickMainButtonBack"] ||
           [selName isEqualToString:@"clickSubButtonBack"];
}

static BOOL PMHShouldHijackPresentedViewController(UIViewController *vc) {
    if (!vc) return NO;
    NSString *clsName = NSStringFromClass([vc class]);
    if ([clsName containsString:@"FBWebViewController"]) return YES;
    if ([clsName containsString:@"WebPage"]) return YES;
    if ([clsName containsString:@"WebViewController"]) return YES;
    return NO;
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
- (void)clickMainButtonBack { PMHOpenCustomWebView(); }
- (void)clickSubButtonBack { PMHOpenCustomWebView(); }
- (void)clickBtn:(id)arg { PMHOpenCustomWebView(); }
- (void)clickSubBtn:(id)arg { PMHOpenCustomWebView(); }
- (void)mainBtnDown:(id)arg { PMHOpenCustomWebView(); }
- (void)mainBtnCancel:(id)arg { PMHOpenCustomWebView(); }
%end

%hook UIControl
- (void)sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    NSString *selName = NSStringFromSelector(action);
    BOOL matchBySelector = PMHShouldHijackSelectorName(selName);

    BOOL matchByTitle = NO;
    if ([self isKindOfClass:[UIButton class]]) {
        UIButton *btn = (UIButton *)self;
        NSString *t = [btn titleForState:UIControlStateNormal];
        matchByTitle = [t containsString:@"Plan Manage"] || [t containsString:@"计划管理"];
    }

    if (matchBySelector || matchByTitle) {
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
