//
//  TPMusicPlayerViewController.m
//  Tanplay
//
//  Created by on 5/31/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "TPMusicPlayerViewController.h"
#import "UIImageView+Reflection.h"
#import "NSDateFormatter+Duration.h"
#import <MediaPlayer/MediaPlayer.h>
#import "AutoScrollLabel.h"
#import <QuartzCore/QuartzCore.h>

@implementation AVPlayer(singleton)

+ (AVPlayer *)sharedAVPlayer
{
    static AVPlayer *player = nil;
    @synchronized(self)
    {
        if(player == nil)
            player = [[AVPlayer alloc] init];
    }
    return player;
}

@end

@interface TPMusicPlayerViewController()

-(void)setScrobbleUI:(BOOL)scrobbleState;
-(void)adjustPlayButtonState;
-(void)changeTrack:(NSUInteger)newTrack;
-(void)updateTrackDisplay;
-(void)adjustDirectionalButtonStates;
-(void)addAirplayPicker;
-(void)updateSeekUI;

@property (nonatomic, retain) IBOutlet UISlider* volumeSlider; // Volume Slider
@property (nonatomic, retain) IBOutlet UISlider* progressSlider; // Progress Slider buried in the Progress View

@property (nonatomic, retain) IBOutlet AutoScrollLabel* trackTitleLabel; // The Title Label
@property (nonatomic, retain) IBOutlet AutoScrollLabel* albumTitleLabel; // Album Label
@property (nonatomic, retain) IBOutlet AutoScrollLabel* artistNameLabel; // Artist Name Label

@property (nonatomic, retain) IBOutlet UIToolbar* controlsToolbar; // Encapsulates the Play, Forward, Rewind buttons

@property (nonatomic, retain) IBOutlet UIBarButtonItem *actionButton; // retain, since controller keeps a reference while it might be detached from view hierarchy
@property (nonatomic, retain) IBOutlet UIBarButtonItem *backButton; // retain, since controller keeps a reference while it might be detached from view hierarchy

@property (nonatomic, retain) IBOutlet UIBarButtonItem* rewindButton; // Previous Track
@property (nonatomic, retain) IBOutlet UIBarButtonItem* fastForwardButton; // Next Track
@property (nonatomic, retain) IBOutlet UIBarButtonItem* playButton; // Play

@property (nonatomic, retain) IBOutlet UIImageView* albumArtImageView; // Album Art Image View
@property (nonatomic, retain) IBOutlet UIImageView* albumArtReflection; // It's reflection

@property (nonatomic, retain) NSTimer* playbackTickTimer; // Ticks each seconds when playing.

@property (nonatomic, retain) UITapGestureRecognizer* coverArtGestureRecognizer; // Tap Recognizer used to dim in / out the scrobble overlay.

@property (nonatomic, retain) IBOutlet UIView* scrobbleOverlay; // Overlay that serves as a container for all components visible only in scrobble-mode
@property (nonatomic, retain) IBOutlet UILabel* timeElapsedLabel; // Elapsed Time Label
@property (nonatomic, retain) IBOutlet UILabel* timeRemainingLabel; // Remaining Time Label
@property (nonatomic, retain) IBOutlet UIButton* shuffleButton; // Shuffle Button
@property (nonatomic, retain) IBOutlet UIButton* repeatButton; // Repeat button
@property (nonatomic, retain) IBOutlet UIButton *downloadButton; // Download button
@property (nonatomic, retain) IBOutlet UILabel* scrobbleHelpLabel; // The Scrobble Usage hint Label
@property (nonatomic, retain) IBOutlet UILabel* numberOfTracksLabel; // Track x of y or the scrobble speed
@property (nonatomic, retain) IBOutlet UIImageView* scrobbleHighlightShadow; // It's reflection


@property (nonatomic) CGFloat currentTrackLength; // The Length of the currently playing track
@property (nonatomic) NSUInteger numberOfTracks; // Number of tracks

