//
//  SocketCommunication.m
//  Utopia
//
//  Created by Ashwin Kamath on 12/21/11.
//  Copyright (c) 2011 LVL6. All rights reserved.
//

#import "SocketCommunication.h"
#import "LNSynthesizeSingleton.h"
#import "IncomingEventController.h"
#import "GameState.h"
#import "OutgoingEventController.h"
#import "Globals.h"
#import "Apsalar.h"
#import "ClientProperties.h"
#import "FullEvent.h"
#import "GameViewController.h"
#import "GenericPopupController.h"

// Tags for keeping state
#define READING_HEADER_TAG -1
#define HEADER_SIZE 12

#define RECONNECT_TIMEOUT 0.5f
#define NUM_SILENT_RECONNECTS 5

@implementation SocketCommunication

SYNTHESIZE_SINGLETON_FOR_CLASS(SocketCommunication);

static NSString *udid = nil;

- (id) init {
  if ((self = [super init])) {
#ifdef FORCE_TUTORIAL
    udid = [[NSString stringWithFormat:@"%d%d%d", arc4random(), arc4random(), arc4random()] retain];
#else
    udid = [UDID retain];
#endif
  }
  return self;
}

- (void) connectToSocket {
  NSError *error = nil;
  NSString *host  = HOST_NAME;
  uint16_t port = HOST_PORT;
  
  // Make connection to host
  if (![_asyncSocket connectToHost:host onPort:port withTimeout:20.f error:&error]) {
    ContextLogError(LN_CONTEXT_COMMUNICATION, @"Unable to connect to due to invalid configuration: %@", error);
  } else {
    ContextLogInfo(LN_CONTEXT_COMMUNICATION, @"Connecting to \"%@\" on port %hu...", host, port);
  }
}

- (void) rebuildSender {
  [_sender release];
  GameState *gs = [GameState sharedGameState];
  _sender = [gs.minUser retain];
}

- (void) initNetworkCommunication {
  _asyncSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
  [self connectToSocket];
  _currentTagNum = 1;
  [self rebuildSender];
  _shouldReconnect = YES;
  _numDisconnects = 0;
}

- (void) readHeader {
  [_asyncSocket readDataToLength:HEADER_SIZE withTimeout:-1 tag:READING_HEADER_TAG];
}

- (void) socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port {
  ContextLogInfo( LN_CONTEXT_COMMUNICATION, @"Connected to host");
  
  if (![[GameState sharedGameState] connected]) {
    [[OutgoingEventController sharedOutgoingEventController] startup];
    [[GameViewController sharedGameViewController] connectedToHost];
  } else {
    [[OutgoingEventController sharedOutgoingEventController] reconnect];
  }
  [self readHeader];
  
  _numDisconnects = 0;
}

- (void) socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
  if (sock != _asyncSocket) {
    ContextLogInfo( LN_CONTEXT_COMMUNICATION, @"Found data with different socket..");
    return;
  }
  
  if (tag == READING_HEADER_TAG) {
    uint8_t *header = (uint8_t *)[data bytes];
    // Get the next 4 bytes for the payload size
    _nextMsgType = *(int *)(header);
    [_asyncSocket readDataToLength:*(int *)(header+8) withTimeout:-1 tag:*(int *)(header+4)];
  } else {
    [self messageReceived:data withType:_nextMsgType tag:tag];
    _nextMsgType = -1;
    [self readHeader];
  }
}

- (void) socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err
{
	ContextLogError(LN_CONTEXT_COMMUNICATION, @"socketDidDisconnect:withError: \"%@\"", err);
  
  if (err != nil) {
    if (_shouldReconnect) {
      _numDisconnects++;
      if (_numDisconnects > NUM_SILENT_RECONNECTS) {
        ContextLogWarn(LN_CONTEXT_COMMUNICATION, @"Asking to reconnect..");
        [GenericPopupController displayNotificationViewWithText:@"Sorry, we are unable to connect to the server. Please try again." title:@"Disconnected!" okayButton:@"Reconnect" target:self selector:@selector(tryReconnect)];
        _numDisconnects = 0;
      } else {
        ContextLogWarn(LN_CONTEXT_COMMUNICATION, @"Silently reconnecting..");
        [self tryReconnect];
      }
    }
  }
}

- (void) tryReconnect {
  [[NSRunLoop mainRunLoop] addTimer:[NSTimer timerWithTimeInterval:RECONNECT_TIMEOUT target:self selector:@selector(connectToSocket) userInfo:nil repeats:NO] forMode:NSRunLoopCommonModes];
}

