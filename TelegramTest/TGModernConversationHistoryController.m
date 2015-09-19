//
//  TGModernConversationHistoryController.m
//  Telegram
//
//  Created by keepcoder on 24.08.15.
//  Copyright (c) 2015 keepcoder. All rights reserved.
//

#import "TGModernConversationHistoryController.h"
#import "TGObservableObject.h"

#import "TLPeer+Extensions.h"

static NSString *kYapChannelCollection = @"channels_keys";
static NSString *kYapChannelKey = @"channels_is_loaded";
@interface TGChannelsLoader : TGObservableObject

@property (nonatomic,assign,readonly) BOOL channelsIsLoaded;

@end


@implementation TGChannelsLoader

-(void)loadChannelsOnQueue:(ASQueue *)queue {
    
    [self loadNext:0 result:@[] onQueue:queue];
    
}

-(instancetype)initWithQueue:(ASQueue *)queue {
    if(self = [super init]) {
        
        __block BOOL isNeedRemoteLoading;
        
        [[Storage yap] readWithBlock:^(YapDatabaseReadTransaction * __nonnull transaction) {
            
            isNeedRemoteLoading = ![[transaction objectForKey:kYapChannelKey inCollection:kYapChannelCollection] boolValue];
            
        }];
        
        [Notification addObserver:self selector:@selector(logout:) name:LOGOUT_EVENT];
        
        if(isNeedRemoteLoading)
            [self loadChannelsOnQueue:queue];
        else
            [[Storage manager] allChannels:^(NSArray *channels, NSArray *messages) {
                
                _channelsIsLoaded = YES;
                
                [[ChannelsManager sharedManager] add:channels];
                
                [self notifyListenersWithObject:channels];
                
            } deliveryOnQueue:queue];
        
    }
    
    return self;
}

-(void)logout:(NSNotification *)notification {
    _channelsIsLoaded = NO;
}

static const int limit = 1000;