@property (nonatomic) BOOL scrobbling; // Whether the player is currently scrobbling

@property (nonatomic) BOOL imageIsPlaceholder; // Whether the currently shown image is a placeholder
@property (nonatomic) BOOL lastDirectionChangePositive; // Whether the last direction change was positive.

@property (nonatomic, retain) IBOutlet UINavigationItem* navigationItem;

@end

@implementation TPMusicPlayerViewController

@synthesize trackTitleLabel;
@synthesize albumTitleLabel;
@synthesize artistNameLabel;
@synthesize actionButton;
@synthesize backButton;
@synthesize rewindButton;
@synthesize fastForwardButton;
@synthesize playButton;
@synthesize volumeSlider;
@synthesize progressSlider;
@synthesize controlsToolbar;
@synthesize albumArtImageView;
@synthesize albumArtReflection;
@synthesize delegate;
@synthesize dataSource;
@synthesize currentTrack;
@synthesize currentPlaybackPosition;
@synthesize playbackTickTimer;
@synthesize playing;
@synthesize scrobbleOverlay;
@synthesize timeElapsedLabel;
@synthesize timeRemainingLabel;
@synthesize shuffleButton;
@synthesize repeatButton;
@synthesize downloadButton;
@synthesize coverArtGestureRecognizer;
@synthesize currentTrackLength;
@synthesize numberOfTracks;
@synthesize scrobbling;
@synthesize scrobbleHelpLabel;
@synthesize numberOfTracksLabel;
@synthesize scrobbleHighlightShadow;
@synthesize repeatMode;
@synthesize shuffling;
@synthesize lastDirectionChangePositive;
@synthesize imageIsPlaceholder;
@synthesize shouldHideNextTrackButtonAtBoundary;
@synthesize shouldHidePreviousTrackButtonAtBoundary;
@synthesize navigationItem;
@synthesize preferredSizeForCoverArt;
@synthesize isChannelMode;


- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        self.isChannelMode = YES;
    }
    return self;   
}

+ (TPMusicPlayerViewController *)sharedMusicPlayerViewController
{
    static TPMusicPlayerViewController *controller = nil;
    @synchronized(self)
    {
        if(controller == nil)
        {
            controller = [[TPMusicPlayerViewController alloc] initWithNibName:@"TPMusicPlayerViewController" bundle:nil];
        }
    }
    return controller;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Scrobble Ovelray alpha should be 0, initialize the gesture recognizer
    self.scrobbleOverlay.alpha = 0;
    self.coverArtGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(coverArtTapped:)];
    [self.albumArtImageView addGestureRecognizer:self.coverArtGestureRecognizer];
    
    // Knobs for the sliders
    
    UIImage* sliderBlueTrack = [[UIImage imageNamed:@"VolumeBlueTrack.png"] stretchableImageWithLeftCapWidth:5.0 topCapHeight:0];
    UIImage* slideWhiteTrack = [[UIImage imageNamed:@"VolumeWhiteTrack.png"] stretchableImageWithLeftCapWidth:5.0 topCapHeight:0];
    UIImage* knob = [UIImage imageNamed:@"VolumeKnob"];
    
    [[UISlider appearanceWhenContainedIn:[self class], nil] setThumbImage:knob forState:UIControlStateNormal];

    [[UISlider appearance] setMinimumTrackImage:sliderBlueTrack forState:UIControlStateNormal];
    [[UISlider appearance] setMaximumTrackImage:slideWhiteTrack forState:UIControlStateNormal];

    // The Original Toolbar is 48px high in the iPod/Music app
    CGRect toolbarRect = self.controlsToolbar.frame;
    toolbarRect.size.height = 48;
    self.controlsToolbar.frame = toolbarRect;

    // Set UI to non-scrobble
    [self setScrobbleUI:NO];
    
    // Set up labels. These are autoscrolling and need code-base setup.
    [self.artistNameLabel setShadowColor:[UIColor blackColor]];
    [self.artistNameLabel setShadowOffset:CGSizeMake(0, -1)];
    [self.artistNameLabel setTextColor:[UIColor lightTextColor]];
    [self.artistNameLabel setFont:[UIFont boldSystemFontOfSize:12]];

    
    [self.albumTitleLabel setShadowColor:[UIColor blackColor]];
    [self.albumTitleLabel setShadowOffset:CGSizeMake(0, -1)];
    [self.albumTitleLabel setTextColor:[UIColor lightTextColor]];
    [self.albumTitleLabel setFont:[UIFont boldSystemFontOfSize:12]];

    self.trackTitleLabel.textColor = [UIColor whiteColor];
    [self.trackTitleLabel setFont:[UIFont boldSystemFontOfSize:12]];
    [self addAirplayPicker];
    //[self coverArtTapped:nil];
}