-(void) messageReceived:(NSData *)data withType:(EventProtocolResponse)eventType tag:(int)tag {
  if (!_asyncSocket) {
    return;
  }
  
  IncomingEventController *iec = [IncomingEventController sharedIncomingEventController];
  
  // Get the proto class for this event type
  Class typeClass = [iec getClassForType:eventType];
  if (!typeClass) {
    ContextLogError(LN_CONTEXT_COMMUNICATION, @"Unable to find controller for event type: %d", eventType);
    return;
  }
  
  // Call handle<Proto Class> method in event controller
  NSString *selectorStr = [NSString stringWithFormat:@"handle%@:", [typeClass description]];
  SEL handleMethod = NSSelectorFromString(selectorStr);
  if ([iec respondsToSelector:handleMethod]) {
    FullEvent *fe = [FullEvent createWithEvent:(PBGeneratedMessage *)[typeClass parseFromData:data] tag:tag];
    [iec performSelectorOnMainThread:handleMethod withObject:fe waitUntilDone:NO];
  } else {
    ContextLogError(LN_CONTEXT_COMMUNICATION, @"Unable to find %@ in IncomingEventController", selectorStr);
  }
}

- (int) sendData:(PBGeneratedMessage *)msg withMessageType: (int) type {
  NSMutableData *messageWithHeader = [NSMutableData data];
  NSData *data = [msg data];
  
  if (_sender.userId == 0) {
    ContextLogError(LN_CONTEXT_COMMUNICATION, @"User id is 0!!!");
  }
  
  // Need to reverse bytes for size and type(to account for endianness??)
  uint8_t header[HEADER_SIZE];
  header[3] = type & 0xFF;
  header[2] = (type & 0xFF00) >> 8;
  header[1] = (type & 0xFF0000) >> 16;
  header[0] = (type & 0xFF000000) >> 24;
  
  header[7] = _currentTagNum & 0xFF;
  header[6] = (_currentTagNum & 0xFF00) >> 8;
  header[5] = (_currentTagNum & 0xFF0000) >> 16;
  header[4] = (_currentTagNum & 0xFF000000) >> 24;
  
  int size = [data length];
  header[11] = size & 0xFF;
  header[10] = (size & 0xFF00) >> 8;
  header[9] = (size & 0xFF0000) >> 16;
  header[8] = (size & 0xFF000000) >> 24;
  
  [messageWithHeader appendBytes:header length:sizeof(header)];
  [messageWithHeader appendData:data];
  
  int tag = _currentTagNum;
  [_asyncSocket writeData:messageWithHeader withTimeout:-1 tag:_currentTagNum];
  
  _currentTagNum++;
  return tag;
}

- (int) sendUserCreateMessageWithName:(NSString *)name type:(UserType)type lat:(CGFloat)lat lon:(CGFloat)lon referralCode:(NSString *)refCode deviceToken:(NSString *)deviceToken attack:(int)attack defense:(int)defense energy:(int)energy stamina:(int)stamina timeOfStructPurchase:(uint64_t)timeOfStructPurchase timeOfStructBuild:(uint64_t)timeOfStructBuild structX:(int)structX structY:(int)structY usedDiamonds:(BOOL)usedDiamondsToBuild {
  UserCreateRequestProto_Builder *bldr = [UserCreateRequestProto builder];
  
  bldr.udid = udid;
  bldr.name = name;
  bldr.type = type;
  
  if (lat != 0 || lon != 0) {
    bldr.userLocation = [[[[LocationProto builder] setLatitude:lat] setLongitude:lon] build];
  }
  
  if (refCode) {
    bldr.referrerCode = refCode;
  }
  
  if (deviceToken) {
    bldr.deviceToken = deviceToken;
  }
  
  bldr.attack = attack;
  bldr.defense = defense;
  bldr.energy = energy;
  bldr.stamina = stamina;
  bldr.timeOfStructPurchase = timeOfStructPurchase;
  bldr.timeOfStructBuild = timeOfStructBuild;
  bldr.structCoords = [[[[CoordinateProto builder] setX:structX] setY:structY] build];
  bldr.usedDiamondsToBuilt = usedDiamondsToBuild;
  
  UserCreateRequestProto *req = [bldr build];
  return [self sendData:req withMessageType:EventProtocolRequestCUserCreateEvent];
}

- (int) sendStartupMessage:(uint64_t)clientTime {
  StartupRequestProto *req = [[[[[StartupRequestProto builder]
                                 setUdid:udid]
                                setApsalarId:[Apsalar apsalarID]]
                               setVersionNum:[[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] floatValue]]
                              build];
  
  ContextLogInfo( LN_CONTEXT_COMMUNICATION, @"Sent over udid: %@", udid);
  
  return [self sendData:req withMessageType:EventProtocolRequestCStartupEvent];
}

- (int) sendReconnectMessage {
  ReconnectRequestProto *req = [[[ReconnectRequestProto builder]
                                 setSender:_sender]
                                build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCReconnectEvent];
}

