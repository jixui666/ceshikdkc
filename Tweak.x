#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

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
    WKWebView *webView = [[WKWebView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;
    [webView loadRequest:[NSURLRequest requestWithURL:url]];

    UIViewController *topVC = PMHGetTopViewController();
    if (!topVC) return;

    UIViewController *vc = [UIViewController new];
    vc.view = webView;
    [topVC presentViewController:vc animated:YES completion:nil];
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
// 兜底按钮点击
// ----------------------------
%hook UIButton
- (void)sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    NSString *t = [self titleForState:0];
    if ([t containsString:@"Plan Manage"] || [t containsString:@"计划管理"]) {
        PMHOpenCustomWebView(@"https://www.baidu.com");
        return;
    }
    %orig;
}
%end