- (void)viewDidUnload
{
    self.actionButton = nil;
    self.backButton = nil;
    [super viewDidUnload];
    self.coverArtGestureRecognizer = nil;
    // Release any retained subviews of the main view.
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        return UIInterfaceOrientationIsPortrait(interfaceOrientation);
    } else {
        return YES;
    }
}

- (void)updateChannelModeUI
{
    if(self.isChannelMode)
    {
        self.downloadButton.hidden = NO;
        self.repeatButton.hidden = YES;
        self.shuffleButton.hidden = YES;
    }
    else
    {
        self.downloadButton.hidden = YES;
        self.repeatButton.hidden = NO;
        self.shuffleButton.hidden = NO;
    }   
}

- (void)setIsChannelMode:(BOOL)_isChannelMode
{
    isChannelMode = _isChannelMode;
    [self updateChannelModeUI];
}

-(void)setDelegate:(id<TPMusicPlayerDelegate>)value {
    self->delegate = value;
    self.navigationItem.rightBarButtonItem =
        [self.delegate respondsToSelector:@selector(musicPlayerActionRequested:)]
        ? self.actionButton
        : nil;
    
    self.navigationItem.leftBarButtonItem =
        [self.delegate respondsToSelector:@selector(musicPlayerBackRequested:)]
        ? self.backButton
        : nil;
}


#pragma mark - Playback Management

/**
 * Updates the UI to match the current track by requesting the information from the datasource.
 */
-(void)updateUIForCurrentTrack {
    
    self.artistNameLabel.text = [self.dataSource musicPlayer:self artistForTrack:self.currentTrack];
    self.trackTitleLabel.text = [self.dataSource musicPlayer:self titleForTrack:self.currentTrack];
    self.albumTitleLabel.text = [self.dataSource musicPlayer:self albumForTrack:self.currentTrack];

    self.currentTrackLength = [self.dataSource musicPlayer:self lengthForTrack:self.currentTrack];
    self.numberOfTracks = [self.dataSource numberOfTracksInPlayer:self];
    self.progressSlider.maximumValue = self.currentTrackLength;
    self.progressSlider.minimumValue = 0;
    
    // We only request the coverart if the delegate responds to it.
    if ( [self.dataSource respondsToSelector:@selector(musicPlayer:artworkForTrack:receivingBlock:)]) {
        
        // Copy the current track to another variable, otherwise we would just access the current one.
        NSUInteger track = self.currentTrack;
         
        // Placeholder as long as we are loading
        self.albumArtImageView.image = [UIImage imageNamed:@"noartplaceholder.png"];
        self.albumArtReflection.image = [self.albumArtImageView reflectedImageWithHeight:self.albumArtReflection.frame.size.height];
        self.imageIsPlaceholder = YES;
        
//        CATransition* transition = [CATransition animation];
//        transition.type = kCATransitionPush;
//        transition.subtype = self.lastDirectionChangePositive ? kCATransitionFromRight : kCATransitionFromLeft;
//        [transition setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
//        [[self.albumArtImageView layer] addAnimation:transition forKey:@"SlideOutandInImagek"];
//        [[self.albumArtReflection layer] addAnimation:transition forKey:@"SlideOutandInImagek"];

        // Request the image.
        [self.dataSource musicPlayer:self artworkForTrack:self.currentTrack receivingBlock:^(UIImage *image, NSError *__autoreleasing *error) {

            if ( track == self.currentTrack )
            {
                // If there is no image given, use the placeholder

                if ( image  != nil )
                {
                    dispatch_async(dispatch_get_main_queue(), ^{
                    self.albumArtImageView.image = image;
                    self.albumArtReflection.image = [self.albumArtImageView reflectedImageWithHeight:self.albumArtReflection.frame.size.height];
                    });
                }
            } 
            else 
            {
                NSLog(@"Discarded Response, Invalid for this cycle.");
            }
        }];

        
    } else {
        // Otherwise, we'll stick with the placeholder.
        self.albumArtImageView.image = [UIImage imageNamed:@"noartplaceholder.png"];
        self.albumArtReflection.image = [self.albumArtImageView reflectedImageWithHeight:self.albumArtReflection.frame.size.height];
    }
}