- (int) sendLogoutMessage {
  LogoutRequestProto *req = [[[LogoutRequestProto builder]
                              setSender:_sender]
                             build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCLogoutEvent];
}

- (int) sendChatMessage:(NSString *)message recipient:(int)recipient {
  ChatRequestProto *req = [[[[[ChatRequestProto builder]
                              setMessage:message]
                             setSender:_sender]
                            addRecipients:[[[MinimumUserProto builder] setUserId:recipient] build]]
                           build];
  return [self sendData:req withMessageType:EventProtocolRequestCChatEvent];
}

- (int) sendVaultMessage:(int)amount requestType: (VaultRequestProto_VaultRequestType) type {
  VaultRequestProto *req = [[[[[VaultRequestProto builder]
                               setAmount:amount]
                              setSender:_sender]
                             setRequestType:type]
                            build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCVaultEvent];
}

- (int) sendBattleMessage:(MinimumUserProto *)defender result:(BattleResult)result curTime:(uint64_t)curTime city:(int)city equips:(NSArray *)equips {
  BattleRequestProto_Builder *builder = [[[[[[BattleRequestProto builder]
                                             setAttacker:_sender]
                                            setDefender:defender]
                                           setBattleResult:result]
                                          setClientTime:curTime]
                                         addAllDefenderUserEquips:equips];
  if (city != -1) {
    [builder setNeutralCityId:city];
  }
  
  BattleRequestProto *req = [builder build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCBattleEvent];
}

- (int) sendArmoryMessage:(ArmoryRequestProto_ArmoryRequestType)requestType quantity:(int)quantity equipId:(int)equipId {
  ArmoryRequestProto *req = [[[[[[ArmoryRequestProto builder]
                                 setSender:_sender]
                                setRequestType:requestType]
                               setQuantity:quantity]
                              setEquipId:equipId]
                             build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCArmoryEvent];
}

- (int) sendTaskActionMessage:(int)taskId curTime:(uint64_t)clientTime {
  TaskActionRequestProto *req = [[[[[TaskActionRequestProto builder]
                                    setTaskId:taskId]
                                   setSender:_sender]
                                  setCurTime:clientTime]
                                 build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCTaskActionEvent];
}

- (int) sendInAppPurchaseMessage:(NSString *)receipt {
  InAppPurchaseRequestProto *req = [[[[InAppPurchaseRequestProto builder]
                                      setReceipt:receipt]
                                     setSender:_sender]
                                    build];
  return [self sendData:req withMessageType:EventProtocolRequestCInAppPurchaseEvent];
}

- (int) sendRetrieveCurrentMarketplacePostsMessageBeforePostId: (int)postId fromSender:(BOOL)fromSender{
  RetrieveCurrentMarketplacePostsRequestProto_Builder *bldr = [[[RetrieveCurrentMarketplacePostsRequestProto builder] setSender:_sender] setFromSender:fromSender];
  
  if (postId) {
    [bldr setBeforeThisPostId:postId];
  }
  
  RetrieveCurrentMarketplacePostsRequestProto *req = bldr.build;
  return [self sendData:req withMessageType:EventProtocolRequestCRetrieveCurrentMarketplacePostsEvent];
}

- (int) sendEquipPostToMarketplaceMessage:(int)equipId coins:(int)coins diamonds:(int)diamonds {
  PostToMarketplaceRequestProto *req = [[[[[[PostToMarketplaceRequestProto builder]
                                            setUserEquipId:equipId]
                                           setCoinCost:coins]
                                          setDiamondCost:diamonds]
                                         setSender:_sender]
                                        build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCPostToMarketplaceEvent];
}

- (int) sendRetractMarketplacePostMessage: (int)postId {
  RetractMarketplacePostRequestProto *req = [[[[RetractMarketplacePostRequestProto builder]
                                               setSender:_sender]
                                              setMarketplacePostId:postId]
                                             build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCRetractPostFromMarketplaceEvent];
}

- (int) sendPurchaseFromMarketplaceMessage: (int)postId poster:(int)posterId {
  PurchaseFromMarketplaceRequestProto *req = [[[[[PurchaseFromMarketplaceRequestProto builder]
                                                 setSender:_sender]
                                                setMarketplacePostId:postId]
                                               setPosterId:posterId]
                                              build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCPurchaseFromMarketplaceEvent];
}

- (int) sendRedeemMarketplaceEarningsMessage {
  RedeemMarketplaceEarningsRequestProto *req = [[[RedeemMarketplaceEarningsRequestProto builder]
                                                 setSender:_sender]
                                                build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCRedeemMarketplaceEarningsEvent];
}

