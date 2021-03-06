//
//  FSCameraView.swift
//  Fusuma
//
//  Created by Yuta Akizuki on 2015/11/14.
//  Copyright © 2015年 ytakzk. All rights reserved.
//

import UIKit
import AVFoundation
import CoreMotion
import Photos

@objc protocol FSCameraViewDelegate: class {
    func cameraShotFinished(_ image: UIImage)
}

final class FSCameraView: UIView, UIGestureRecognizerDelegate {

    @IBOutlet weak var previewViewContainer: UIView!
    @IBOutlet weak var shotButton: UIButton!
    @IBOutlet weak var flashButton: UIButton!
    @IBOutlet weak var flipButton: UIButton!
    @IBOutlet weak var fullAspectRatioConstraint: NSLayoutConstraint!
    var croppedAspectRatioConstraint: NSLayoutConstraint?
    
    weak var delegate: FSCameraViewDelegate? = nil
    
    var session: AVCaptureSession?
    var device: AVCaptureDevice?
    var videoInput: AVCaptureDeviceInput?
    var imageOutput: AVCaptureStillImageOutput?
    var focusView: UIView?

    var flashOffImage: UIImage?
    var flashOnImage: UIImage?
    
    var motionManager: CMMotionManager?
    var currentDeviceOrientation: UIDeviceOrientation?
    
    static func instance() -> FSCameraView {
        
        return UINib(nibName: "FSCameraView", bundle: Bundle(for: self.classForCoder())).instantiate(withOwner: self, options: nil)[0] as! FSCameraView
    }
    
