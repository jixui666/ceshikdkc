#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

static UIViewController *PMHGetTopViewController(void) {
    UIWindow *targetWindow = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                if (window.isKeyWindow) {
                    targetWindow = window;
                    break;
                }
            }
            if (targetWindow) {
                break;
            }
        }
    }

    if (!targetWindow) {
        targetWindow = [UIApplication sharedApplication].windows.firstObject;
    }

    UIViewController *topVC = targetWindow.rootViewController;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    return topVC;
}

static void PMHOpenCustomWebView(NSString *urlString) {
    WKWebView *webView = [[WKWebView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        return;
    }
    [webView loadRequest:[NSURLRequest requestWithURL:url]];

    UIViewController *topVC = PMHGetTopViewController();
    if (!topVC) {
        return;
    }
    UIViewController *vc = [UIViewController new];
    vc.view = webView;
    [topVC presentViewController:vc animated:YES completion:nil];
}

%config(generator=internal)
%hook SZFoldawayButton

- (void)clickMainButtonBack {
    NSLog(@"[PlanManageHijack] 劫持成功！打开自定义网页");
    PMHOpenCustomWebView(@"https://www.baidu.com"); // <--- 改成你的网址
}

- (void)clickSubButtonBack {
    NSLog(@"[PlanManageHijack] 劫持子按钮");
    PMHOpenCustomWebView(@"https://www.baidu.com"); // <--- 改成你的网址
}

%end

// 兜底保护：只要按钮文字是 Plan Manage 就劫持
%hook UIButton
- (void)sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    NSString *title = [self titleForState:0];
    if ([title containsString:@"Plan Manage"] || [title containsString:@"计划管理"]) {
        PMHOpenCustomWebView(@"https://www.baidu.com");
        return;
    }
    %orig;
}
%end