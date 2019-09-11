//
//  VideoFiltersVC.swift
//  YPImagePicker
//
//  Created by Nik Kov || nik-kov.com on 18.04.2018.
//  Copyright © 2018 Yummypets. All rights reserved.
//

import UIKit
import Photos
import PryntTrimmerView

public class YPVideoFiltersVC: UIViewController, IsMediaFilterVC {
    
    @IBOutlet weak var trimBottomItem: YPMenuItem!
    @IBOutlet weak var coverBottomItem: YPMenuItem!
    @IBOutlet weak var timelineLabel: UILabel!
    
    @IBOutlet weak var videoView: YPVideoView!
    @IBOutlet weak var trimmerView: TrimmerView!
    
    @IBOutlet weak var coverImageView: UIImageView!
    @IBOutlet weak var coverThumbSelectorView: ThumbSelectorView!
    
    public var inputVideo: YPMediaVideo!
    public var inputAsset: AVAsset { return AVAsset(url: inputVideo.url) }
    
    private var playbackTimeCheckerTimer: Timer?
    private var imageGenerator: AVAssetImageGenerator?
    private var isFromSelectionVC = false
    
    open var didSave: ((YPMediaItem) -> Void)?
    open var didCancel: (() -> Void)?
    
    /// Designated initializer
    public class func initWith(video: YPMediaVideo,
                               isFromSelectionVC: Bool) -> YPVideoFiltersVC {
        let vc = YPVideoFiltersVC(nibName: "YPVideoFiltersVC", bundle: Bundle(for: YPVideoFiltersVC.self))
        vc.inputVideo = video
        vc.isFromSelectionVC = isFromSelectionVC
        
        return vc
    }
    
    // MARK: - Live cycle
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        
        trimmerView.mainColor = YPConfig.colors.trimmerMainColor
        trimmerView.handleColor = YPConfig.colors.trimmerHandleColor
        trimmerView.positionBarColor = YPConfig.colors.positionLineColor
        trimmerView.maxDuration = YPConfig.video.trimmerMaxDuration
        trimmerView.minDuration = YPConfig.video.trimmerMinDuration
        
        coverThumbSelectorView.thumbBorderColor = YPConfig.colors.coverSelectorBorderColor
        