    func initialize() {
        
        if session != nil {
            
            return
        }
        
        self.backgroundColor = fusumaBackgroundColor
        
        let bundle = Bundle(for: self.classForCoder)
        
        flashOnImage = fusumaFlashOnImage != nil ? fusumaFlashOnImage : UIImage(named: "ic_flash_on", in: bundle, compatibleWith: nil)
        flashOffImage = fusumaFlashOffImage != nil ? fusumaFlashOffImage : UIImage(named: "ic_flash_off", in: bundle, compatibleWith: nil)
        let flipImage = fusumaFlipImage != nil ? fusumaFlipImage : UIImage(named: "ic_loop", in: bundle, compatibleWith: nil)
        let shotImage = fusumaShotImage != nil ? fusumaShotImage : UIImage(named: "ic_radio_button_checked", in: bundle, compatibleWith: nil)
        
        if(fusumaTintIcons) {
            flashButton.tintColor = fusumaBaseTintColor
            flipButton.tintColor  = fusumaBaseTintColor
            shotButton.tintColor  = fusumaBaseTintColor
            
            flashButton.setImage(flashOffImage?.withRenderingMode(.alwaysTemplate), for: UIControl.State())
            flipButton.setImage(flipImage?.withRenderingMode(.alwaysTemplate), for: UIControl.State())
            shotButton.setImage(shotImage?.withRenderingMode(.alwaysTemplate), for: UIControl.State())
        } else {
            flashButton.setImage(flashOffImage, for: UIControl.State())
            flipButton.setImage(flipImage, for: UIControl.State())
            shotButton.setImage(shotImage, for: UIControl.State())
        }

        
        self.isHidden = false
        
        // AVCapture
        session = AVCaptureSession()
        
        for device in AVCaptureDevice.devices() {
            
            if device.position == AVCaptureDevice.Position.back {
                
                self.device = device
                
                if !device.hasFlash {
                    
                    flashButton.isHidden = true
                }
            }
        }
        
        do {

            if let session = session {

                videoInput = try AVCaptureDeviceInput(device: device!)

                session.addInput(videoInput!)
                
                imageOutput = AVCaptureStillImageOutput()
                
                session.addOutput(imageOutput!)
                
                let videoLayer = AVCaptureVideoPreviewLayer(session: session)
                videoLayer.frame = self.previewViewContainer.bounds
                videoLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
                
                self.previewViewContainer.layer.addSublayer(videoLayer)
                
                session.sessionPreset = AVCaptureSession.Preset.photo

                session.startRunning()
                
            }
            
            // Focus View
            self.focusView         = UIView(frame: CGRect(x: 0, y: 0, width: 90, height: 90))
            let tapRecognizer      = UITapGestureRecognizer(target: self, action:#selector(FSCameraView.focus(_:)))
            tapRecognizer.delegate = self
            self.previewViewContainer.addGestureRecognizer(tapRecognizer)
            
        } catch {
            
        }
        flashConfiguration()
        
        self.startCamera()
        
        NotificationCenter.default.addObserver(self, selector: #selector(FSCameraView.willEnterForegroundNotification(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    @objc func willEnterForegroundNotification(_ notification: Notification) {
        
        startCamera()
    }
    
    deinit {
        
        NotificationCenter.default.removeObserver(self)
    }
    
    func startCamera() {
        
        let status = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
        
        if status == AVAuthorizationStatus.authorized {
            
            session?.startRunning()
            
            motionManager = CMMotionManager()
            motionManager!.accelerometerUpdateInterval = 0.2
            motionManager!.startAccelerometerUpdates(to: OperationQueue()) { [unowned self] (data, _) in
                if let data = data {
                    if abs( data.acceleration.y ) < abs( data.acceleration.x ) {
                        if data.acceleration.x > 0 {
                            self.currentDeviceOrientation = .landscapeRight
                        } else {
                            self.currentDeviceOrientation = .landscapeLeft
                        }
                    } else {
                        if data.acceleration.y > 0 {
                            self.currentDeviceOrientation = .portraitUpsideDown
                        } else {
                            self.currentDeviceOrientation = .portrait
                        }
                    }
                }
            }
            
        } else if status == AVAuthorizationStatus.denied || status == AVAuthorizationStatus.restricted {
            
            stopCamera()
        }
    }
    
    func stopCamera() {
        session?.stopRunning()
        motionManager?.stopAccelerometerUpdates()
        currentDeviceOrientation = nil
    }

    func saveImageToCameraRoll(image: UIImage) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)

        }, completionHandler: nil)
    }

    @IBAction func shotButtonPressed(_ sender: UIButton) {
        
        guard let imageOutput = imageOutput else {
            
            return
        }
        
        DispatchQueue.global(qos: .default).async(execute: { () -> Void in

            let videoConnection = imageOutput.connection(with: AVMediaType.video)

            let orientation: UIDeviceOrientation = self.currentDeviceOrientation ?? UIDevice.current.orientation
            switch (orientation) {
            case .portrait:
                videoConnection?.videoOrientation = .portrait
            case .portraitUpsideDown:
                videoConnection?.videoOrientation = .portraitUpsideDown
            case .landscapeRight:
                videoConnection?.videoOrientation = .landscapeLeft
            case .landscapeLeft:
                videoConnection?.videoOrientation = .landscapeRight
            default:
                videoConnection?.videoOrientation = .portrait
            }

            imageOutput.captureStillImageAsynchronously(from: videoConnection!, completionHandler: { (buffer, error) -> Void in
                
                self.stopCamera()
                
                let data = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(buffer!)
                
                if let image = UIImage(data: data!), let delegate = self.delegate {
                    
                    // Image size
                    var iw: CGFloat
                    var ih: CGFloat

                    switch (orientation) {
                    case .landscapeLeft, .landscapeRight:
                        // Swap width and height if orientation is landscape
                        iw = image.size.height
                        ih = image.size.width
                    default:
                        iw = image.size.width
                        ih = image.size.height
                    }
                    
                    // Frame size
                    let sw = self.previewViewContainer.frame.width
                    
                    // The center coordinate along Y axis
                    let rcy = ih * 0.5

                    let imageRef = image.cgImage?.cropping(to: CGRect(x: rcy-iw*0.5, y: 0 , width: iw, height: iw))
                    
                    
                                        
                    DispatchQueue.main.async(execute: { () -> Void in
                        if fusumaCropImage {
                            let resizedImage = UIImage(cgImage: imageRef!, scale: sw/iw, orientation: image.imageOrientation)
                            delegate.cameraShotFinished(resizedImage)

                            if fusumaSavesImage {
                                self.saveImageToCameraRoll(image: resizedImage)
                            }

                        } else {
                            delegate.cameraShotFinished(image)

                            if fusumaSavesImage {
                                self.saveImageToCameraRoll(image: image)
                            }
                        }
                        
                        self.session       = nil
                        self.device        = nil
                        self.imageOutput   = nil
                        self.motionManager = nil
                        
                    })
                }
                
            })
            
        })
    }
    
    @IBAction func flipButtonPressed(_ sender: UIButton) {

        if !cameraIsAvailable() {

            return
        }
        
        session?.stopRunning()
        
        do {

            session?.beginConfiguration()

            if let session = session {
                
                for input in session.inputs {
                    
                    session.removeInput(input)
                }

                let position = (videoInput?.device.position == AVCaptureDevice.Position.front) ? AVCaptureDevice.Position.back : AVCaptureDevice.Position.front

                for device in AVCaptureDevice.devices(for: AVMediaType.video) {

                    if device.position == position {
                 
                        videoInput = try AVCaptureDeviceInput(device: device)
                        session.addInput(videoInput!)
                        
                    }
                }

            }
            
            session?.commitConfiguration()

            
        } catch {
            
        }
        
        session?.startRunning()
    }
    
    @IBAction func flashButtonPressed(_ sender: UIButton) {

        if !cameraIsAvailable() {

            return
        }

        do {

            if let device = device {
                
                guard device.hasFlash else { return }
            
                try device.lockForConfiguration()
                
                let mode = device.flashMode
                
                if mode == AVCaptureDevice.FlashMode.off {
                    
                    device.flashMode = AVCaptureDevice.FlashMode.on
                    flashButton.setImage(flashOnImage, for: UIControl.State())
                    
                } else if mode == AVCaptureDevice.FlashMode.on {
                    
                    device.flashMode = AVCaptureDevice.FlashMode.off
                    flashButton.setImage(flashOffImage, for: UIControl.State())
                }
                
                device.unlockForConfiguration()

            }

        } catch _ {

            flashButton.setImage(flashOffImage, for: UIControl.State())
            return
        }
 
    }
}

