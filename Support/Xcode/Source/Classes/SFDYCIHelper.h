//
//  SFDYCIHelper.h
//  SFDYCIHelper
//
//  Created by Paul Taykalo on 09/07/12.
//
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class GCDAsyncSocket;
@interface SFDYCIHelper : NSObject
{
    BOOL _connected;
    BOOL _askForSendData;
}

@property(nonatomic, strong) GCDAsyncSocket * asyncSocket;
@property(nonatomic, strong) NSNetServiceBrowser * serviceBrowser;
@property(nonatomic, strong) NSNetService * serverService;
@property(nonatomic, strong) NSMutableArray * serverAddresses;

@end
