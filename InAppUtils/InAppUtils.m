#import "InAppUtils.h"
#import <StoreKit/StoreKit.h>
#import <React/RCTLog.h>
#import <React/RCTUtils.h>
#import "SKProduct+StringPrice.h"

@implementation InAppUtils
{
    NSArray *products;
    NSMutableDictionary *promisesByKey;
}

- (instancetype)init
{
    if ((self = [super init])) {
        promisesByKey = [NSMutableDictionary dictionary];
        [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
    }
    return self;
}

+ (BOOL)requiresMainQueueSetup {
    return YES;
}

- (void)addPromiseForKey:(NSString*)key resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
    NSMutableArray* promises = [promisesByKey valueForKey:key];
    
    if (promises == nil) {
        promises = [NSMutableArray array];
        [promisesByKey setValue:promises forKey:key];
    }
    
    [promises addObject:@[resolve, reject]];
}

- (void)resolvePromisesForKey:(NSString*)key value:(id)value {
    NSMutableArray* promises = [promisesByKey valueForKey:key];

    if (promises != nil) {
        for (NSMutableArray *tuple in promises) {
            RCTPromiseResolveBlock resolve = tuple[0];
            resolve(value);
        }
        [promisesByKey removeObjectForKey:key];
    }
}

- (void)rejectPromisesForKey:(NSString*)key code:(NSString*)code message:(NSString*)message error:(NSError*) error {
    NSMutableArray* promises = [promisesByKey valueForKey:key];

    if (promises != nil) {
        for (NSMutableArray *tuple in promises) {
            RCTPromiseRejectBlock reject = tuple[1];
            reject(code, message, error);
        }
        [promisesByKey removeObjectForKey:key];
    }
}

RCT_EXPORT_MODULE();

- (void) paymentQueue:(SKPaymentQueue *)queue
  updatedTransactions:(NSArray *)transactions
{
    for (SKPaymentTransaction *transaction in transactions) {
        switch (transaction.transactionState) {
            case SKPaymentTransactionStateFailed: {
                NSString *key = transaction.payment.productIdentifier;
                NSString *code = [NSString stringWithFormat:@"%ld", transaction.error.code];
                [self rejectPromisesForKey:key code:code message:transaction.error.localizedDescription error:transaction.error];
                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                break;
            }
            case SKPaymentTransactionStatePurchased: {
                NSString *key = transaction.payment.productIdentifier;
                NSDictionary *purchase = [self getPurchaseData:transaction];
                [self resolvePromisesForKey:key value:purchase];
                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                break;
            }
            case SKPaymentTransactionStateRestored:
                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                break;
            case SKPaymentTransactionStatePurchasing:
                NSLog(@"purchasing");
                break;
            case SKPaymentTransactionStateDeferred:
                NSLog(@"deferred");
                break;
            default:
                break;
        }
    }
}

RCT_EXPORT_METHOD(purchaseProductForUser:(NSString *)productIdentifier username:(NSString *)username
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
    [self doPurchaseProduct:productIdentifier username:username resolve:resolve reject:reject];
}

RCT_EXPORT_METHOD(purchaseProduct:(NSString *)productIdentifier
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
    [self doPurchaseProduct:productIdentifier username:nil resolve:resolve reject:reject];
}

- (void) doPurchaseProduct:(NSString *)productIdentifier
                  username:(NSString *)username
                   resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject
{
    SKProduct *product;
    for(SKProduct *p in products)
    {
        if([productIdentifier isEqualToString:p.productIdentifier]) {
            product = p;
            break;
        }
    }

    if(product) {
        SKMutablePayment *payment = [SKMutablePayment paymentWithProduct:product];
        if(username) {
            payment.applicationUsername = username;
        }
        [[SKPaymentQueue defaultQueue] addPayment:payment];
        [self addPromiseForKey:payment.productIdentifier resolve:resolve reject:reject];
    } else {
        reject(@"invalid_product", @"Invalid product", nil);
    }
}

