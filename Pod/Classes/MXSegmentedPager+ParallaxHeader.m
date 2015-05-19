// MXSegmentedPager+ParallaxHeader.m
//
// Copyright (c) 2015 Maxime Epain
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import <objc/runtime.h>

#import "MXSegmentedPager+ParallaxHeader.h"

typedef NS_ENUM(NSInteger, MXPanGestureDirection) {
    MXPanGestureDirectionNone  = 1 << 0,
    MXPanGestureDirectionRight = 1 << 1,
    MXPanGestureDirectionLeft  = 1 << 2,
    MXPanGestureDirectionUp    = 1 << 3,
    MXPanGestureDirectionDown  = 1 << 4
};

@interface MXScrollView : UIScrollView <UIScrollViewDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, assign) CGFloat minimumHeigth;
@property (nonatomic, strong) MXSegmentedPager *segmentedPager;
@property (nonatomic, strong) MXProgressBlock progressBlock;

@property (nonatomic, weak) NSArray *pages;
@end

@implementation MXScrollView {
    BOOL _isObserving;
    BOOL _isAtTop;
}

static void * const kMXScrollViewKVOContext = (void*)&kMXScrollViewKVOContext;
static NSString* const kContentOffsetKeyPath = @"contentOffset";
static NSString* const kPagesKeyPath = @"pages";

- (instancetype)init {
    self = [super init];
    if (self) {
        
        self.delegate = self;
        self.alwaysBounceVertical = NO;
        self.showsVerticalScrollIndicator = NO;
        self.directionalLockEnabled = YES;
        self.autoresizingMask =(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
        self.contentMode = UIViewContentModeTopRight;
        
        self.minimumHeigth = 0;
        [self addObserver:self forKeyPath:kContentOffsetKeyPath
                  options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld
                  context:kMXScrollViewKVOContext];
        
        _isObserving = YES;
        _isAtTop = YES;
    }
    return self;
}

#pragma mark Properties

- (void)setSegmentedPager:(MXSegmentedPager *)segmentedPager {
    @try {
        [_segmentedPager removeObserver:self forKeyPath:kPagesKeyPath context:kMXScrollViewKVOContext];
    }
    @catch (NSException *exception) {
        NSLog(@"Exception while removing observer: %@", exception);
    }
    @finally {
        _segmentedPager = segmentedPager;
        [_segmentedPager addObserver:self forKeyPath:kPagesKeyPath options:NSKeyValueObservingOptionNew context:kMXScrollViewKVOContext];
    }
}

- (void)setPages:(NSArray *)pages {
    [self removeScrollObservers];
    _pages = pages;
    [self addScrollObservers];
}

#pragma mark <UIScrollViewDelegate>

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    
    if ((self.contentOffset.y >= -self.minimumHeigth)) {
        self.contentOffset = CGPointMake(self.contentOffset.x, -self.minimumHeigth);
    }

    [scrollView shouldPositionParallaxHeader];
    
    if (self.progressBlock) {
        self.progressBlock(scrollView.parallaxHeader.progress);
    }
}

