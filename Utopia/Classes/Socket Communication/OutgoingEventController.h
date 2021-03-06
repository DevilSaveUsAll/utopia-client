//
//  OutgoingEventController.h
//  Utopia
//
//  Created by Ashwin Kamath on 1/29/12.
//  Copyright (c) 2012 LVL6. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Protocols.pb.h"
#import "UserData.h"
#import <CoreLocation/CoreLocation.h>

@interface OutgoingEventController : NSObject

+ (OutgoingEventController *) sharedOutgoingEventController;

- (void) createUser;

- (void) vaultWithdrawal:(int)amount;
- (void) vaultDeposit:(int)amount;

- (BOOL) taskAction:(int)taskId curTimesActed:(int)numTimesActed;

- (void) battle:(FullUserProto *)defender result:(BattleResult)result city:(int)city equips:(NSArray *)equips;
- (void) buyEquip:(int)equipId;
//- (int) sellEquip:(int)equipId;
- (BOOL) wearEquip:(int)equipId;

- (void) generateAttackList:(int)numEnemies;
- (void) generateAttackList:(int)numEnemies bounds:(CGRect)bounds;

- (void) startup;
- (void) logout;
- (void) reconnect;
- (void) inAppPurchase: (NSString *) receipt goldAmt:(int)gold;

- (void) retrieveMostRecentMarketplacePosts;
- (void) retrieveMoreMarketplacePosts;
- (void) retrieveMostRecentMarketplacePostsFromSender;
- (void) retrieveMoreMarketplacePostsFromSender;
- (void) equipPostToMarketplace:(int)equipId price:(int)amount;
- (void) retractMarketplacePost: (int)postId;
- (void) purchaseFromMarketplace: (int)postId;
- (void) redeemMarketplaceEarnings;
- (void) purchaseShortMarketplaceLicense;
- (void) purchaseLongMarketplaceLicense;

- (void) addAttackSkillPoint;
- (void) addDefenseSkillPoint;
- (void) addEnergySkillPoint;
- (void) addStaminaSkillPoint;
- (void) addHealthSkillPoint;

- (void) refillEnergyWaitComplete;
- (void) refillStaminaWaitComplete;
- (void) refillEnergyWithDiamonds;
- (void) refillStaminaWithDiamonds;

- (UserStruct *) purchaseNormStruct:(int)structId atX:(int)x atY:(int)y;
- (void) moveNormStruct:(UserStruct *)userStruct atX:(int)x atY:(int)y;
- (void) rotateNormStruct:(UserStruct *)userStruct to:(StructOrientation)orientation;
- (void) retrieveFromNormStructure:(UserStruct *)userStruct;
- (void) sellNormStruct:(UserStruct *)userStruct;
- (void) instaBuild:(UserStruct *)userStruct;
- (void) instaUpgrade:(UserStruct *)userStruct;
- (void) normStructWaitComplete:(UserStruct *)userStruct;
- (void) upgradeNormStruct:(UserStruct *)userStruct;
- (void) retrieveAllStaticData;
- (void) retrieveStaticEquip:(int)equipId;
- (void) retrieveStaticEquipsForUser:(FullUserProto *)fup;
- (void) retrieveStructStore;
- (void) retrieveEquipStore;

- (void) loadPlayerCity:(int)userId;
- (void) loadNeutralCity:(int)cityId;
- (void) loadNeutralCity:(int)cityId enemyType:(DefeatTypeJobProto_DefeatTypeJobEnemyType)type;
- (void) loadNeutralCity:(int)cityId asset:(int)assetId;

- (void) levelUp;

- (void) changeUserLocationWithCoordinate:(CLLocationCoordinate2D)coord;

- (void) acceptQuest:(int)questId;
- (void) redeemQuest:(int)questId;
- (void) retrieveQuestLog;
- (void) retrieveQuestDetails:(int)questId;

- (void) retrieveEquipsForUser:(int)userId;
- (void) retrieveUsersForUserIds:(NSArray *)userIds;

- (void) retrieveMostRecentWallPostsForPlayer:(int)playerId;
- (void) retrieveWallPostsForPlayer:(int)playerId beforePostId:(int)postId;
- (PlayerWallPostProto *) postToPlayerWall:(int)playerId withContent:(NSString *)content;

- (void) enableApns:(NSData *)deviceToken;

- (void) kiipReward:(int)gold receipt:(NSString *)string;
- (void) adColonyRewardWithAmount:(int)amount type:(EarnFreeDiamondsRequestProto_AdColonyRewardType)type;

- (BOOL) submitEquipsToBlacksmithWithUserEquipId:(int)equipOne userEquipId:(int)equipTwo guaranteed:(BOOL)guaranteed;
- (void) forgeAttemptWaitComplete;
- (void) finishForgeAttemptWaittimeWithDiamonds;
- (void) collectForgeEquips;

- (void) resetStats;
- (void) resetName:(NSString *)name;
- (void) changeUserType:(UserType)type;
- (void) resetGame;

- (void) retrieveLeaderboardForType:(LeaderboardType)type;
- (void) retrieveLeaderboardForType:(LeaderboardType)type afterRank:(int)afterRank;

- (void) sendGroupChat:(GroupChatScope)scope message:(NSString *)msg;
- (void) purchaseGroupChats;

- (int) createClan:(NSString *)clanName tag:(NSString *)tag;
- (int) leaveClan;
- (int) requestJoinClan:(int)clanId;
- (int) retractRequestToJoinClan:(int)clanId;
- (int) approveOrRejectRequestToJoinClan:(int)requesterId accept:(BOOL)accept;
- (int) transferClanOwnership:(int)newClanOwnerId;
- (int) changeClanDescription:(NSString *)description;
- (void) retrieveClanInfo:(NSString *)clanName clanId:(int)clanId grabType:(RetrieveClanInfoRequestProto_ClanInfoGrabType)grabType isForBrowsingList:(BOOL)isForBrowsingList beforeClanId:(int)beforeClanId;
- (int) bootPlayerFromClan:(int)playerId;
- (ClanWallPostProto *) postOnClanWall:(NSString *)content;
- (void) retrieveClanWallPosts:(int)beforeThisPostId;

- (void) retrieveClanWallPosts:(int)beforeThisPostId;

- (void) retrieveThreeCardMonte;
- (void) playThreeCardMonte:(int)cardID;
- (void) beginGoldmineTimer;
- (void) collectFromGoldmine;

@end
