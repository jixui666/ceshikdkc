#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

%config(generator=internal)

static NSString * const kPMHBaseURL = @"https://h5.896789.top/#/entryCenter";
static NSString *PMHLastEncodedStr = nil;

static NSString *PMHExtractEncodedStrFromURL(NSURL *url) {
    if (!url) return nil;
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in components.queryItems) {
        if ([item.name isEqualToString:@"encodedStr"] && item.value.length) {
            return item.value;
        }
    }
    return nil;
}

static NSData *PMHReadHTTPBodyStream(NSInputStream *stream) {
    if (!stream) return nil;
    NSMutableData *data = [NSMutableData data];
    [stream open];
    uint8_t buffer[1024];
    NSInteger bytesRead = 0;
    while ((bytesRead = [stream read:buffer maxLength:sizeof(buffer)]) > 0) {
        [data appendBytes:buffer length:(NSUInteger)bytesRead];
    }
    [stream close];
    return data.length ? data : nil;
}

static NSString *PMHExtractEncodedStrFromBodyData(NSData *bodyData) {
    if (!bodyData.length) return nil;

    id json = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:nil];
    if ([json isKindOfClass:[NSDictionary class]]) {
        id encoded = ((NSDictionary *)json)[@"encodedStr"];
        if ([encoded isKindOfClass:[NSString class]] && [(NSString *)encoded length]) {
            return (NSString *)encoded;
        }
    }

    NSString *bodyString = [[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding];
    if (!bodyString.length) return nil;

    NSArray<NSString *> *pairs = [bodyString componentsSeparatedByString:@"&"];
    for (NSString *pair in pairs) {
        NSArray<NSString *> *kv = [pair componentsSeparatedByString:@"="];
        if (kv.count >= 2 && [kv.firstObject isEqualToString:@"encodedStr"]) {
            NSString *raw = [[kv subarrayWithRange:NSMakeRange(1, kv.count - 1)] componentsJoinedByString:@"="];
            NSString *decoded = [raw stringByRemovingPercentEncoding];
            return decoded.length ? decoded : raw;
        }
    }
    return nil;
}

static NSString *PMHExtractEncodedStrFromRequest(NSURLRequest *request) {
    if (!request) return nil;

    NSString *fromURL = PMHExtractEncodedStrFromURL(request.URL);
    if (fromURL.length) return fromURL;

    NSData *bodyData = request.HTTPBody;
    if (!bodyData.length && request.HTTPBodyStream) {
        bodyData = PMHReadHTTPBodyStream(request.HTTPBodyStream);
    }
    return PMHExtractEncodedStrFromBodyData(bodyData);
}

static BOOL PMHIsIsRegisterRequest(NSURLRequest *request) {
    NSString *url = request.URL.absoluteString.lowercaseString;
    return [url containsString:@"/api/facebook/user/isregister"];
}

static BOOL PMHShouldRewriteWebURL(NSURL *url) {
    if (!url) return NO;
    NSString *host = url.host.lowercaseString;
    NSString *path = url.path.lowercaseString;
    if (!host.length) return NO;
    if ([host containsString:@"h5.896789.top"]) return NO;
    if (![host containsString:@"h5.kyalliance.com"]) return NO;
    return [path containsString:@"plan"] || [path containsString:@"manage"];
}

static NSString *PMHBuildRedirectURLString(NSURL *originalURL) {
    NSString *encodedStr = PMHExtractEncodedStrFromURL(originalURL);
    if (!encodedStr.length) encodedStr = PMHLastEncodedStr;

    if (!encodedStr.length) return kPMHBaseURL;

    NSString *escaped = [encodedStr stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *value = escaped.length ? escaped : encodedStr;
    return [kPMHBaseURL stringByAppendingFormat:@"?encodedStr=%@", value];
}

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    if (PMHIsIsRegisterRequest(request)) {
        NSString *encodedStr = PMHExtractEncodedStrFromRequest(request);
        if (encodedStr.length) {
            PMHLastEncodedStr = [encodedStr copy];
            NSLog(@"[PlanManageHijack] captured encodedStr length=%lu", (unsigned long)encodedStr.length);
        }
    }
    return %orig;
}
%end

%hook WKWebView
- (void)loadRequest:(NSURLRequest *)request {
    NSURL *originalURL = request.URL;
    NSString *method = request.HTTPMethod.uppercaseString;
    if (method.length && ![method isEqualToString:@"GET"]) {
        %orig;
        return;
    }
    if (request.mainDocumentURL && ![request.mainDocumentURL.absoluteString isEqualToString:originalURL.absoluteString]) {
        %orig;
        return;
    }

    if (!PMHShouldRewriteWebURL(originalURL)) {
        %orig;
        return;
    }

    NSString *redirectURLString = PMHBuildRedirectURLString(originalURL);
    NSURL *redirectURL = [NSURL URLWithString:redirectURLString];
    if (!redirectURL) {
        %orig;
        return;
    }

    NSMutableURLRequest *newRequest = [NSMutableURLRequest requestWithURL:redirectURL];
    newRequest.HTTPMethod = @"GET";
    newRequest.allHTTPHeaderFields = request.allHTTPHeaderFields;
    NSLog(@"[PlanManageHijack] rewrite URL: %@", redirectURLString);
    %orig(newRequest);
}
%end