-(void)play {
    if ( !self.playing ){
        self->playing = YES;

        self.playbackTickTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(playbackTick:) userInfo:nil repeats:YES];
        
        if ( [self.delegate respondsToSelector:@selector(musicPlayerDidStartPlaying:)] ){
            [self.delegate musicPlayerDidStartPlaying:self];
        }
        [self adjustPlayButtonState];
    }
}

-(void)pause {
    if ( self.playing ){
        self->playing = NO;        

        [self.playbackTickTimer invalidate];
        self.playbackTickTimer = nil;
        
        if ( [self.delegate respondsToSelector:@selector(musicPlayerDidStopPlaying:)] ){
            [self.delegate musicPlayerDidStopPlaying:self];
        }
        
        [self adjustPlayButtonState];

    }
}

-(void)next {
    self.lastDirectionChangePositive = YES;
    [self changeTrack:self->currentTrack+1];
}

-(void)previous {
    self.lastDirectionChangePositive = NO;

    [self changeTrack:self->currentTrack-1];
}

/*
 * Called when the player finished playing the current track. 
 */
-(void)currentTrackFinished {
    [self pause];
    if ( self.repeatMode != MPMusicRepeatModeOne ){
        [self next];
        [self play];

    } else {
        self->currentPlaybackPosition = 0;
        [self updateSeekUI];
        [self play];
    }
}

-(void)playTrack:(NSUInteger)track atPosition:(CGFloat)position volume:(CGFloat)volume {
    if(volume > 0)
        self.volume = volume;
    if(position > 0)
        self->currentPlaybackPosition = position;
    [self changeTrack:track];
    [self play];
}

/*
 * Changes the track to the new track given.
 */
-(void)changeTrack:(NSUInteger)newTrack {
    BOOL shouldChange = YES;
    if ( [self.delegate respondsToSelector:@selector(musicPlayer:shoulChangeTrack:) ]){
        shouldChange = [self.delegate musicPlayer:self shouldChangeTrack:newTrack];
    }
    
    if ( newTrack > numberOfTracks-1 ){
        shouldChange = NO;
        // If we can't next, stop the playback.
        self->currentPlaybackPosition = self.currentTrackLength;
        [self pause];
    }
    
    if ( shouldChange ){
        [self pause];
        
        // Update state to match new track
        self->currentPlaybackPosition = 0;
        self.currentTrack = newTrack;

        if ( [self.delegate respondsToSelector:@selector(musicPlayer:didChangeTrack:) ]){
            [self.delegate musicPlayer:self didChangeTrack:newTrack];
        }
                
        [self updateUIForCurrentTrack];
        [self updateSeekUI];
        [self updateTrackDisplay];
        [self adjustDirectionalButtonStates];
        [self play];
    }
}

