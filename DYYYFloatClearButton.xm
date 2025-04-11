/* 
 * Tweak Name: 1KeyHideDYUI
 * Target App: com.ss.iphone.ugc.Aweme
 * Dev: @c00kiec00k 曲奇的坏品味🍻
 * iOS Version: 16.5
 */
#import "AwemeHeaders.h"
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <signal.h>
#import <objc/runtime.h>
// 定义悬浮按钮类
@interface HideUIButton : UIButton
@property (nonatomic, assign) BOOL isElementsHidden;
@property (nonatomic, strong) NSMutableArray *hiddenViewsList;
@property (nonatomic, assign) BOOL isPersistentMode; // 是否为全局生效模式
- (void)hideUIElements;
- (void)showUIElements;
- (void)safeResetState;
- (void)findAndHideViewsOfClass:(Class)viewClass inView:(UIView *)view withPredicate:(BOOL (^)(id view))predicate;
@end
// 全局变量
static HideUIButton *hideButton;
static BOOL isAppInTransition = NO;
static NSString *const kLastPositionXKey = @"lastHideButtonPositionX";
static NSString *const kLastPositionYKey = @"lastHideButtonPositionY";
static NSString *const kPersistentModeKey = @"hideButtonPersistentMode";
static NSString *const kIsElementsHiddenKey = @"isElementsHidden";
static NSString *const kEnableButtonKey = @"DYYYEnableFloatClearButton";
// 用于方法交换的全局变量
static IMP originalSetAlpha = NULL;
static IMP originalSetHidden = NULL;
static NSMutableSet *classesToSwizzle;
// 获取keyWindow的辅助方法
static UIWindow* getKeyWindow() {
    UIWindow *keyWindow = nil;
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if (window.isKeyWindow) {
            keyWindow = window;
            break;
        }
    }
    return keyWindow;
}
// 获取抖音应用的Documents目录
static NSString* getAppDocumentsPath() {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [paths firstObject];
}
// 检查自定义图标是否存在
static UIImage* getCustomImage(NSString *imageName) {
    NSString *documentsPath = getAppDocumentsPath();
    NSString *imagePath = [documentsPath stringByAppendingPathComponent:imageName];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:imagePath]) {
        return [UIImage imageWithContentsOfFile:imagePath];
    }
    return nil;
}
// 扩展的类列表 - 包含更多需要隐藏的UI元素
static NSArray* getHideClassList() {
    return @[
        @"AWEHPTopBarCTAContainer",
        @"AWEHPDiscoverFeedEntranceView",
        @"AWELeftSideBarEntranceView",
        @"DUXBadge",
        @"AWEBaseElementView",
        @"AWEPlayInteractionDescriptionLabel",
        @"AWEUserNameLabel",
        @"AWEStoryProgressSlideView",
        @"AWEStoryProgressContainerView",
        @"ACCEditTagStickerView",
        @"AWEFeedTemplateAnchorView",
        @"AWESearchFeedTagView",
        @"AWEPlayInteractionSearchAnchorView",
        @"AFDRecommendToFriendTagView",
        @"AWELandscapeFeedEntryView",
        @"AWEFeedAnchorContainerView",
        @"AFDAIbumFolioView",
        @"AWEAwemeDescriptionLabel", // 添加更多可能包含左下角文案的类
        @"AWEPlayInteractionView",
        @"AWEUILabel",
        @"AWEPlayInteractionCommentGuideView",
        @"AWECommentCountLabel",
        @"AWEPlayInteractionLikeView",
        @"AWEPlayInteractionCommentView",
        @"AWEPlayInteractionShareView",
        @"AWEFeedCellBottomView",
        @"AWEUIView"
    ];
}
// 判断是否为目标AWEElementStackView的函数
static BOOL isTargetStackView(id view) {
    if ([view respondsToSelector:@selector(accessibilityLabel)]) {
        NSString *accessibilityLabel = [view accessibilityLabel];
        return [accessibilityLabel isEqualToString:@"left"];
    }
    return NO;
}
// 判断视图是否应该被隐藏
static BOOL shouldHideView(UIView *view) {
    if (!hideButton || !hideButton.isElementsHidden) {
        return NO;
    }
    
    // 检查视图类型
    for (NSString *className in getHideClassList()) {
        Class viewClass = NSClassFromString(className);
        if (viewClass && [view isKindOfClass:viewClass]) {
            return YES;
        }
    }
    
    // 特别检查AWEElementStackView
    Class stackViewClass = NSClassFromString(@"AWEElementStackView");
    if (stackViewClass && [view isKindOfClass:stackViewClass]) {
        return isTargetStackView(view);
    }
    
    // 检查AWEBaseElementView是否是目标AWEElementStackView的子视图
    Class baseElementClass = NSClassFromString(@"AWEBaseElementView");
    if (baseElementClass && [view isKindOfClass:baseElementClass]) {
        UIView *superview = view.superview;
        if ([superview isKindOfClass:NSClassFromString(@"AWEElementStackView")]) {
            return isTargetStackView(superview);
        }
    }
    
    return NO;
}
// 替换的setAlpha方法
static void newSetAlpha(id self, SEL _cmd, CGFloat alpha) {
    // 如果当前视图应该被隐藏，则强制设置alpha为0
    if (shouldHideView((UIView *)self)) {
        ((void (*)(id, SEL, CGFloat))originalSetAlpha)(self, _cmd, 0.0);
        
        // 如果不在hiddenViewsList中，添加它
        if (hideButton && ![hideButton.hiddenViewsList containsObject:self]) {
            [hideButton.hiddenViewsList addObject:self];
        }
    } else {
        ((void (*)(id, SEL, CGFloat))originalSetAlpha)(self, _cmd, alpha);
    }
}
// 替换的setHidden方法
static void newSetHidden(id self, SEL _cmd, BOOL hidden) {
    // 如果当前视图应该被隐藏，则强制设置hidden为YES
    if (shouldHideView((UIView *)self)) {
        ((void (*)(id, SEL, BOOL))originalSetHidden)(self, _cmd, YES);
        
        // 如果不在hiddenViewsList中，添加它
        if (hideButton && ![hideButton.hiddenViewsList containsObject:self]) {
            [hideButton.hiddenViewsList addObject:self];
        }
    } else {
        ((void (*)(id, SEL, BOOL))originalSetHidden)(self, _cmd, hidden);
    }
}
// 交换UIView的setAlpha和setHidden方法
static void swizzleUIViewMethods() {
    // 初始化需要交换方法的类集合
    classesToSwizzle = [NSMutableSet set];
    
    // 添加所有需要隐藏的类
    for (NSString *className in getHideClassList()) {
        Class viewClass = NSClassFromString(className);
        if (viewClass) {
            [classesToSwizzle addObject:viewClass];
        }
    }
    
    // 添加AWEElementStackView和AWEBaseElementView
    Class stackViewClass = NSClassFromString(@"AWEElementStackView");
    if (stackViewClass) {
        [classesToSwizzle addObject:stackViewClass];
    }
    
    Class baseElementClass = NSClassFromString(@"AWEBaseElementView");
    if (baseElementClass) {
        [classesToSwizzle addObject:baseElementClass];
    }
    
    // 对每个类交换方法
    for (Class viewClass in classesToSwizzle) {
        // 交换setAlpha:方法
        Method originalAlphaMethod = class_getInstanceMethod(viewClass, @selector(setAlpha:));
        if (originalAlphaMethod) {
            originalSetAlpha = method_getImplementation(originalAlphaMethod);
            method_setImplementation(originalAlphaMethod, (IMP)newSetAlpha);
        }
        
        // 交换setHidden:方法
        Method originalHiddenMethod = class_getInstanceMethod(viewClass, @selector(setHidden:));
        if (originalHiddenMethod) {
            originalSetHidden = method_getImplementation(originalHiddenMethod);
            method_setImplementation(originalHiddenMethod, (IMP)newSetHidden);
        }
    }
}
// HideUIButton 实现
@implementation HideUIButton
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // 基本设置 - 完全透明背景，只显示图标
        self.backgroundColor = [UIColor clearColor];
        
        // 初始化属性
        _hiddenViewsList = [NSMutableArray array];
        
        // 从用户默认设置中加载持久化模式设置
        _isPersistentMode = [[NSUserDefaults standardUserDefaults] boolForKey:kPersistentModeKey];
        _isElementsHidden = [[NSUserDefaults standardUserDefaults] boolForKey:kIsElementsHiddenKey];
        
        // 设置初始图标或文字
        [self setupButtonAppearance];
        
        // 添加拖动手势
        UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:panGesture];
        
        // 使用单击事件（原生按钮点击）
        [self addTarget:self action:@selector(handleTap) forControlEvents:UIControlEventTouchUpInside];
        
        // 添加长按手势
        UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        longPressGesture.minimumPressDuration = 0.5; // 0.5秒长按
        [self addGestureRecognizer:longPressGesture];
        
        // 如果之前是隐藏状态，则恢复隐藏
        if (_isElementsHidden) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self hideUIElements];
            });
        }
    }
    return self;
}
- (void)setupButtonAppearance {
    // 尝试加载自定义图标
    UIImage *customShowIcon = getCustomImage(@"Qingping.png");
    
    if (customShowIcon) {
        [self setImage:customShowIcon forState:UIControlStateNormal];
    } else {
        // 如果没有自定义图标，则使用文字
        [self setTitle:self.isElementsHidden ? @"显示" : @"隐藏" forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        self.titleLabel.textColor = [UIColor whiteColor];
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5]; // 半透明背景，便于看到文字
        self.layer.cornerRadius = self.frame.size.width / 2;
        self.layer.masksToBounds = YES;
    }
}
- (void)updateButtonAppearance {
    // 更新按钮外观，根据当前状态
    UIImage *customShowIcon = getCustomImage(@"Qingping.png");
    
    if (customShowIcon) {
        [self setImage:customShowIcon forState:UIControlStateNormal];
    } else {
        [self setTitle:self.isElementsHidden ? @"显示" : @"隐藏" forState:UIControlStateNormal];
    }
}
- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.superview];
    CGPoint newCenter = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    
    // 确保按钮不会超出屏幕边界
    newCenter.x = MAX(self.frame.size.width / 2, MIN(newCenter.x, self.superview.frame.size.width - self.frame.size.width / 2));
    newCenter.y = MAX(self.frame.size.height / 2, MIN(newCenter.y, self.superview.frame.size.height - self.frame.size.height / 2));
    
    self.center = newCenter;
    [gesture setTranslation:CGPointZero inView:self.superview];
    
    // 保存位置到NSUserDefaults
    if (gesture.state == UIGestureRecognizerStateEnded) {
        [[NSUserDefaults standardUserDefaults] setFloat:self.center.x forKey:kLastPositionXKey];
        [[NSUserDefaults standardUserDefaults] setFloat:self.center.y forKey:kLastPositionYKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}
- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self showOptionsMenu];
    }
}
- (void)showOptionsMenu {
    // 创建一个UIAlertController作为菜单
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"设置"
                                                                             message:nil
                                                                      preferredStyle:UIAlertControllerStyleActionSheet];
    
    // 添加"全局生效"选项
    NSString *persistentTitle = self.isPersistentMode ? @"✓ 全局生效" : @"全局生效";
    UIAlertAction *persistentAction = [UIAlertAction actionWithTitle:persistentTitle
                                                               style:UIAlertActionStyleDefault
                                                             handler:^(UIAlertAction * _Nonnull action) {
        self.isPersistentMode = !self.isPersistentMode;
        [[NSUserDefaults standardUserDefaults] setBool:self.isPersistentMode forKey:kPersistentModeKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }];
    [alertController addAction:persistentAction];
    
    // 添加"单个视频生效"选项
    NSString *singleVideoTitle = !self.isPersistentMode ? @"✓ 单个视频生效" : @"单个视频生效";
    UIAlertAction *singleVideoAction = [UIAlertAction actionWithTitle:singleVideoTitle
                                                                style:UIAlertActionStyleDefault
                                                              handler:^(UIAlertAction * _Nonnull action) {
        self.isPersistentMode = !self.isPersistentMode;
        [[NSUserDefaults standardUserDefaults] setBool:self.isPersistentMode forKey:kPersistentModeKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }];
    [alertController addAction:singleVideoAction];
    
    // 添加取消选项
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    [alertController addAction:cancelAction];
    
    // 在iPad上，我们需要设置弹出位置
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alertController.popoverPresentationController.sourceView = self;
        alertController.popoverPresentationController.sourceRect = self.bounds;
    }
    
    // 显示菜单
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alertController animated:YES completion:nil];
}
- (void)handleTap {
    if (isAppInTransition) {
        return;
    }
    
    if (!self.isElementsHidden) {
        // 隐藏UI元素
        [self hideUIElements];
    } else {
        // 恢复所有UI元素
        [self showUIElements];
    }
    
    // 保存状态
    [[NSUserDefaults standardUserDefaults] setBool:self.isElementsHidden forKey:kIsElementsHiddenKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    [self updateButtonAppearance];
}
- (void)hideUIElements {
    // 递归查找并隐藏所有匹配的视图
    for (NSString *className in getHideClassList()) {
        Class viewClass = NSClassFromString(className);
        if (!viewClass) continue;
        
        // 递归查找所有匹配的视图
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            [self findAndHideViewsOfClass:viewClass inView:window withPredicate:nil];
        }
    }
    
    // 特别处理AWEElementStackView
    Class stackViewClass = NSClassFromString(@"AWEElementStackView");
    if (stackViewClass) {
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            [self findAndHideViewsOfClass:stackViewClass inView:window withPredicate:^BOOL(id view) {
                return isTargetStackView(view);
            }];
        }
    }
    
    self.isElementsHidden = YES;
}
- (void)showUIElements {
    // 恢复所有被隐藏的视图
    for (UIView *view in self.hiddenViewsList) {
        if ([view isKindOfClass:[UIView class]]) {
            view.alpha = 1.0;
            view.hidden = NO;
        }
    }
    
    [self.hiddenViewsList removeAllObjects];
    self.isElementsHidden = NO;
}
- (void)findAndHideViewsOfClass:(Class)viewClass inView:(UIView *)view withPredicate:(BOOL (^)(id view))predicate {
    if ([view isKindOfClass:viewClass]) {
        // 只有不是自己，并且满足谓词条件（如果有）才隐藏
        if (view != self && (!predicate || predicate(view))) {
            if (![self.hiddenViewsList containsObject:view]) {
                [self.hiddenViewsList addObject:view];
                view.alpha = 0.0;
                view.hidden = YES;
            }
        }
    }
    
    // 递归查找子视图
    for (UIView *subview in view.subviews) {
        [self findAndHideViewsOfClass:viewClass inView:subview withPredicate:predicate];
    }
}
- (void)safeResetState {
    // 恢复所有UI元素
    [self showUIElements];
    
    // 保存状态
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kIsElementsHiddenKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    [self updateButtonAppearance];
}
@end
// 预先隐藏视图的方法
%hook UIView
- (void)didMoveToSuperview {
    %orig;
    
    // 如果当前是隐藏状态且该视图应该被隐藏，则立即隐藏它
    if (hideButton && hideButton.isElementsHidden && shouldHideView(self)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![hideButton.hiddenViewsList containsObject:self]) {
                [hideButton.hiddenViewsList addObject:self];
                self.alpha = 0.0;
                self.hidden = YES;
            }
        });
    }
}
- (void)didMoveToWindow {
    %orig;
    
    // 当视图被添加到窗口时也检查
    if (hideButton && hideButton.isElementsHidden && shouldHideView(self)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![hideButton.hiddenViewsList containsObject:self]) {
                [hideButton.hiddenViewsList addObject:self];
                self.alpha = 0.0;
                self.hidden = YES;
            }
        });
    }
}
%end
// 监控视图转换状态
%hook UIViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    isAppInTransition = YES;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        isAppInTransition = NO;
        
        // 如果是全局模式且状态是隐藏，则确保所有元素都被隐藏
        if (hideButton && hideButton.isElementsHidden && hideButton.isPersistentMode) {
            [hideButton hideUIElements];
        }
    });
}
- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    isAppInTransition = YES;
    
    if (hideButton && hideButton.isElementsHidden && !hideButton.isPersistentMode) {
        // 如果视图即将消失且不是全局模式，直接重置状态
        dispatch_async(dispatch_get_main_queue(), ^{
            [hideButton safeResetState];
        });
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        isAppInTransition = NO;
    });
}
%end
// 监控视频内容变化 - 这里使用更精确的hook
%hook AWEFeedCellViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    
    // 如果是全局模式且元素被隐藏，则在视频切换时重新隐藏所有元素
    if (hideButton && hideButton.isElementsHidden && hideButton.isPersistentMode) {
        // 使用延迟以确保新的UI元素已经加载
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [hideButton hideUIElements];
        });
    }
    // 如果是单视频模式且元素被隐藏，则在视频切换时恢复元素
    else if (hideButton && hideButton.isElementsHidden && !hideButton.isPersistentMode) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [hideButton safeResetState];
        });
    }
}
%end
// 适配更多可能的视频容器
%hook AWEAwemeViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    
    // 如果是全局模式且元素被隐藏，确保所有元素都被隐藏
    if (hideButton && hideButton.isElementsHidden && hideButton.isPersistentMode) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [hideButton hideUIElements];
        });
    }
}
%end
// 在视频切换或滚动时更强力地重新应用隐藏，但减少频率以提高性能
%hook AWEFeedTableView
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    %orig;
    
    // 视频滚动停止后，重新检查并隐藏元素
    if (hideButton && hideButton.isElementsHidden && hideButton.isPersistentMode) {
        static NSTimeInterval lastUpdateTime = 0;
        NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
        
        // 确保至少间隔1秒才执行一次隐藏操作，避免频繁执行导致卡顿
        if (currentTime - lastUpdateTime > 1.0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [hideButton hideUIElements];
            });
            lastUpdateTime = currentTime;
        }
    }
}
%end
// 预先隐藏视频Cell内的元素
%hook AWEFeedTableViewCell
- (void)setContentView:(UIView *)contentView {
    %orig;
    
    // 如果是全局模式且元素被隐藏，预先处理内部元素
    if (hideButton && hideButton.isElementsHidden && hideButton.isPersistentMode) {
        dispatch_async(dispatch_get_main_queue(), ^{
            for (UIView *subview in contentView.subviews) {
                if (shouldHideView(subview)) {
                    if (![hideButton.hiddenViewsList containsObject:subview]) {
                        [hideButton.hiddenViewsList addObject:subview];
                        subview.alpha = 0.0;
                        subview.hidden = YES;
                    }
                }
            }
        });
    }
}
%end
// Hook AppDelegate 来初始化按钮
%hook AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL result = %orig;
    
    // 检查是否启用了悬浮按钮，默认为YES（显示）
    BOOL isEnabled = YES;
    if ([[NSUserDefaults standardUserDefaults] objectForKey:kEnableButtonKey] != nil) {
        isEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:kEnableButtonKey];
    } else {
        // 如果没有设置过，则设置默认值为YES
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kEnableButtonKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    
    // 只有当功能被启用时才创建按钮
    if (isEnabled) {
        // 创建按钮 - 不延迟，立即创建
        dispatch_async(dispatch_get_main_queue(), ^{
            CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
            CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
            
            hideButton = [[HideUIButton alloc] initWithFrame:CGRectMake(0, 0, 50, 50)];
            
            // 从NSUserDefaults获取上次位置，如果没有则放在左侧中间
            CGFloat lastX = [[NSUserDefaults standardUserDefaults] floatForKey:kLastPositionXKey];
            CGFloat lastY = [[NSUserDefaults standardUserDefaults] floatForKey:kLastPositionYKey];
            
            if (lastX > 0 && lastY > 0) {
                // 使用保存的位置
                hideButton.center = CGPointMake(lastX, lastY);
            } else {
                // 默认位置：左侧中间
                hideButton.center = CGPointMake(30, screenHeight / 2);
            }
            
            UIWindow *window = getKeyWindow();
            if (window) {
                [window addSubview:hideButton];
            } else {
                // 如果当前没有keyWindow，则等待一下再添加
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [getKeyWindow() addSubview:hideButton];
                });
            }
        });
    }
    
    return result;
}
%end
%ctor {
    // 注册信号处理
    signal(SIGSEGV, SIG_IGN);
    
    // 交换方法以实现预先隐藏
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        swizzleUIViewMethods();
    });
}