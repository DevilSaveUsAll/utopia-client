//
//  ForgeMenus.m
//  Utopia
//
//  Created by Ashwin Kamath on 7/18/12.
//  Copyright (c) 2012 LVL6. All rights reserved.
//

#import "ForgeMenus.h"

@implementation ForgeItem

@synthesize equipId, level, quantity;

- (NSString *)description {
  FullEquipProto *fep = [[GameState sharedGameState] equipWithId:equipId];
  return [NSString stringWithFormat:@"{%p: equip=%@, level=%d, quantity=%d}", self, fep.name, level, quantity];
}

@end

@implementation ForgeItemView

@synthesize nameLabel, attackLabel, defenseLabel;
@synthesize quantityLabel, equipIcon, forgeItem;
@synthesize bgdImage, forgingTag, levelIcon;

- (void) loadForForgeItem:(ForgeItem *)fi {
  GameState *gs = [GameState sharedGameState];
  Globals *gl = [Globals sharedGlobals];
  FullEquipProto *fep = [gs equipWithId:fi.equipId];
  
  self.forgeItem = fi;
  self.nameLabel.text = fep.name;
  self.quantityLabel.text = [NSString stringWithFormat:@"%d", fi.quantity];
  [Globals loadImageForEquip:fi.equipId toView:equipIcon maskedView:nil];
  self.attackLabel.text = [NSString stringWithFormat:@"%d", [gl calculateAttackForEquip:fi.equipId level:fi.level]];
  self.defenseLabel.text = [NSString stringWithFormat:@"%d", [gl calculateDefenseForEquip:fi.equipId level:fi.level]];
  
  self.levelIcon.level = fi.level;
         
  if (gs.forgeAttempt.equipId == fi.equipId && gs.forgeAttempt.level == fi.level) {
    self.forgingTag.hidden = NO;
  } else {
    self.forgingTag.hidden = YES;
  }
}

- (void) setSelected:(BOOL)selected animated:(BOOL)animated {
  [super setSelected:selected animated:animated];
  if (selected) {
    bgdImage.highlighted = YES;
  } else if (!self.highlighted) {
    bgdImage.highlighted = NO;
  }
}

- (void) setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
  [super setHighlighted:highlighted animated:animated];
  if (highlighted) {
    bgdImage.highlighted = YES;
  } else if (!self.selected) {
    bgdImage.highlighted = NO;
  }
}

- (void) dealloc {
  self.nameLabel = nil;
  self.attackLabel = nil;
  self.defenseLabel = nil;
  self.quantityLabel = nil;
  self.equipIcon = nil;
  self.forgeItem = nil;
  self.bgdImage = nil;
  self.forgingTag = nil;
  self.levelIcon = nil;
  [super dealloc];
}

@end

@implementation ForgeProgressView

@synthesize timeLeftLabel, progressBar, timer;

- (void) beginAnimating {
  GameState *gs = [GameState sharedGameState];
  Globals *gl = [Globals sharedGlobals];
  ForgeAttempt *fa = gs.forgeAttempt;
  
  int minutes = [gl calculateMinutesForForge:fa.equipId level:fa.level];
  NSDate *endDate = [fa.startTime dateByAddingTimeInterval:minutes*60.f];
  
  self.timer = [NSTimer timerWithTimeInterval:1.f target:self selector:@selector(updateLabel:) userInfo:endDate repeats:YES];
  [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
  [self updateLabel:self.timer];
  
  float timePassed = -[fa.startTime timeIntervalSinceNow];
  self.progressBar.percentage = timePassed/minutes/60.f;
  [UIView animateWithDuration:minutes*60-timePassed animations:^{
    self.progressBar.percentage = 1.f;
  }];
}

- (void) stopAnimating {
  self.timer = nil;
  [self.progressBar.layer removeAllAnimations];
}

- (void) updateLabel:(NSTimer *)t {
  NSDate *date = t.userInfo;
  NSTimeInterval interval = [date timeIntervalSinceNow];
  if (interval >= 0.f) {
    self.timeLeftLabel.text = [NSString stringWithFormat:@"Finishes in %@", [Globals convertTimeToString:interval]];
  } else {
    self.timeLeftLabel.text = [NSString stringWithFormat:@"Finishes in %@", [Globals convertTimeToString:0.f]];
    self.timer = nil;
  }
}

- (void) setTimer:(NSTimer *)t {
  if (timer != t) {
    [timer invalidate];
    [timer release];
    timer = [t retain];
  }
}

- (void) dealloc {
  self.timer = nil;
  self.timeLeftLabel = nil;
  self.progressBar = nil;
  [super dealloc];
}

@end

@implementation ForgeStatusView

@synthesize statusLabel, checkIcon, xIcon, spinner;

- (void) displayAttemptComplete {
  self.statusLabel.text = @"Attempt Complete";
  self.statusLabel.textColor = [Globals creamColor];
  self.checkIcon.hidden = NO;
  self.xIcon.hidden = YES;
  self.spinner.hidden = YES;
  [self.spinner stopAnimating];
}

- (void) displayForgeSuccess {
  self.statusLabel.text = @"Forge Succeeded";
  self.statusLabel.textColor = [Globals greenColor];
  self.checkIcon.hidden = NO;
  self.xIcon.hidden = YES;
  self.spinner.hidden = YES;
  [self.spinner stopAnimating];
}

- (void) displayForgeFailed {
  self.statusLabel.text = @"Forge Failed";
  self.statusLabel.textColor = [Globals redColor];
  self.checkIcon.hidden = YES;
  self.xIcon.hidden = NO;
  self.spinner.hidden = YES;
  [self.spinner stopAnimating];
}

- (void) displayCheckingForge {
  self.statusLabel.text = @"Checking...";
  self.statusLabel.textColor = [Globals creamColor];
  self.checkIcon.hidden = YES;
  self.xIcon.hidden = YES;
  self.spinner.hidden = NO;
  [self.spinner startAnimating];
}

- (void) dealloc {
  self.statusLabel = nil;
  self.checkIcon = nil;
  self.xIcon = nil;
  self.spinner = nil;
  [super dealloc];
}

@end