/**
 * Reloads data from the data source and updates the player. If the player is currently playing, the playback is stopped.
 */
-(void)reloadData {
    if ( self.playing )
        [self pause];
    
    [self changeTrack:0];
    
}

/**
 * Tick method called each second when playing back.
 */
-(void)playbackTick:(id)unused {
    // Only tick forward if not scrobbling.
    if ( !self.scrobbling ){
        if ( self->currentPlaybackPosition+1.0 > self.currentTrackLength ){
            [self currentTrackFinished];
        } else {
            self->currentPlaybackPosition += 1.0f;
            [self updateSeekUI];
        }
    }
}

/*
 * Updates the remaining and elapsed time label, as well as the progress bar's value
 */
-(void)updateSeekUI {
    NSString* elapsed = [NSDateFormatter formattedDuration:(long)self.currentPlaybackPosition];
    NSString* remaining = [NSDateFormatter formattedDuration:(self.currentTrackLength-self.currentPlaybackPosition)*-1];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.timeElapsedLabel.text =elapsed;
        self.timeRemainingLabel.text =remaining;
        self.progressSlider.value = self.currentPlaybackPosition;
    });
}

/*
 * Updates the Track Display ( Track 10 of 10 )
 */
-(void)updateTrackDisplay {
    if ( !self.scrobbling ){
        self.numberOfTracksLabel.text = [NSString stringWithFormat:@"Track %d of %d", self.currentTrack+1, self.numberOfTracks];
    }
}

-(void)updateRepeatButton {
    MPMusicRepeatMode currentMode = self->repeatMode;
    NSString* imageName = nil;
    switch (currentMode) {
        case MPMusicRepeatModeDefault:
            imageName = @"repeat_off.png";
            break;
        case MPMusicRepeatModeOne:
            imageName = @"repeat_on_1.png";
            break;
        case MPMusicRepeatModeAll:
            imageName = @"repeat_on.png";
            break;
    }
    if ( imageName )
        [self.repeatButton setImage:[UIImage imageNamed:imageName] forState:UIControlStateNormal];
}

-(void)addAirplayPicker
{
    MPVolumeView *volumeView = [[MPVolumeView alloc] init];
    [volumeView setShowsVolumeSlider:NO];
    //NSLog(@"%f, %f", volumeView.frame.size.width, volumeView.frame.size.height);
    volumeView.frame = CGRectMake(238, 370, 0, 0);
    for (UIButton *button in volumeView.subviews) 
    {
        if ([button isKindOfClass:[UIButton class]])
        {
            //[button setImage:[UIImage imageNamed:@"audio_btn_airplay_blue_h.png"] forState:UIControlStateNormal];
            [button setBounds:CGRectMake(0, 0, 43, 43)];
        }
    }
    [volumeView sizeToFit];
    [self.view addSubview:volumeView];
}

#pragma mark Repeat mode

-(void)setRepeatMode:(int)newRepeatMode {
    self->repeatMode = newRepeatMode;
    [self updateRepeatButton];
}

#pragma mark Shuffling ( Every day I'm )

-(void)setShuffling:(BOOL)newShuffling {
    self->shuffling = newShuffling;
    
    NSString* imageName = ( self.shuffling ? @"shuffle_on.png" : @"shuffle_off.png");
    [self.shuffleButton setImage:[UIImage imageNamed:imageName] forState:UIControlStateNormal];
}

#pragma mark - Volume

/*
 * Setting the volume really just changes the slider
 */
-(void)setVolume:(CGFloat)volume {
    self.volumeSlider.value = volume;
}

/*
 * The Volume value is the slider value
 */
-(CGFloat)volume {
    return self.volumeSlider.value;
}

#pragma mark - User Interface ACtions

