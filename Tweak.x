#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

%config(generator=internal)
%hook SZFoldawayButton

- (void)clickMainButtonBack {
    NSLog(@"[PlanManageHijack] 劫持成功！打开自定义网页");
    [self openCustomWebView:@"https://www.baidu.com"]; // <--- 改成你的网址
}

- (void)clickSubButtonBack {
    NSLog(@"[PlanManageHijack] 劫持子按钮");
    [self openCustomWebView:@"https://www.baidu.com"]; // <--- 改成你的网址
}

- (void)openCustomWebView:(NSString *)urlString {
    WKWebView *webView = [[WKWebView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    NSURL *url = [NSURL URLWithString:urlString];
    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    [webView loadRequest:req];

    UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }

    UIViewController *vc = [[UIViewController alloc] init];
    vc.view = webView;
    [topVC presentViewController:vc animated:YES completion:nil];
}

%end

// 兜底保护：只要按钮文字是 Plan Manage 就劫持
%hook UIButton
- (void)sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    NSString *title = [self titleForState:0];
    if ([title containsString:@"Plan Manage"] || [title containsString:@"计划管理"]) {
        WKWebView *webView = [[WKWebView alloc] initWithFrame:[UIScreen mainScreen].bounds];
        [webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://www.baidu.com"]]];
        
        UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (topVC.presentedViewController) topVC = topVC.presentedViewController;
        UIViewController *vc = [UIViewController new];
        vc.view = webView;
        [topVC presentViewController:vc animated:YES completion:nil];
        return;
    }
    %orig;
}
%end