        trimBottomItem.textLabel.text = YPConfig.wordings.trim
        if YPConfig.video.showCoverButton {
            coverBottomItem.textLabel.text = YPConfig.wordings.cover
            coverBottomItem.button.addTarget(self, action: #selector(selectCover), for: .touchUpInside)
        } else {
            coverBottomItem.isHidden = true
        }
        
        trimBottomItem.button.addTarget(self, action: #selector(selectTrim), for: .touchUpInside)
        
        // Remove the default and add a notification to repeat playback from the start
        videoView.removeReachEndObserver()
        NotificationCenter.default
            .addObserver(self,
                         selector: #selector(itemDidFinishPlaying(_:)),
                         name: .AVPlayerItemDidPlayToEndTime,
                         object: nil)
        
        // Set initial video cover
        imageGenerator = AVAssetImageGenerator(asset: self.inputAsset)
        imageGenerator?.appliesPreferredTrackTransform = true
        imageGenerator?.requestedTimeToleranceAfter = CMTime.zero
        imageGenerator?.requestedTimeToleranceBefore = CMTime.zero
        didChangeThumbPosition(CMTime(seconds: 1, preferredTimescale: 1))
        if YPConfig.video.showTimeline {
            updateTimeline()
        }
        
        // Navigation bar setup
        title = YPConfig.wordings.trim
        if isFromSelectionVC {
            navigationItem.leftBarButtonItem = UIBarButtonItem(title: YPConfig.wordings.cancel,
                                                               style: .plain,
                                                               target: self,
                                                               action: #selector(cancel))
        }
        setupRightBarButtonItem()
    }
    
    override public func viewDidAppear(_ animated: Bool) {
        trimmerView.asset = inputAsset
        trimmerView.delegate = self
        
        coverThumbSelectorView.asset = inputAsset
        coverThumbSelectorView.delegate = self
        
        selectTrim()
        videoView.loadVideo(inputVideo)
        
        super.viewDidAppear(animated)
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPlaybackTimeChecker()
        videoView.stop()
    }
    
    func setupRightBarButtonItem() {
        let rightBarButtonTitle = isFromSelectionVC ? YPConfig.wordings.done : YPConfig.wordings.next
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: rightBarButtonTitle,
                                                            style: .done,
                                                            target: self,
                                                            action: #selector(save))
        navigationItem.rightBarButtonItem?.tintColor = YPConfig.colors.tintColor
    }
    
    // MARK: - Top buttons
    
    @objc public func save() {
        guard let didSave = didSave else { return print("Don't have saveCallback") }
        navigationItem.rightBarButtonItem = YPLoaders.defaultLoader
        
        do {
            let asset = AVURLAsset(url: inputVideo.url)
            let trimmedAsset = try asset
                .assetByTrimming(startTime: trimmerView.startTime ?? CMTime.zero,
                                 endTime: trimmerView.endTime ?? inputAsset.duration)
            
            // Looks like file:///private/var/mobile/Containers/Data/Application
            // /FAD486B4-784D-4397-B00C-AD0EFFB45F52/tmp/8A2B410A-BD34-4E3F-8CB5-A548A946C1F1.mov
            let destinationURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingUniquePathComponent(pathExtension: YPConfig.video.fileType.fileExtension)
            
            print("trimmed result duration \(String(describing:trimmedAsset.duration.seconds))")
            
            try trimmedAsset.export(to: destinationURL) { [weak self] in
                guard let strongSelf = self else { return }
                
                DispatchQueue.main.async {
                    let resultVideo = YPMediaVideo(thumbnail: strongSelf.coverImageView.image!,
                                                   videoURL: destinationURL, fromCamera: strongSelf.inputVideo.fromCamera, asset: strongSelf.inputVideo.asset)
                    didSave(YPMediaItem.video(v: resultVideo))
                    strongSelf.setupRightBarButtonItem()
                }
            }
        } catch let error {
            print("💩 \(error)")
        }
    }
    
    @objc func cancel() {
        didCancel?()
    }
    
    // MARK: - Bottom buttons
    
    @objc public func selectTrim() {
        title = YPConfig.wordings.trim
        
        trimBottomItem.select()
        coverBottomItem.deselect()
        
        if YPConfig.video.showTimeline {
            timelineLabel.isHidden = false
        }
        trimmerView.isHidden = false
        videoView.isHidden = false
        coverImageView.isHidden = true
        coverThumbSelectorView.isHidden = true
    }
    
    @objc public func selectCover() {
        title = YPConfig.wordings.cover
        
        trimBottomItem.deselect()
        coverBottomItem.select()
        
        timelineLabel.isHidden = true
        trimmerView.isHidden = true
        videoView.isHidden = true
        coverImageView.isHidden = false
        coverThumbSelectorView.isHidden = false
        
        stopPlaybackTimeChecker()
        videoView.stop()
    }
    
    // MARK: - Various Methods
    
    // Updates the bounds of the cover picker if the video is trimmed
    // TODO: Now the trimmer framework doesn't support an easy way to do this.
    // Need to rethink a flow or search other ways.
    func updateCoverPickerBounds() {
        if let startTime = trimmerView.startTime,
            let endTime = trimmerView.endTime {
            if let selectedCoverTime = coverThumbSelectorView.selectedTime {
                let range = CMTimeRange(start: startTime, end: endTime)
                if !range.containsTime(selectedCoverTime) {
                    // If the selected before cover range is not in new trimeed range,
                    // than reset the cover to start time of the trimmed video
                }
            } else {
                // If none cover time selected yet, than set the cover to the start time of the trimmed video
            }
        }
    }
    
    // MARK: - Trimmer playback
    
    @objc func itemDidFinishPlaying(_ notification: Notification) {
        if let startTime = trimmerView.startTime {
            videoView.player.seek(to: startTime)
        }
    }
    
    func startPlaybackTimeChecker() {
        stopPlaybackTimeChecker()
        playbackTimeCheckerTimer = Timer
            .scheduledTimer(timeInterval: 0.05, target: self,
                            selector: #selector(onPlaybackTimeChecker),
                            userInfo: nil,
                            repeats: true)
    }
    
    func stopPlaybackTimeChecker() {
        playbackTimeCheckerTimer?.invalidate()
        playbackTimeCheckerTimer = nil
    }
    
    @objc func onPlaybackTimeChecker() {
        guard let startTime = trimmerView.startTime,
            let endTime = trimmerView.endTime else {
                return
        }
        
        let playBackTime = videoView.player.currentTime()
        trimmerView.seek(to: playBackTime)
        
        if playBackTime >= endTime {
            videoView.player.seek(to: startTime,
                                  toleranceBefore: CMTime.zero,
                                  toleranceAfter: CMTime.zero)
            trimmerView.seek(to: startTime)
        }
    }
    
    func updateTimeline() {
        var end = 0.0
        if let endTime = trimmerView.endTime {
            end = endTime.seconds
        } else {
            end = min(inputAsset.duration.seconds, trimmerView.maxDuration)
        }
//        let end = min((trimmerView.endTime ?? inputAsset.duration).seconds, trimmerView.maxDuration)
        let start = (trimmerView.startTime ?? CMTime.zero).seconds
//        let timeRange = CMTimeRangeFromTimeToTime(start: trimmerView.startTime ?? CMTime.zero, end: trimmerView.endTime ?? min(inputAsset.duration, CMTimeMake(value: Int64(trimmerView!.maxDuration), timescale: inputAsset.duration.timescale) ))
//
        let rawDuration = end-start
        print("start: \(String(describing: start))")
        print("end: \(String(describing: end))")

        let totalSeconds = round(rawDuration)
        print("raw duration \(rawDuration)")
//        print("time range duration seconds: \(timeRange.duration.seconds)")
//        print("time range duration: \(timeRange.duration)")
        print("start time: \(String(describing: trimmerView.startTime))")
        print("end time: \(String(describing: trimmerView.endTime))")
        
        
        
        let hours:Int = Int(totalSeconds / 3600)
        let minutes:Int = Int(totalSeconds.truncatingRemainder(dividingBy: 3600) / 60)
        let seconds:Int = Int(totalSeconds.truncatingRemainder(dividingBy: 60))
        
        var labelText = NSLocalizedString("Duration: %@", comment: "")
        if hours > 0 {
            labelText = String.localizedStringWithFormat(labelText, String(format: "%i:%02i:%02i", hours, minutes, seconds))
        } else {
            labelText = String.localizedStringWithFormat(labelText, String(format: "%02i:%02i", minutes, seconds))
        }
        
        timelineLabel.text = labelText
    }
}

// MARK: - TrimmerViewDelegate
extension YPVideoFiltersVC: TrimmerViewDelegate {
    public func positionBarStoppedMoving(_ playerTime: CMTime) {
        videoView.player.seek(to: playerTime, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero)
        videoView.play()
        startPlaybackTimeChecker()
        updateCoverPickerBounds()
    }
    
    public func didChangePositionBar(_ playerTime: CMTime) {
        print("didChangePositionBar")
        stopPlaybackTimeChecker()
        videoView.pause()
        videoView.player.seek(to: playerTime, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero)
        if YPConfig.video.showTimeline {
            updateTimeline()
        }
        
        let duration = (trimmerView.endTime! - trimmerView.startTime!).seconds
        print(duration)

    }
}

// MARK: - ThumbSelectorViewDelegate
extension YPVideoFiltersVC: ThumbSelectorViewDelegate {
    public func didChangeThumbPosition(_ imageTime: CMTime) {
        print(imageTime)
        imageGenerator?.generateCGImagesAsynchronously(forTimes: [imageTime as NSValue],
                                                       completionHandler: { (_, image, _, _, _) in
                                                        guard let image = image else {
                                                            return
                                                        }
                                                        DispatchQueue.main.async {
                                                            self.imageGenerator?.cancelAllCGImageGeneration()
                                                            let uiimage = UIImage(cgImage: image)
                                                            self.coverImageView.image = uiimage
                                                        }
        })
        //        if let imageGenerator = imageGenerator,
        //            let imageRef = try? imageGenerator.copyCGImage(at: imageTime, actualTime: nil) {
        //            coverImageView.image = coverThumbSelectorView.ima
        //        }
    }
}