-(IBAction)playAction:(UIBarButtonItem*)sender {
    if ( self.playing ){
        [self pause];
    } else {
        [self play];
    }
}

-(IBAction)nextAction:(id)sender {
    [self next];
}

-(IBAction)previousAction:(id)sender {
    [self previous];
}


/**
 * Called when the cover art is tapped. Either shows or hides the scrobble-ui
 */
-(IBAction)coverArtTapped:(id)sender {
    
    [self updateChannelModeUI];
    
    [UIView animateWithDuration:0.25 animations:^{
        if ( self.scrobbleOverlay.alpha == 0 ){
            [self.scrobbleOverlay setAlpha:1];
        } else {
            [self.scrobbleOverlay setAlpha:0];
        }
    }];
}



#pragma mark - Playback button state management

/*
 * Adjusts the directional buttons to comply with the shouldHide-Button settings.
 */
-(void)adjustDirectionalButtonStates {
    if ( self.currentTrack+1 == self.numberOfTracks && self.shouldHideNextTrackButtonAtBoundary ){
        self.fastForwardButton.enabled = NO;
    } else {
        self.fastForwardButton.enabled = YES;
    }
    
    if ( self.currentTrack == 0 && self.shouldHidePreviousTrackButtonAtBoundary ){
        self.rewindButton.enabled = NO;
    } else {
        self.rewindButton.enabled = YES;
    }
}

/*
 * Adjusts the state of the play button to match the current state of the player
 */
-(void)adjustPlayButtonState {
    if ( !self.playing ){
        self.playButton.image = [UIImage imageNamed:@"play.png"];
    } else {
        self.playButton.image = [UIImage imageNamed:@"pause.png"];
    }
}

-(void)setShouldHideNextTrackButtonAtBoundary:(BOOL)newShouldHideNextTrackButtonAtBoundary {
    self->shouldHideNextTrackButtonAtBoundary = newShouldHideNextTrackButtonAtBoundary;
    [self adjustDirectionalButtonStates];
}

-(void)setShouldHidePreviousTrackButtonAtBoundary:(BOOL)newShouldHidePreviousTrackButtonAtBoundary {
    self->shouldHidePreviousTrackButtonAtBoundary = newShouldHidePreviousTrackButtonAtBoundary;
    [self adjustDirectionalButtonStates];
}

#pragma mark - OBSlider delegate methods

/**
 * Called whenever the scrubber changes it's speed. Used to update the display of the scrobble speed.
 */
-(void)slider:(OBSlider *)slider didChangeScrubbingSpeed:(CGFloat)speed {
    if ( speed == 1.0 ){
        self.numberOfTracksLabel.text = @"Hi-Speed Scrubbing";
    } else if ( speed == 0.5 ){
        self.numberOfTracksLabel.text = @"Half-Speed Scrubbing";
        
    }else if ( speed == 0.25 ){
        self.numberOfTracksLabel.text = @"Quarter-Speed Scrubbing";
        
    } else {
        self.numberOfTracksLabel.text = @"Fine Scrubbing";
    }
}

/**
 * Dims away the repeat and shuffle button
 */
-(void)sliderDidBeginScrubbing:(OBSlider *)slider {
    self.scrobbling = YES;
    //[self setScrobbleUI:YES];

}

/**
 * Shows the repeat and shuffle button and hides the scrobble help
 */
-(void)sliderDidEndScrubbing:(OBSlider *)slider {
    self.scrobbling = NO;
    //[self setScrobbleUI:NO];
    [self updateTrackDisplay];
}

/*
 * Updates the UI according to the current scrobble state given.
 */
-(void)setScrobbleUI:(BOOL)scrobbleState {
    float alpha = ( scrobbleState ? 1 : 0 );
    [UIView animateWithDuration:0.25 animations:^{
        self.repeatButton.alpha = 1-alpha;
        self.shuffleButton.alpha = 1-alpha;
        self.scrobbleHelpLabel.alpha = alpha;
        self.scrobbleHighlightShadow.alpha = alpha;
    }];
}