- (int) sendPurchaseMarketplaceLicenseMessage: (uint64_t)clientTime type:(PurchaseMarketplaceLicenseRequestProto_LicenseType)type {
  PurchaseMarketplaceLicenseRequestProto *req = [[[[[PurchaseMarketplaceLicenseRequestProto builder]
                                                    setSender:_sender]
                                                   setClientTime:clientTime]
                                                  setLicenseType:type]
                                                 build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCPurchaseMarketplaceLicenseEvent];
}

- (int) sendUseSkillPointMessage:(UseSkillPointRequestProto_BoostType) boostType {
  UseSkillPointRequestProto *req = [[[[UseSkillPointRequestProto builder]
                                      setSender:_sender]
                                     setBoostType:boostType]
                                    build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCUseSkillPointEvent];
}

- (int) sendGenerateAttackListMessage:(int)numEnemies latUpperBound:(CGFloat)latUpperBound latLowerBound:(CGFloat)latLowerBound lonUpperBound:(CGFloat)lonUpperBound lonLowerBound:(CGFloat)lonLowerBound {
  GenerateAttackListRequestProto *req = [[[[[[[[[GenerateAttackListRequestProto builder]
                                                setSender:_sender]
                                               setNumEnemies:numEnemies]
                                              setLatLowerBound:latLowerBound]
                                             setLatUpperBound:latUpperBound]
                                            setLongLowerBound:lonLowerBound]
                                           setLongUpperBound:lonUpperBound]
                                          setForMap:YES]
                                         build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCGenerateAttackListEvent];
}

- (int) sendGenerateAttackListMessage:(int)numEnemies {
  GenerateAttackListRequestProto *req = [[[[[GenerateAttackListRequestProto builder]
                                            setSender:_sender]
                                           setNumEnemies:numEnemies]
                                          setForMap:NO]
                                         build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCGenerateAttackListEvent];
}

- (int) sendRefillStatWithDiamondsMessage:(RefillStatWithDiamondsRequestProto_StatType) statType {
  RefillStatWithDiamondsRequestProto *req = [[[[RefillStatWithDiamondsRequestProto builder]
                                               setSender:_sender]
                                              setStatType:statType]
                                             build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCRefillStatWithDiamondsEvent];
}

- (int) sendPurchaseNormStructureMessage:(int)structId x:(int)x y:(int)y time:(uint64_t)time{
  PurchaseNormStructureRequestProto *req = [[[[[[PurchaseNormStructureRequestProto builder]
                                                setSender:_sender]
                                               setStructId:structId]
                                              setStructCoordinates:[[[[CoordinateProto builder] setX:x] setY:y] build]]
                                             setTimeOfPurchase:time]
                                            build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCPurchaseNormStructureEvent];
}

- (int) sendMoveNormStructureMessage:(int)userStructId x:(int)x y:(int)y {
  MoveOrRotateNormStructureRequestProto *req =
  [[[[[[MoveOrRotateNormStructureRequestProto builder]
       setSender:_sender]
      setUserStructId:userStructId]
     setType:MoveOrRotateNormStructureRequestProto_MoveOrRotateNormStructTypeMove]
    setCurStructCoordinates:[[[[CoordinateProto builder] setX:x] setY:y] build]]
   build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCMoveOrRotateNormStructureEvent];
}

- (int) sendRotateNormStructureMessage:(int)userStructId orientation:(StructOrientation)orientation {
  MoveOrRotateNormStructureRequestProto *req =
  [[[[[[MoveOrRotateNormStructureRequestProto builder]
       setSender:_sender]
      setUserStructId:userStructId]
     setType:MoveOrRotateNormStructureRequestProto_MoveOrRotateNormStructTypeRotate]
    setNewOrientation:orientation]
   build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCMoveOrRotateNormStructureEvent];
}

- (int) sendUpgradeNormStructureMessage:(int)userStructId time:(uint64_t)curTime {
  UpgradeNormStructureRequestProto *req = [[[[[UpgradeNormStructureRequestProto builder]
                                              setSender:_sender]
                                             setUserStructId:userStructId]
                                            setTimeOfUpgrade:curTime]
                                           build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCUpgradeNormStructureEvent];
}

- (int) sendNormStructBuildsCompleteMessage:(NSArray *)userStructIds time:(uint64_t)curTime {
  NormStructWaitCompleteRequestProto *req = [[[[[NormStructWaitCompleteRequestProto builder]
                                                setSender:_sender]
                                               addAllUserStructId:userStructIds]
                                              setCurTime:curTime]
                                             build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCNormStructWaitCompleteEvent];
}

