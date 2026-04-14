#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

static BOOL PMHIsPresenting = NO;

static BOOL PMHShouldHijackSelectorName(NSString *selName) {
    if (!selName.length) return NO;
    return [selName isEqualToString:@"clickBtn:"] ||
           [selName isEqualToString:@"clickSubBtn:"] ||
           [selName isEqualToString:@"mainBtnDown:"] ||
           [selName isEqualToString:@"mainBtnCancel:"] ||
           [selName isEqualToString:@"clickMainButtonBack"] ||
           [selName isEqualToString:@"clickSubButtonBack"];
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

    if (!targetWindow)
        targetWindow = [UIApplication sharedApplication].windows.firstObject;

    UIViewController *topVC = targetWindow.rootViewController;
    while (topVC.presentedViewController)
        topVC = topVC.presentedViewController;
    return topVC;
}

static void PMHOpenCustomWebView(NSString *urlString) {
    if (PMHIsPresenting) return;
    PMHIsPresenting = YES;

    WKWebView *webView = [[WKWebView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        PMHIsPresenting = NO;
        return;
    }
    [webView loadRequest:[NSURLRequest requestWithURL:url]];

    UIViewController *topVC = PMHGetTopViewController();
    if (!topVC) {
        PMHIsPresenting = NO;
        return;
    }

    UIViewController *vc = [UIViewController new];
    vc.view = webView;
    [topVC presentViewController:vc animated:YES completion:^{
        PMHIsPresenting = NO;
    }];
}

%config(generator=internal)

// ----------------------------
// 核心劫持：按钮类点击入口
// ----------------------------
%hook SZFoldawayButton

- (void)clickMainButtonBack {
    PMHOpenCustomWebView(@"https://www.baidu.com"); // <--- 改成你的网址
}

- (void)clickSubButtonBack {
    PMHOpenCustomWebView(@"https://www.baidu.com"); // <--- 改成你的网址
}

- (void)clickBtn:(id)arg {
    PMHOpenCustomWebView(@"https://www.baidu.com");
}

- (void)clickSubBtn:(id)arg {
    PMHOpenCustomWebView(@"https://www.baidu.com");
}

- (void)mainBtnDown:(id)arg {
    PMHOpenCustomWebView(@"https://www.baidu.com");
}

- (void)mainBtnCancel:(id)arg {
    PMHOpenCustomWebView(@"https://www.baidu.com");
}

%end

// ----------------------------
// 兜底 action 拦截（比 UIButton 更通用）
// ----------------------------
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
        PMHOpenCustomWebView(@"https://www.baidu.com");
        return;
    }
    %orig;
}
%end