- (void)paymentQueue:(SKPaymentQueue *)queue
restoreCompletedTransactionsFailedWithError:(NSError *)error
{
    NSString *key = @"restoreRequest";
    NSString *code = [NSString stringWithFormat:@"%ld", error.code];
    [self rejectPromisesForKey:key code:code message:error.localizedDescription error:error];
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue
{
    NSString *key = @"restoreRequest";
    
    NSMutableArray *productsArrayForJS = [NSMutableArray array];
    for(SKPaymentTransaction *transaction in queue.transactions){
        if(transaction.transactionState == SKPaymentTransactionStateRestored) {

            NSDictionary *purchase = [self getPurchaseData:transaction];

            [productsArrayForJS addObject:purchase];
            [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
        }
    }
    
    [self resolvePromisesForKey:key value:productsArrayForJS];
}

RCT_EXPORT_METHOD(restorePurchases:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
    [self addPromiseForKey:@"restoreRequest" resolve:resolve reject:reject];
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

RCT_EXPORT_METHOD(restorePurchasesForUser:(NSString *)username
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
    if(!username) {
        reject(@"no_username", @"Username required", nil);
        return;
    }
    
    [self addPromiseForKey:@"restoreRequest" resolve:resolve reject:reject];
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

RCT_EXPORT_METHOD(loadProducts:(NSArray *)productIdentifiers
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
    SKProductsRequest *productsRequest = [[SKProductsRequest alloc]
                                          initWithProductIdentifiers:[NSSet setWithArray:productIdentifiers]];
    
    NSString *key = RCTKeyForInstance(productsRequest);
    [self addPromiseForKey:key resolve:resolve reject:reject];
    
    productsRequest.delegate = self;
    [productsRequest start];
}

RCT_EXPORT_METHOD(canMakePayments:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
    BOOL canMakePayments = [SKPaymentQueue canMakePayments];
    resolve(@(canMakePayments));
}

RCT_EXPORT_METHOD(receiptData:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
    NSString *receipt = [self grandUnifiedReceipt];
    if (receipt == nil) {
        reject(@"no_receipt", @"No receipt", nil);
    } else {
        resolve(receipt);
    }
}

// Fetch Grand Unified Receipt
- (NSString *)grandUnifiedReceipt
{
    NSURL *receiptUrl = [[NSBundle mainBundle] appStoreReceiptURL];
    NSData *receiptData = [NSData dataWithContentsOfURL:receiptUrl];
    if (!receiptData) {
        return nil;
    } else {
        return [receiptData base64EncodedStringWithOptions:0];
    }
}

// SKProductsRequestDelegate protocol method
- (void)productsRequest:(SKProductsRequest *)request
     didReceiveResponse:(SKProductsResponse *)response
{
    NSString *key = RCTKeyForInstance(request);
   
    products = [NSMutableArray arrayWithArray:response.products];
    NSMutableArray *productsArrayForJS = [NSMutableArray array];
    for(SKProduct *item in response.products) {
        NSDictionary *product = @{
            @"identifier": item.productIdentifier,
            @"price": item.price,
            @"currencySymbol": [item.priceLocale objectForKey:NSLocaleCurrencySymbol],
            @"currencyCode": [item.priceLocale objectForKey:NSLocaleCurrencyCode],
            @"priceString": item.priceString,
            @"countryCode": [item.priceLocale objectForKey: NSLocaleCountryCode],
            @"downloadable": item.isDownloadable ? @"true" : @"false" ,
            @"description": item.localizedDescription ? item.localizedDescription : @"",
            @"title": item.localizedTitle ? item.localizedTitle : @"",
        };
        [productsArrayForJS addObject:product];
    }
    
    [self resolvePromisesForKey:key value:productsArrayForJS];
}

// SKProductsRequestDelegate network error
- (void)request:(SKRequest *)request didFailWithError:(NSError *)error{
    NSString *key = RCTKeyForInstance(request);
    NSString *code = [NSString stringWithFormat:@"%ld", error.code];
    
    [self rejectPromisesForKey:key code:code message:error.localizedDescription error:error];
}

- (NSDictionary *)getPurchaseData:(SKPaymentTransaction *)transaction {
    NSMutableDictionary *purchase = [NSMutableDictionary dictionaryWithDictionary: @{
        @"transactionDate": @(transaction.transactionDate.timeIntervalSince1970 * 1000),
        @"transactionIdentifier": transaction.transactionIdentifier,
        @"productIdentifier": transaction.payment.productIdentifier,
        @"transactionReceipt": [self grandUnifiedReceipt]
    }];
    // originalTransaction is available for restore purchase and purchase of cancelled/expired subscriptions
    SKPaymentTransaction *originalTransaction = transaction.originalTransaction;
    if (originalTransaction) {
        purchase[@"originalTransactionDate"] = @(originalTransaction.transactionDate.timeIntervalSince1970 * 1000);
        purchase[@"originalTransactionIdentifier"] = originalTransaction.transactionIdentifier;
    }

    return purchase;
}

- (void)dealloc
{
    [[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
}

#pragma mark Private

static NSString *RCTKeyForInstance(id instance)
{
    return [NSString stringWithFormat:@"%p", instance];
}

@end