-(void)setHelpLabelUI
{
    self.scrobbleHelpLabel.alpha = 1;
    self.scrobbleHighlightShadow.alpha = 1;
    [UIView animateWithDuration:2.00 animations:^{
        self.scrobbleHelpLabel.alpha = 0;
        self.scrobbleHighlightShadow.alpha = 0;
    }];
}

/*
 * Action triggered by the continous track progress slider
 */
-(IBAction)sliderValueChanged:(id)slider {
    self->currentPlaybackPosition = self.progressSlider.value;
    
    if ( [self.delegate respondsToSelector:@selector(musicPlayer:didSeekToPosition:)]) {
        [self.delegate musicPlayer:self didSeekToPosition:self->currentPlaybackPosition];
    }
    
    [self updateSeekUI];
    
}

/*
 * Action triggered by the volume slider
 */
-(IBAction)volumeSliderValueChanged:(id)sender {
    if ( [self.delegate respondsToSelector:@selector(musicPlayer:didChangeVolume:)]) {
        [self.delegate musicPlayer:self didChangeVolume:self.volumeSlider.value];
    }
}

/*
 * Action triggered by the repeat mode button
 */
-(IBAction)repeatModeButtonAction:(id)sender{
    MPMusicRepeatMode currentMode = self.repeatMode;
    switch (currentMode) {
        case MPMusicRepeatModeDefault:
            self.repeatMode = MPMusicRepeatModeAll;
            break;
        case MPMusicRepeatModeOne:
            self.repeatMode = MPMusicRepeatModeDefault;
            break;
        case MPMusicRepeatModeAll:
            self.repeatMode = MPMusicRepeatModeOne ;
            break;
        default:
            self.repeatMode = MPMusicRepeatModeOne;
            break;
    }
    if ( [self.delegate respondsToSelector:@selector(musicPlayer:didChangeRepeatMode:)]) {
        [self.delegate musicPlayer:self didChangeRepeatMode:self.repeatMode];
    }
}

/*
 * Changes the shuffle mode and calls the delegate
 */
-(IBAction)shuffleButtonAction:(id)sender {
    self.shuffling = !self.shuffling;
    if ( [self.delegate respondsToSelector:@selector(musicPlayer:didChangeShuffleState:)]) {
        [self.delegate musicPlayer:self didChangeShuffleState:self.shuffling];
    }
}

- (IBAction)backButtonAction:(id)sender {
    if ( [self.delegate respondsToSelector:@selector(musicPlayerBackRequested:)]) {
        [self.delegate musicPlayerBackRequested:self];
    }
}

- (IBAction)downloadButtonAction:(id)sender {
    if ( [self.delegate respondsToSelector:@selector(musicPlayerDownloadRequested:)]) 
    {
        if([self.delegate musicPlayerDownloadRequested:self])
        {
            self.scrobbleHelpLabel.text = @"成功加入下载列表";
            [self setHelpLabelUI];
        }
        else
        {
            self.scrobbleHelpLabel.text = @"该歌曲已经在下载列表中";
            [self setHelpLabelUI];
        }
    }
}

/*
 * Just forward the action message to the delegate
 */
-(IBAction)actionButtonAction:(id)sender {
    if ( [self.delegate respondsToSelector:@selector(musicPlayerActionRequested:)]) {
        [self.delegate musicPlayerActionRequested:self];
    }
}

#pragma mark Cover Art resolution handling

-(CGSize)preferredSizeForCoverArt {
    CGFloat scale = UIScreen.mainScreen.scale;
    CGSize points = self.albumArtImageView.frame.size;
    return  CGSizeMake(points.width * scale, points.height * scale);
}

-(CGFloat)displayScale {
    return [UIScreen mainScreen].scale;
}


@end
