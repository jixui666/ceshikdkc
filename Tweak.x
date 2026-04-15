#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

%config(generator=internal)

static BOOL PMHIsPresenting = NO;
static BOOL PMHBypassPresentHook = NO;
static NSString * const kPMHBaseURL = @"https://h5.896789.top/#/entryCenter";

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

static NSString *PMHBuildEncodedStrFromPlistDictionary(NSDictionary *dict) {
    if (!dict.count) return nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
    if (!jsonData.length) return nil;
    return [jsonData base64EncodedStringWithOptions:0];
}

static NSString *PMHLoadEncodedStrFromUserInfoPlist(void) {
    NSArray<NSString *> *candidates = @[
        [NSHomeDirectory() stringByAppendingPathComponent:@"user_info.plist"],
        [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/user_info.plist"],
        [NSHomeDirectory() stringByAppendingPathComponent:@"Library/user_info.plist"]
    ];

    for (NSString *path in candidates) {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
        NSString *encoded = PMHBuildEncodedStrFromPlistDictionary(dict);
        if (encoded.length) {
            PMHLog(@"loaded user_info.plist: %@ (len=%lu)", path, (unsigned long)encoded.length);
            return encoded;
        }
    }
    PMHLog(@"user_info.plist not found or invalid");
    return nil;
}

static NSString *PMHBuildCustomURLString(void) {
    NSString *encodedStr = PMHLoadEncodedStrFromUserInfoPlist();
    if (!encodedStr.length) return kPMHBaseURL;

    NSURLComponents *components = [NSURLComponents componentsWithString:kPMHBaseURL];
    if (!components) return kPMHBaseURL;
    components.queryItems = @[[NSURLQueryItem queryItemWithName:@"encodedStr" value:encodedStr]];
    return components.string ?: kPMHBaseURL;
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