- (int) sendFinishNormStructBuildWithDiamondsMessage:(int)userStructId time:(uint64_t)milliseconds type:(FinishNormStructWaittimeWithDiamondsRequestProto_NormStructWaitTimeType) type {
  FinishNormStructWaittimeWithDiamondsRequestProto *req =
  [[[[[[FinishNormStructWaittimeWithDiamondsRequestProto builder]
       setSender:_sender]
      setUserStructId:userStructId]
     setTimeOfSpeedup:milliseconds]
    setWaitTimeType:type]
   build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCFinishNormStructWaittimeWithDiamondsEvent];
}

- (int) sendRetrieveCurrencyFromNormStructureMessage:(int)userStructId time:(uint64_t)milliseconds {
  RetrieveCurrencyFromNormStructureRequestProto *req = [[[[[RetrieveCurrencyFromNormStructureRequestProto builder]
                                                           setSender:_sender]
                                                          setUserStructId:userStructId]
                                                         setTimeOfRetrieval:milliseconds]
                                                        build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCRetrieveCurrencyFromNormStructureEvent];
}

- (int) sendSellNormStructureMessage:(int)userStructId {
  SellNormStructureRequestProto *req = [[[[SellNormStructureRequestProto builder]
                                          setSender:_sender]
                                         setUserStructId:userStructId]
                                        build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCSellNormStructureEvent];
}

- (int) sendLoadPlayerCityMessage:(int)userId {
  LoadPlayerCityRequestProto *req = [[[[LoadPlayerCityRequestProto builder]
                                       setSender:_sender]
                                      setCityOwnerId:userId]
                                     build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCLoadPlayerCityEvent];
}

- (int) sendRetrieveStaticDataMessageWithStructIds:(NSArray *)structIds taskIds:(NSArray *)taskIds questIds:(NSArray *)questIds cityIds:(NSArray *)cityIds equipIds:(NSArray *)equipIds buildStructJobIds:(NSArray *)buildStructJobIds defeatTypeJobIds:(NSArray *)defeatTypeJobIds possessEquipJobIds:(NSArray *)possessEquipJobIds upgradeStructJobIds:(NSArray *)upgradeStructJobIds {
  RetrieveStaticDataRequestProto_Builder *blder = [RetrieveStaticDataRequestProto builder];
  
  if (structIds) {
    [blder addAllStructIds:structIds];
  }
  if (taskIds) {
    [blder addAllTaskIds:taskIds];
  }
  if (questIds) {
    [blder addAllQuestIds:questIds];
  }
  if (cityIds) {
    [blder addAllCityIds:cityIds];
  }
  if (equipIds) {
    [blder addAllEquipIds:equipIds];
  }
  if (buildStructJobIds) {
    [blder addAllBuildStructJobIds:buildStructJobIds];
  }
  if (defeatTypeJobIds) {
    [blder addAllDefeatTypeJobIds:defeatTypeJobIds];
  }
  if (possessEquipJobIds) {
    [blder addAllPossessEquipJobIds:possessEquipJobIds];
  }
  if (upgradeStructJobIds) {
    [blder addAllUpgradeStructJobIds:upgradeStructJobIds];
  }
  
  [blder setSender:_sender];
  RetrieveStaticDataRequestProto *req = [blder build];
  return [self sendData:req withMessageType:EventProtocolRequestCRetrieveStaticDataEvent];
}

- (int) sendRetrieveStaticDataFromShopMessage:(RetrieveStaticDataForShopRequestProto_RetrieveForShopType) type {
  RetrieveStaticDataForShopRequestProto *req = [[[[RetrieveStaticDataForShopRequestProto builder]
                                                  setSender:_sender]
                                                 setType:type]
                                                build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCRetrieveStaticDataForShopEvent];
}

- (int) sendEquipEquipmentMessage:(int) equipId {
  EquipEquipmentRequestProto *req = [[[[EquipEquipmentRequestProto builder]
                                       setSender:_sender]
                                      setUserEquipId:equipId]
                                     build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCEquipEquipmentEvent];
}

- (int) sendChangeUserLocationMessageWithLatitude:(CGFloat)lat longitude:(CGFloat)lon {
  ChangeUserLocationRequestProto *req = [[[[ChangeUserLocationRequestProto builder]
                                           setSender:_sender]
                                          setUserLocation:
                                          [[[[LocationProto builder]
                                             setLatitude:lat]
                                            setLongitude:lon]
                                           build]]
                                         build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCChangeUserLocationEvent];
}

- (int) sendLoadNeutralCityMessage:(int)cityId {
  LoadNeutralCityRequestProto *req = [[[[LoadNeutralCityRequestProto builder]
                                        setSender:_sender]
                                       setCityId:cityId]
                                      build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCLoadNeutralCityEvent];
}

- (int) sendLevelUpMessage {
  LevelUpRequestProto *req = [[[LevelUpRequestProto builder]
                               setSender:_sender]
                              build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCLevelUpEvent];
}