-(void)loadNext:(int)offset result:(NSArray *)result onQueue:(ASQueue *)queue{
    
    [RPCRequest sendRequest:[TLAPI_channels_getDialogs createWithOffset:offset limit:limit] successHandler:^(id request, TL_messages_dialogs *response) {
        
         [SharedManager proccessGlobalResponse:response];
        
        
        NSMutableArray *converted = [[NSMutableArray alloc] initWithCapacity:response.dialogs.count];
        
        
        
        
   //     assert(response.dialogs.count == response.messages.count);
        
        
        [response.dialogs enumerateObjectsUsingBlock:^(TL_dialogChannel *channel, NSUInteger idx, BOOL *stop) {
            
            NSArray *f = [response.messages filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self.peer_id == %d", channel.peer.peer_id]];
            
            
            assert(f.count > 0);
            
            __block TL_localMessage *topMsg;
            __block TL_localMessage *minMsg;
            
            [f enumerateObjectsUsingBlock:^(TL_localMessage *obj, NSUInteger idx, BOOL *stop) {
                
                if(channel.top_message == obj.n_id)
                    topMsg = obj;
                
                if(!minMsg || obj.n_id < minMsg.n_id)
                    minMsg = obj;
                
            }];
            
           
            
            if(minMsg.n_id == 1 ) {
                int bp = 0;
            }
            
            if(f.count == 2) {
                
                if(minMsg.n_id != topMsg.n_id) {
                    TGMessageHole *hole = [[TGMessageHole alloc] initWithUniqueId:-rand_int() peer_id:minMsg.peer_id min_id:minMsg.n_id max_id:topMsg.n_id date:minMsg.date count:0];
                    
                    [[Storage manager] insertMessagesHole:hole];
                }
                
                // hole
                
                
                // need create group hole
                
                TGMessageGroupHole *groupHole = [[TGMessageGroupHole alloc] initWithUniqueId:-rand_int() peer_id:topMsg.peer_id min_id:minMsg.n_id max_id:topMsg.n_id+1 date:INT32_MAX count:0];
                
                [[Storage manager] insertMessagesHole:groupHole];
                
            }
            
            
            [converted addObject:[TL_conversation createWithPeer:channel.peer top_message:channel.top_message unread_count:channel.unread_important_count last_message_date:topMsg.date notify_settings:channel.notify_settings last_marked_message:channel.top_message top_message_fake:channel.top_message last_marked_date:topMsg.date sync_message_id:topMsg.n_id read_inbox_max_id:channel.read_inbox_max_id unread_important_count:channel.unread_important_count lastMessage:minMsg pts:channel.pts isInvisibleChannel:NO top_important_message:minMsg.n_id]];
            
            
            if(minMsg == nil) {
                int bp = 0;
            }
            
        }];
        
        
        NSArray *join = [result arrayByAddingObjectsFromArray:converted];
        
        if(converted.count < limit) {
            [self saveResults:join onQueue:queue];
        }
        
        else
            [self loadNext:(int) join.count result:join onQueue:queue];
            
        
    } errorHandler:^(id request, RpcError *error) {
        
    } timeout:0 queue:queue.nativeQueue];
    
    
}

-(void)saveResults:(NSArray *)channels onQueue:(ASQueue *)queue {
    [queue dispatchOnQueue:^{
        
        
        _channelsIsLoaded = YES;
        
        [[ChannelsManager sharedManager] add:channels];
        
        [self notifyListenersWithObject:channels];
        
        [[Storage manager] insertChannels:channels completionHandler:^{
            
            [[Storage yap] readWriteWithBlock:^(YapDatabaseReadWriteTransaction * __nonnull transaction) {
                [transaction setObject:@(YES) forKey:kYapChannelKey inCollection:kYapChannelCollection];
            }];
            
        } deliveryOnQueue:queue];
        
        
    }];
    
}

@end

@interface TGModernConversationHistoryController () <TGObservableDelegate>
@property (nonatomic,strong) ASQueue *queue;
@property (nonatomic,weak) id<TGModernConversationHistoryControllerDelegate> delegate;
@property (nonatomic,assign) BOOL loadNextAfterLoadChannels;
@property (nonatomic,assign) int channelsOffset;
@end

@implementation TGModernConversationHistoryController




static TGChannelsLoader *channelsLoader;
static BOOL isStorageLoaded;

-(id)initWithQueue:(ASQueue *)queue delegate:(id<TGModernConversationHistoryControllerDelegate>)deleagte {
    
    if(self = [super init]) {
        _queue = queue;
        
        [queue dispatchOnQueue:^{
            
            _delegate = deleagte;
            
           
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                channelsLoader = [[TGChannelsLoader alloc] initWithQueue:queue];
            });
            
            
            [channelsLoader addWeakEventListener:self];
            
            
            _state = isStorageLoaded ? TGModernCHStateCache : TGModernCHStateLocal;
            
        } synchronous:YES];
        

         
        
    }
    
    return self;
}
         
-(void)dealloc {
    [channelsLoader removeEventListener:self];
}


-(void)didChangedEventStateWithObject:(id)object {
   
    if(_loadNextAfterLoadChannels)
        [self performLoadNext];
    
}

-(void)requestNextConversation {
    
    [_queue dispatchOnQueue:^{
        
        if(_isLoading)
            return;
        
        _isLoading = YES;
        
        if(!channelsLoader.channelsIsLoaded)
            _loadNextAfterLoadChannels = YES;
        else
            [self performLoadNext];
            
        
    }];
    

}

