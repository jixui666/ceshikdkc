#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/message.h>

static NSString * const kPMHBaseURL = @"https://h5.896789.top/#/entryCenter?";
static BOOL PMHIsPresenting = NO;
static BOOL PMHBypassPresentHook = NO;

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

static NSString *PMHBuildCustomURLString(NSString *originalURLString) {
    if (!originalURLString.length) return kPMHBaseURL;

    NSURLComponents *components = [NSURLComponents componentsWithString:originalURLString];
    NSString *query = components.query;
    if (!query.length) return kPMHBaseURL;

    if ([kPMHBaseURL hasSuffix:@"?"] || [kPMHBaseURL hasSuffix:@"&"]) {
        return [kPMHBaseURL stringByAppendingString:query];
    }
    return [kPMHBaseURL stringByAppendingFormat:@"&%@", query];
}

static NSString *PMHExtractURLStringFromValue(id value) {
    if (!value) return nil;
    if ([value isKindOfClass:[NSURL class]]) return [(NSURL *)value absoluteString];
    if ([value isKindOfClass:[NSURLRequest class]]) return [(NSURLRequest *)value.URL absoluteString];
    if ([value isKindOfClass:[NSString class]]) return (NSString *)value;
    return nil;
}

static NSString *PMHExtractOriginalURLStringFromPresentedVC(UIViewController *vc) {
    if (!vc) return nil;

    SEL selectors[] = { @selector(URL), @selector(url), @selector(request) };
    for (NSUInteger i = 0; i < sizeof(selectors) / sizeof(SEL); i++) {
        SEL sel = selectors[i];
        if ([vc respondsToSelector:sel]) {
            id value = ((id (*)(id, SEL))objc_msgSend)(vc, sel);
            NSString *urlString = PMHExtractURLStringFromValue(value);
            if (urlString.length) return urlString;
        }
    }

    if ([vc respondsToSelector:@selector(webView)]) {
        id webViewObj = ((id (*)(id, SEL))objc_msgSend)(vc, @selector(webView));
        if ([webViewObj isKindOfClass:[WKWebView class]]) {
            NSString *urlString = ((WKWebView *)webViewObj).URL.absoluteString;
            if (urlString.length) return urlString;
        }
    }

    return nil;
}

static void PMHOpenCustomWebView(NSString *originalURLString) {
    if (PMHIsPresenting) return;
    PMHIsPresenting = YES;

    NSString *customURLString = PMHBuildCustomURLString(originalURLString);
    NSURL *url = [NSURL URLWithString:customURLString];
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
}

%config(generator=internal)

%hook SZFoldawayButton
- (void)clickMainButtonBack { PMHOpenCustomWebView(nil); }
- (void)clickSubButtonBack { PMHOpenCustomWebView(nil); }
- (void)clickBtn:(id)arg { PMHOpenCustomWebView(nil); }
- (void)clickSubBtn:(id)arg { PMHOpenCustomWebView(nil); }
- (void)mainBtnDown:(id)arg { PMHOpenCustomWebView(nil); }
- (void)mainBtnCancel:(id)arg { PMHOpenCustomWebView(nil); }
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
        PMHOpenCustomWebView(nil);
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
        NSString *originalURLString = PMHExtractOriginalURLStringFromPresentedVC(viewControllerToPresent);
        PMHOpenCustomWebView(originalURLString);
        return;
    }
    %orig;
}
%end