- (int) sendRefillStatWaitTimeComplete:(RefillStatWaitCompleteRequestProto_RefillStatWaitCompleteType)type curTime:(uint64_t)curTime {
  RefillStatWaitCompleteRequestProto *req = [[[[[RefillStatWaitCompleteRequestProto builder]
                                                setSender:_sender]
                                               setType:type]
                                              setCurTime:curTime]
                                             build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCRefillStatWaitCompleteEvent];
}

- (int) sendQuestAcceptMessage:(int)questId {
  QuestAcceptRequestProto *req = [[[[QuestAcceptRequestProto builder]
                                    setSender:_sender]
                                   setQuestId:questId]
                                  build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCQuestAcceptEvent];
}

- (int) sendQuestRedeemMessage:(int)questId {
  QuestRedeemRequestProto *req = [[[[QuestRedeemRequestProto builder]
                                    setSender:_sender]
                                   setQuestId:questId]
                                  build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCQuestRedeemEvent];
}

- (int) sendUserQuestDetailsMessage:(int)questId {
  UserQuestDetailsRequestProto_Builder *builder = [[UserQuestDetailsRequestProto builder]
                                                   setSender:_sender];
  
  if (questId != 0) {
    [builder setQuestId:questId];
  }
  UserQuestDetailsRequestProto *req = [builder build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCUserQuestDetailsEvent];
}

- (int) sendRetrieveUserEquipForUserMessage:(int)userId {
  RetrieveUserEquipForUserRequestProto *req = [[[[RetrieveUserEquipForUserRequestProto builder]
                                                 setSender:_sender]
                                                setRelevantUserId:userId]
                                               build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCRetrieveUserEquipForUser];
}

- (int) sendRetrieveUsersForUserIds:(NSArray *)userIds {
  RetrieveUsersForUserIdsRequestProto *req = [[[[RetrieveUsersForUserIdsRequestProto builder]
                                                setSender:_sender]
                                               addAllRequestedUserIds:userIds]
                                              build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCRetrieveUsersForUserIdsEvent];
}

- (int) sendRetrievePlayerWallPostsMessage:(int)playerId beforePostId:(int)beforePostId {
  RetrievePlayerWallPostsRequestProto_Builder *bldr = [[[RetrievePlayerWallPostsRequestProto builder]
                                                        setSender:_sender]
                                                       setRelevantUserId:playerId];
  
  if (beforePostId > 0) {
    [bldr setBeforeThisPostId:beforePostId];
  }
  
  RetrievePlayerWallPostsRequestProto *req = [bldr build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCRetrievePlayerWallPostsEvent];
}

- (int) sendPostOnPlayerWallMessage:(int)playerId withContent:(NSString *)content {
  PostOnPlayerWallRequestProto *req = [[[[[PostOnPlayerWallRequestProto builder]
                                          setSender:_sender]
                                         setWallOwnerId:playerId]
                                        setContent:content]
                                       build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCPostOnPlayerWallEvent];
}

- (int) sendAPNSMessage:(NSString *)deviceToken {
  EnableAPNSRequestProto *req = [[[[EnableAPNSRequestProto builder]
                                   setSender:_sender]
                                  setDeviceToken:deviceToken]
                                 build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCEnableApnsEvent];
}

- (int) sendEarnFreeDiamondsKiipMessageClientTime:(uint64_t)time receipt:(NSString *)receipt {
  EarnFreeDiamondsRequestProto *req = [[[[[[EarnFreeDiamondsRequestProto builder]
                                           setSender:_sender]
                                          setFreeDiamondsType:EarnFreeDiamondsTypeKiip]
                                         setClientTime:time]
                                        setKiipReceipt:receipt]
                                       build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCEarnFreeDiamondsEvent];
}

- (int) sendEarnFreeDiamondsAdColonyMessageClientTime:(uint64_t)time digest:(NSString *)digest amount:(int)amount type:(EarnFreeDiamondsRequestProto_AdColonyRewardType)type {
  EarnFreeDiamondsRequestProto *req = [[[[[[[[EarnFreeDiamondsRequestProto builder]
                                             setSender:_sender]
                                            setFreeDiamondsType:EarnFreeDiamondsTypeAdcolony]
                                           setClientTime:time]
                                          setAdColonyDigest:digest]
                                         setAdColonyAmountEarned:amount]
                                        setAdColonyRewardType:type]
                                       build];
  return [self sendData:req withMessageType:EventProtocolRequestCEarnFreeDiamondsEvent];
}