#pragma mark <UIGestureRecognizerDelegate>

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer{
    
    if ([gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
        MXPanGestureDirection direction = [self getDirectionOfPanGestureRecognizer:(UIPanGestureRecognizer*)gestureRecognizer];
        
        if (direction == MXPanGestureDirectionLeft || direction == MXPanGestureDirectionRight) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

#pragma mark Private methods

- (MXPanGestureDirection) getDirectionOfPanGestureRecognizer:(UIPanGestureRecognizer*) panGestureRecognizer {
    
    CGPoint velocity = [panGestureRecognizer velocityInView:self];
    CGFloat absX = fabs(velocity.x);
    CGFloat absY = fabs(velocity.y);
    
    if (absX > absY) {
        return (velocity.x > 0)? MXPanGestureDirectionRight : MXPanGestureDirectionLeft;
    }
    else if (absX < absY) {
        return (velocity.y > 0)? MXPanGestureDirectionDown : MXPanGestureDirectionUp;
    }
    return MXPanGestureDirectionNone;
}

#pragma mark KVO

- (void) addScrollObservers {
    
    for (UIView<MXPageProtocol> *page in _pages) {
        if ([page respondsToSelector:@selector(addScrollObserver:forKeyPath:options:context:)]) {
            [page addScrollObserver:self
                         forKeyPath:kContentOffsetKeyPath
                            options:NSKeyValueObservingOptionOld|NSKeyValueObservingOptionNew
                            context:kMXScrollViewKVOContext];
        }
    }
}

- (void) removeScrollObservers {
    
    for (UIView<MXPageProtocol> *page in _pages) {
        @try {
            if ([page respondsToSelector:@selector(removeScrollObserver:forKeyPath:context:)]) {
                [page removeScrollObserver:self
                                forKeyPath:kContentOffsetKeyPath
                                   context:kMXScrollViewKVOContext];
            }
        }
        @catch (NSException *exception) {
            NSLog(@"Exception while removing observer: %@", exception);
        }
    }
}

//This is where the magic happens...
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    
    if (context == kMXScrollViewKVOContext && [keyPath isEqualToString:kContentOffsetKeyPath]) {
        
        CGFloat delta = [[change objectForKey:NSKeyValueChangeOldKey] CGPointValue].y;
        delta -= [[change objectForKey:NSKeyValueChangeNewKey] CGPointValue].y;
        
        if (_isObserving && object == self) {
            
            //Adjust self scroll offset
            if (!_isAtTop) {
                if (self.contentOffset.y + delta >= -self.minimumHeigth && !_isAtTop) {
                    [self scrollView:self setContentOffset:CGPointMake(self.contentOffset.x, -self.minimumHeigth)];
                }
                else if (delta > 0){
                    [self scrollView:self setContentOffset:CGPointMake(self.contentOffset.x, self.contentOffset.y + delta)];
                }
            }
        }
        else if (_isObserving && [object isKindOfClass:[UIScrollView class]]) {
            
            //Adjust the observed scrollview's content offset
            UIScrollView *scrollView = object;
            _isAtTop = (scrollView.contentOffset.y <= -scrollView.contentInset.top);
            
            //Manage scroll up
            if (self.contentOffset.y < -self.minimumHeigth && !_isAtTop && delta < 0) {
                [self scrollView:scrollView setContentOffset:[[change objectForKey:NSKeyValueChangeOldKey] CGPointValue]];
            }
            //Disable bouncing when scroll down
            if (_isAtTop) {
                [self scrollView:scrollView setContentOffset:CGPointMake(scrollView.contentOffset.x, -scrollView.contentInset.top)];
            }
        }
    }
    else if (context == kMXScrollViewKVOContext && [keyPath isEqualToString:kPagesKeyPath]) {
        self.pages = self.segmentedPager.pages;
        self.contentSize = CGSizeMake(self.frame.size.width, self.frame.size.height + self.parallaxHeader.frame.size.height - self.minimumHeigth);
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void) scrollView:(UIScrollView*)scrollView setContentOffset:(CGPoint)offset {
    _isObserving = NO;
    scrollView.contentOffset = offset;
    _isObserving = YES;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

@interface MXSegmentedPager ()
@property (nonatomic, strong) MXScrollView * scrollView;
@property (nonatomic, assign) BOOL changeContainerFrame;
@end

@implementation MXSegmentedPager (ParallaxHeader)

static void * const kMXSegmentedPagerKVOContext = (void*)&kMXSegmentedPagerKVOContext;
static NSString* const kFrameKeyPath = @"frame";
static NSString* const kSegmentedControlPositionKeyPath = @"segmentedControlPosition";

- (void)setParallaxHeaderView:(UIView *)view mode:(VGParallaxHeaderMode)mode height:(CGFloat)height {
    [self.scrollView setParallaxHeaderView:view mode:mode height:height];
}

#pragma mark Properties

- (MXScrollView *)scrollView {
    MXScrollView *_scrollView = objc_getAssociatedObject(self, @selector(scrollView));
    if (!_scrollView) {
        
        // Create scroll-view
        _scrollView = [[MXScrollView alloc] init];
        _scrollView.segmentedPager = self;
        
        //Organize subviews
        [self addSubview:_scrollView];
        [_scrollView addSubview:self.container];
        if(self.segmentedControlPosition == MXSegmentedControlPositionTop) {
            [_scrollView addSubview:self.segmentedControl];
        }
        
        //Add constraints to the scroll-view
        _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
        NSDictionary *binding  = @{@"v" : _scrollView};
        [self addConstraints:[NSLayoutConstraint
                              constraintsWithVisualFormat:@"H:|-0-[v]-0-|"
                              options:NSLayoutFormatDirectionLeadingToTrailing
                              metrics:nil
                              views:binding]];
        
        [self addConstraints:[NSLayoutConstraint
                              constraintsWithVisualFormat:@"V:|-0-[v]-0-|"
                              options:NSLayoutFormatDirectionLeadingToTrailing
                              metrics:nil
                              views:binding]];
        
        // Add KVO
        [self.container addObserver:self forKeyPath:kFrameKeyPath options:NSKeyValueObservingOptionNew context:kMXSegmentedPagerKVOContext];
        [self addObserver:self forKeyPath:kSegmentedControlPositionKeyPath options:NSKeyValueObservingOptionNew context:kMXSegmentedPagerKVOContext];
        
        self.changeContainerFrame = YES;
        
        objc_setAssociatedObject(self, @selector(scrollView), _scrollView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return _scrollView;
}

- (void)setScrollView:(MXScrollView *)scrollView {
    objc_setAssociatedObject(self, @selector(scrollView), scrollView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (VGParallaxHeader *)parallaxHeader {
    return self.scrollView.parallaxHeader;
}

- (CGFloat)minimumHeaderHeight {
    return self.scrollView.minimumHeigth;
}

- (void)setMinimumHeaderHeight:(CGFloat)minimumHeaderHeight {
    self.scrollView.minimumHeigth = minimumHeaderHeight;
}

- (MXProgressBlock)progressBlock {
    return self.scrollView.progressBlock;
}

- (void)setProgressBlock:(MXProgressBlock)progressBlock {
    self.scrollView.progressBlock = progressBlock;
}

- (BOOL)changeContainerFrame {
    NSNumber *number = objc_getAssociatedObject(self, @selector(changeContainerFrame));
    return [number boolValue];
}

- (void)setChangeContainerFrame:(BOOL)changeContainerFrame {
    NSNumber *number = [NSNumber numberWithBool:changeContainerFrame];
    objc_setAssociatedObject(self, @selector(changeContainerFrame), number , OBJC_ASSOCIATION_RETAIN);
}

#pragma mark KVO 

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == kMXSegmentedPagerKVOContext) {
        if ([keyPath isEqualToString:kFrameKeyPath]) {
        
            if (self.changeContainerFrame) {
                self.changeContainerFrame = NO;
                
                CGFloat height = self.scrollView.frame.size.height;
                height -= self.segmentedControl.frame.size.height;
                height -= self.scrollView.minimumHeigth;
                
                self.container.frame = (CGRect){
                    .origin         = self.container.frame.origin,
                    .size.width     = self.container.frame.size.width,
                    .size.height    = height
                };
                
                self.changeContainerFrame = YES;
            }
        }
        else if ([keyPath isEqualToString:kSegmentedControlPositionKeyPath]) {
            if(self.segmentedControlPosition == MXSegmentedControlPositionBottom) {
                [self addSubview:self.segmentedControl];
            }
            else {
                [self.scrollView addSubview:self.segmentedControl];
            }
        }
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

@implementation UIScrollView (MXSegmentedPager)

#pragma mark <MXPageProtocol>

- (void)addScrollObserver:(NSObject *)observer
               forKeyPath:(NSString *)keyPath
                  options:(NSKeyValueObservingOptions)options
                  context:(void *)context {
    [self addObserver:observer forKeyPath:keyPath options:options context:context];
}

- (void)removeScrollObserver:(NSObject *)observer
                  forKeyPath:(NSString *)keyPath
                     context:(void *)context {
    [self removeObserver:observer forKeyPath:keyPath context:context];
}

@end

@implementation UIWebView (MXSegmentedPager)

#pragma mark <MXPageProtocol>

- (void)addScrollObserver:(NSObject *)observer
               forKeyPath:(NSString *)keyPath
                  options:(NSKeyValueObservingOptions)options
                  context:(void *)context {
    [self.scrollView addScrollObserver:observer forKeyPath:keyPath options:options context:context];
}

- (void)removeScrollObserver:(NSObject *)observer
                  forKeyPath:(NSString *)keyPath
                     context:(void *)context{
    [self.scrollView removeScrollObserver:observer forKeyPath:keyPath context:context];
}

@end