extension FSCameraView {
    
    @objc func focus(_ recognizer: UITapGestureRecognizer) {
        
        let point = recognizer.location(in: self)
        let viewsize = self.bounds.size
        let newPoint = CGPoint(x: point.y/viewsize.height, y: 1.0-point.x/viewsize.width)
        
        let device = AVCaptureDevice.default(for: AVMediaType.video)
        
        do {
            
            try device?.lockForConfiguration()
            
        } catch _ {
            
            return
        }
        
        if device?.isFocusModeSupported(AVCaptureDevice.FocusMode.autoFocus) == true {

            device?.focusMode = AVCaptureDevice.FocusMode.autoFocus
            device?.focusPointOfInterest = newPoint
        }

        if device?.isExposureModeSupported(AVCaptureDevice.ExposureMode.continuousAutoExposure) == true {
            
            device?.exposureMode = AVCaptureDevice.ExposureMode.continuousAutoExposure
            device?.exposurePointOfInterest = newPoint
        }
        
        device?.unlockForConfiguration()
        
        self.focusView?.alpha = 0.0
        self.focusView?.center = point
        self.focusView?.backgroundColor = UIColor.clear
        self.focusView?.layer.borderColor = fusumaBaseTintColor.cgColor
        self.focusView?.layer.borderWidth = 1.0
        self.focusView!.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
        self.addSubview(self.focusView!)
        
        UIView.animate(withDuration: 0.8, delay: 0.0, usingSpringWithDamping: 0.8,
                       initialSpringVelocity: 3.0, options: UIView.AnimationOptions.curveEaseIn, // UIViewAnimationOptions.BeginFromCurrentState
            animations: {
                self.focusView!.alpha = 1.0
                self.focusView!.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
            }, completion: {(finished) in
                self.focusView!.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
                self.focusView!.removeFromSuperview()
        })
    }
    
    func flashConfiguration() {
    
        do {
            
            if let device = device {
                
                guard device.hasFlash else { return }
                
                try device.lockForConfiguration()
                
                device.flashMode = AVCaptureDevice.FlashMode.off
                flashButton.setImage(flashOffImage, for: UIControl.State())
                
                device.unlockForConfiguration()
                
            }
            
        } catch _ {
            
            return
        }
    }

    func cameraIsAvailable() -> Bool {

        let status = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)

        if status == AVAuthorizationStatus.authorized {

            return true
        }

        return false
    }
}