- (int) sendSubmitEquipsToBlacksmithMessageWithUserEquipId:(int)equipOne userEquipId:(int)equipTwo guaranteed:(BOOL)guaranteed clientTime:(uint64_t)time {
  SubmitEquipsToBlacksmithRequestProto *req = [[[[[[[SubmitEquipsToBlacksmithRequestProto builder]
                                                    setSender:_sender]
                                                   setUserEquipOne:equipOne]
                                                  setUserEquipTwo:equipTwo]
                                                 setPaidToGuarantee:guaranteed]
                                                setStartTime:time]
                                               build];
  return [self sendData:req withMessageType:EventProtocolRequestCSubmitEquipsToBlacksmith];
}

- (int) sendForgeAttemptWaitCompleteMessageWithBlacksmithId:(int)blacksmithId clientTime:(uint64_t)time {
  ForgeAttemptWaitCompleteRequestProto *req = [[[[[ForgeAttemptWaitCompleteRequestProto builder]
                                                  setBlacksmithId:blacksmithId]
                                                 setCurTime:time]
                                                setSender:_sender]
                                               build];
  return [self sendData:req withMessageType:EventProtocolRequestCForgeAttemptWaitComplete];
}

- (int) sendFinishForgeAttemptWaittimeWithDiamondsWithBlacksmithId:(int)blacksmithId clientTime:(uint64_t)time {
  FinishForgeAttemptWaittimeWithDiamondsRequestProto *req = [[[[[FinishForgeAttemptWaittimeWithDiamondsRequestProto builder]
                                                                setBlacksmithId:blacksmithId]
                                                               setTimeOfSpeedup:time]
                                                              setSender:_sender]
                                                             build];
  return [self sendData:req withMessageType:EventProtocolRequestCFinishForgeAttemptWaittimeWithDiamonds];
}

- (int) sendCollectForgeEquipsWithBlacksmithId:(int)blacksmithId {
  CollectForgeEquipsRequestProto *req = [[[[CollectForgeEquipsRequestProto builder]
                                           setBlacksmithId:blacksmithId]
                                          setSender:_sender]
                                         build];
  return [self sendData:req withMessageType:EventProtocolRequestCCollectForgeEquips ];
}

- (int) sendCharacterModWithType:(CharacterModType)modType newType:(UserType)userType newName:(NSString *)name {
  CharacterModRequestProto_Builder *bldr = [[[CharacterModRequestProto builder]
                                             setModType:modType]
                                            setSender:_sender];
  
  if (modType == CharacterModTypeChangeName && name) {
    [bldr setFutureName:name];
  }
  
  if (modType == CharacterModTypeChangeCharacterType) {
    [bldr setFutureUserType:userType];
  }
  
  CharacterModRequestProto *req = [bldr build];
  return [self sendData:req withMessageType:EventProtocolRequestCCharacterModEvent];
}

- (int) sendRetrieveLeaderboardMessage:(LeaderboardType)type afterRank:(int)rank {
  RetrieveLeaderboardRequestProto *req = [[[[[RetrieveLeaderboardRequestProto builder]
                                             setLeaderboardType:type]
                                            setAfterThisRank:rank]
                                           setSender:_sender]
                                          build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCRetrieveLeaderboardEvent];
}

- (int) sendGroupChatMessage:(GroupChatScope)scope message:(NSString *)msg {
  SendGroupChatRequestProto *req = [[[[[SendGroupChatRequestProto builder]
                                       setScope:scope]
                                      setChatMessage:msg]
                                     setSender:_sender]
                                    build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCSendGroupChatEvent];
}

- (int) sendPurchaseGroupChatMessage {
  SendGroupChatRequestProto *req = [[[SendGroupChatRequestProto builder]
                                     setSender:_sender]
                                    build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCPurchaseGroupChatEvent];
}

- (int) sendCreateClanMessage:(NSString *)clanName tag:(NSString *)tag {
  CreateClanRequestProto *req = [[[[[CreateClanRequestProto builder]
                                    setSender:_sender]
                                   setName:clanName]
                                  setTag:tag]
                                 build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCCreateClanEvent];
}

- (int) sendLeaveClanMessage {
  LeaveClanRequestProto *req = [[[LeaveClanRequestProto builder]
                                 setSender:_sender]
                                build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCLeaveClanEvent];
}

- (int) sendRequestJoinClanMessage:(int)clanId {
  RequestJoinClanRequestProto *req = [[[[RequestJoinClanRequestProto builder]
                                        setSender:_sender]
                                       setClanId:clanId]
                                      build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCRequestJoinClanEvent];
}

- (int) sendRetractRequestJoinClanMessage:(int)clanId {
  RetractRequestJoinClanRequestProto *req = [[[[RetractRequestJoinClanRequestProto builder]
                                               setSender:_sender]
                                              setClanId:clanId]
                                             build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCRetractRequestJoinClanEvent];
}

