//
//  ComposeActionBlackListBehavior.m
//  Telegram
//
//  Created by keepcoder on 17.09.15.
//  Copyright (c) 2015 keepcoder. All rights reserved.
//

#import "ComposeActionBlackListBehavior.h"

@implementation ComposeActionBlackListBehavior

-(NSAttributedString *)centerTitle {
    
    
    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] init];
    
    if(self.action.result.multiObjects.count > 0) {
        
        [attr appendString:NSLocalizedString(@"Compose.Unban", nil) withColor:NSColorFromRGB(0x333333)];
        
        NSRange range = [attr appendString:[NSString stringWithFormat:@" - %lu/%lu",self.action.result.multiObjects.count,[self limit]] withColor:DARK_GRAY];
        
        [attr setFont:[NSFont fontWithName:@"HelveticaNeue" size:12] forRange:range];
        
        [attr setAlignment:NSCenterTextAlignment range:attr.range];
    } else {
        
        [attr appendString:NSLocalizedString(@"Compose.ChannelBlackList", nil) withColor:NSColorFromRGB(0x333333)];
        
        [attr setAlignment:NSCenterTextAlignment range:attr.range];
    }
    
    
    return attr;
}

-(NSString *)doneTitle {
    return NSLocalizedString(@"Compose.Unban", nil);
}

-(NSUInteger)limit {
    return 10;
}


-(TLChat *)chat {
    return self.action.object;
}

-(void)composeDidDone {
    [self.delegate behaviorDidStartRequest];
    
    [self unbanUsers:[self.action.result.multiObjects mutableCopy]];
}


-(void)unbanUsers:(NSMutableArray *)users {
    
    if(users.count > 0) {
        
        TLUser *user = users[0];
        
        [users removeObjectAtIndex:0];
        
        [RPCRequest sendRequest:[TLAPI_channels_kickFromChannel createWithChannel:self.chat.inputPeer user_id:user.inputUser kicked:NO] successHandler:^(id request, id response) {
            
            if(users.count == 0) {
                [self.delegate behaviorDidEndRequest:nil];
            }
            
        } errorHandler:^(id request, RpcError *error) {
            
            if(users.count > 0) {
                [self unbanUsers:users];
            } else {
                [self.delegate behaviorDidEndRequest:nil];
            }
            
        }];
    }
    

}

@end