-(void)performLoadNext {
    
    if(_state == TGModernCHStateLocal)
    {
        [[Storage manager] dialogsWithOffset:0 limit:10000 completeHandler:^(NSArray *d, NSArray *m) {
            
            [[DialogsManager sharedManager] add:d];
            
            [_queue dispatchOnQueue:^{
                
                isStorageLoaded = YES;
                
                _state = TGModernCHStateCache;
                
                [self performLoadNext];
                
            }];
            
            
        }];
    } else if(_state == TGModernCHStateCache) {
        NSArray *all = [[DialogsManager sharedManager] all];
        
        BOOL needDispatch = all.count > 0;
        
        [[DialogsManager sharedManager] add:[[ChannelsManager sharedManager] all]];
        
        if(_offset >= all.count || !needDispatch) {
            _state = TGModernCHStateRemote;
            [self performLoadNext];
            return;
        }
        
        [self dispatchWithFullList:all];
        
        
    } else if(_state == TGModernCHStateRemote) {
        
        int remoteOffset = (int) [[[[DialogsManager sharedManager] all] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self.type != 4 && self.type != 3 && self.type != 2"]] count];
        
        [RPCRequest sendRequest:[TLAPI_messages_getDialogs createWithOffset:remoteOffset limit:[_delegate conversationsLoadingLimit]] successHandler:^(id request, TL_messages_dialogs *response) {
            
            
            if([response isKindOfClass:[TL_messages_dialogsSlice class]] && remoteOffset == response.n_count)
                return;
            
            [SharedManager proccessGlobalResponse:response];
            
            
            NSMutableArray *converted = [[NSMutableArray alloc] init];
           
            [response.dialogs enumerateObjectsUsingBlock:^(TL_dialog *dialog, NSUInteger idx, BOOL *stop) {
                
                TL_localMessage *msg = [TL_localMessage convertReceivedMessage:[[response.messages filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self.n_id == %d",dialog.top_message]] firstObject]];
                
                [converted addObject:[TL_conversation createWithPeer:dialog.peer top_message:dialog.top_message unread_count:dialog.unread_count last_message_date:msg.date notify_settings:dialog.notify_settings last_marked_message:dialog.top_message top_message_fake:dialog.top_message last_marked_date:msg.date sync_message_id:msg.n_id read_inbox_max_id:dialog.read_inbox_max_id unread_important_count:dialog.unread_important_count lastMessage:msg pts:dialog.pts isInvisibleChannel:NO top_important_message:dialog.top_important_message]];
                
            }];
            
            
            [[DialogsManager sharedManager] add:converted];
            [[Storage manager] insertDialogs:converted completeHandler:nil];
            
            [MessagesManager updateUnreadBadge];
            
            if(converted.count < [_delegate conversationsLoadingLimit])
                _state = TGModernCHStateFull;
            
            
            [self dispatchWithFullList:[[DialogsManager sharedManager] all]];
            
            
            
        } errorHandler:^(id request, RpcError *error) {
            
            
            
        } timeout:0 queue:_queue.nativeQueue];
        
    }

}

- (NSArray *)mixChannelsWithConversations:(NSArray *)channels conversations:(NSArray *)conversations {
    
    NSArray *join = [channels arrayByAddingObjectsFromArray:conversations];
    
    return [join sortedArrayUsingComparator:^NSComparisonResult(TL_conversation * obj1, TL_conversation * obj2) {
        return (obj1.last_real_message_date < obj2.last_real_message_date ? NSOrderedDescending : (obj1.last_real_message_date > obj2.last_real_message_date ? NSOrderedAscending : (obj1.top_message < obj2.top_message ? NSOrderedDescending : NSOrderedAscending)));
    }];
    
}

-(void)dispatchWithFullList:(NSArray *)all {
    
    
    NSArray *mixed = [self mixChannelsWithConversations:@[] conversations:all];
    

//    [mixed enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(TL_conversation *obj, NSUInteger idx, BOOL *stop) {
//        
//        if(obj.type != DialogTypeChannel) {
//            lastIndex = idx+1;
//            *stop = YES;
//        }
//        
//    }];
//    
//    
//    
    mixed = [mixed subarrayWithRange:NSMakeRange(_offset, MIN([self.delegate conversationsLoadingLimit],mixed.count - _offset))];
//    
//    NSArray *channels = [mixed filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self.type == 4"]];
//    
//    NSUInteger channelsOffsetCount = [channels count];
//    
//    [[DialogsManager sharedManager] add:channels];
//   
    NSRange range = NSMakeRange(_offset, mixed.count);
    
    [_delegate didLoadedConversations:mixed withRange:range];
    
  //  _channelsOffset+=channelsOffsetCount;
    _offset+= mixed.count;
    
    _isLoading = NO;

}


@end