- (int) sendApproveOrRejectRequestToJoinClan:(int)requesterId accept:(BOOL)accept {
  ApproveOrRejectRequestToJoinClanRequestProto *req = [[[[[ApproveOrRejectRequestToJoinClanRequestProto builder]
                                                          setSender:_sender]
                                                         setRequesterId:requesterId]
                                                        setAccept:accept]
                                                       build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCApproveOrRejectRequestToJoinClanEvent];
}

- (int) sendTransferClanOwnership:(int)newClanOwnerId {
  TransferClanOwnershipRequestProto *req = [[[[TransferClanOwnershipRequestProto builder]
                                              setSender:_sender]
                                             setNewClanOwnerId:newClanOwnerId]
                                            build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCTransferClanOwnership];
}

- (int) sendChangeClanDescription:(NSString *)description {
  ChangeClanDescriptionRequestProto *req = [[[[ChangeClanDescriptionRequestProto builder]
                                              setSender:_sender]
                                             setDescription:description]
                                            build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCChangeClanDescriptionEvent];
}

- (int) sendRetrieveClanInfoMessage:(NSString *)clanName clanId:(int)clanId grabType:(RetrieveClanInfoRequestProto_ClanInfoGrabType)grabType isForBrowsingList:(BOOL)isForBrowsingList beforeClanId:(int)beforeClanId {
  RetrieveClanInfoRequestProto_Builder *bldr = [[[[RetrieveClanInfoRequestProto builder]
                                                  setSender:_sender]
                                                 setGrabType:grabType]
                                                setIsForBrowsingList:isForBrowsingList];
  
  if (clanName) bldr.clanName = clanName;
  if (clanId) bldr.clanId = clanId;
  if (beforeClanId) bldr.beforeThisClanId = beforeClanId;
  
  RetrieveClanInfoRequestProto *req = [bldr build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCRetrieveClanInfoEvent];
}

- (int) sendBootPlayerFromClan:(int)playerId {
  BootPlayerFromClanRequestProto *req = [[[[BootPlayerFromClanRequestProto builder]
                                           setSender:_sender]
                                          setPlayerToBoot:playerId]
                                         build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCBootPlayerFromClanEvent];
}

- (int) sendPostOnClanWallMessage:(NSString *)content {
  PostOnClanWallRequestProto *req = [[[[PostOnClanWallRequestProto builder]
                                       setSender:_sender]
                                      setContent:content]
                                     build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCPostOnClanWallEvent];
}

- (int) sendRetrieveClanWallPostsMessage:(int)beforeThisClanId {
  RetrieveClanInfoRequestProto_Builder *bldr = [[RetrieveClanInfoRequestProto builder] setSender:_sender];
  
  if (beforeThisClanId > 0) {
    [bldr setBeforeThisClanId:beforeThisClanId];
  }
  
  RetrieveClanInfoRequestProto *req = [bldr build];
  return [self sendData:req withMessageType:EventProtocolRequestCRetrieveClanWallPostsEvent];
}

- (int) sendRetrieveThreeCardMonteMessage {
  RetrieveThreeCardMonteRequestProto *req = [[[RetrieveThreeCardMonteRequestProto builder] setSender:_sender] build];
  return [self sendData:req withMessageType:EventProtocolRequestCRetrieveThreeCardMonteEvent];
}

- (int) sendPlayThreeCardMonteMessage:(int)cardId {
  PlayThreeCardMonteRequestProto *req = [[[[PlayThreeCardMonteRequestProto builder]setSender:_sender]setCardId:cardId]build];
  return [self sendData:req withMessageType:EventProtocolRequestCPlayThreeCardMonteEvent];
}

- (int) sendBeginGoldmineTimerMessage:(uint64_t)clientTime reset:(BOOL)reset {
  BeginGoldmineTimerRequestProto *req = [[[[[BeginGoldmineTimerRequestProto builder]
                                            setSender:_sender]
                                           setClientTime:clientTime]
                                          setReset:reset]
                                         build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCBeginGoldmineTimerEvent];
}

- (int) sendCollectFromGoldmineMessage:(uint64_t)clientTime {
  CollectFromGoldmineRequestProto *req = [[[[CollectFromGoldmineRequestProto builder]
                                            setSender:_sender]
                                           setClientTime:clientTime]
                                          build];
  
  return [self sendData:req withMessageType:EventProtocolRequestCCollectFromGoldmineEvent];
}

- (void) closeDownConnection {
  if (_asyncSocket) {
    _shouldReconnect = NO;
    [_asyncSocket disconnectAfterReadingAndWriting];
    ContextLogInfo( LN_CONTEXT_COMMUNICATION, @"Disconnected from socket..");
    [_asyncSocket release];
    _asyncSocket = nil;
  }
}

- (void) dealloc {
  [udid release];
  udid = nil;
  [_sender release];
  [self closeDownConnection];
  [super dealloc];
}

@end
