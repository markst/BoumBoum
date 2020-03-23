//
//  BoumBoum.swift
//  BoumBoum
//
//  Created by Kevin DELANNOY on 20/01/16.
//  Copyright © 2016 Kevin Delannoy. All rights reserved.
//

import UIKit
import AVFoundation

/**
 Possible BoumBoum Errors.
 
 - AlreadyRunning:                  Means you asked to start monitoring while it already is.
 - AlreadyStopped:                  Means you asked to stop monitoring while it's not.
 - CameraUnavailable:               Means the camera isn't available.
 - TorchModeUnsupported:            Means the torch isn't available - though needed.
 - CameraLockFailed:                Means the camera lock failed to update the configuration.
 - CameraDeviceInputCreationFailed: Means the camera device input creation failed.
 */
public enum BoumBoumError: Error {
    case alreadyRunning
    case alreadyStopped
    case cameraUnavailable
    case torchModeUnsupported
    case cameraLockFailed(NSError)
    case cameraDeviceInputCreationFailed(NSError)
}

/// The delegate protocol.
public protocol BoumBoumDelegate: class {
    /**
     Called when the averate heart rate is updated. At start, it may take a while
     but after the first average has been computed, it will be called regularly.
     
     - parameter boumBoum: BoumBoum instance.
     - parameter rate:     The heart rate.
     */
    func boumBoum(boumBoum: BoumBoum, didFindAverageRate rate: UInt)
}

/// BoumBoum is an heart rate monitor that use value from the camera.
/// Place your finger on the back camera with a part of your finger on
/// the torch and see your heart rate.
public class BoumBoum: NSObject {
    /**
     Possible BoumBoum states.
     
     - Running: BoumBoum is monitoring.
     - Stopped: BoumBoum isn't monitoring.
     */
    public enum State {
        case running
        case stopped
    }
    
    /// The capture session.
    public let session: AVCaptureSession
    
    /// The camera.
    public let camera: AVCaptureDevice?
    
    /// The delegate.
    public weak var delegate: BoumBoumDelegate?
    
    
    /// The state.
    public private(set) var state = State.stopped
    
    
    /// The rate analyzer.
    private let analyzer = BoumBoumAnalyzer()
    
    /// The camera input.
    private var cameraInput: AVCaptureDeviceInput?
    
    /// The video output.
    private var videoOutput: AVCaptureVideoDataOutput?
    
    // MARK: Initialization
    ////////////////////////////////////////////////////////////////////////////
    
    /**
     Initializes BoumBoum with a new `AVCaptureSession` and the default camera.
     
     - returns: An initialized BoumBoum.
     */
    public convenience override init() {
        self.init(session: AVCaptureSession(),
                  camera: AVCaptureDevice.default(for: .video))
    }
    
    /**
     Initializes BoumBoum with a given `AVCaptureSession` and a given camera.
     
     - parameter session: A capture session.
     - parameter camera:  A reference to the back camera.
     
     - returns: An initialized BoumBoum.
     */
    public init(session: AVCaptureSession, camera: AVCaptureDevice) {
        self.session = session
        self.camera = camera
        super.init()
    }
    
    /**
     Initializes BoumBoum with a given `AVCaptureSession` and a given camera.
     
     - parameter session: A capture session.
     - parameter camera:  A reference to the back camera.
     
     - returns: An initialized BoumBoum.
     */
    private init(session: AVCaptureSession, camera: AVCaptureDevice?) {
        self.session = session
        self.camera = camera
        super.init()
    }
    
    ////////////////////////////////////////////////////////////////////////////
    
    
    // MARK: Start / Stop
    ////////////////////////////////////////////////////////////////////////////
    
    /**
     Starts monitoring the heart rate.
     
     - throws: A `BoumBoumError` if something fails.
     */
    public func startMonitoring() throws {
        //Ensuring we have a camera
        guard let camera = camera else {
            throw BoumBoumError.cameraUnavailable
        }
        
        //Ensuring we're stopped
        guard state == .stopped else {
            throw BoumBoumError.alreadyRunning
        }
        
        //Then, we create an input
        let cameraInput: AVCaptureDeviceInput
        if let existingInput = self.cameraInput {
            cameraInput = existingInput
        }
        else {
            do {
                cameraInput = try AVCaptureDeviceInput(device: camera)
                self.cameraInput = cameraInput
            } catch let error {
                throw BoumBoumError.cameraDeviceInputCreationFailed(error as NSError)
            }
        }
        
        //Let's create the output
        let cameraOutput = videoOutput ?? configuredCameraOutput(delegate: self)
        videoOutput = cameraOutput
        
        //Configure session
        session.sessionPreset = .low
        session.addInput(cameraInput)
        session.addOutput(cameraOutput)
        
        //And we're good to go
        session.startRunning()
        state = .running

        //First, we turn on the torch
        guard camera.isTorchModeSupported(.on) else {
            throw BoumBoumError.torchModeUnsupported
        }

        do {
            try camera.lockForConfiguration()
            try camera.setTorchModeOn(level: 1.0)
            camera.torchMode = .on
            camera.unlockForConfiguration()
        } catch let error {
            throw BoumBoumError.cameraLockFailed(error as NSError)
        }
    }
    
    /**
     Stops monitoring the heart rate.
     
     - throws: A `BoumBoumError` if something fails.
     */
    public func stopMonitoring() throws {
        //Ensuring we have a camera
        guard let camera = camera else {
            throw BoumBoumError.cameraUnavailable
        }
        
        //Ensuring we're running
        guard state == .running else {
            throw BoumBoumError.alreadyStopped
        }
        
        //First, we stop the session
        session.stopRunning()
        
        //Then we remove input and output
        if let cameraInput = cameraInput {
            session.removeInput(cameraInput)
        }
        if let videoOutput = videoOutput {
            session.removeOutput(videoOutput)
        }
        
        //And we turn off the torch
        guard camera.isTorchModeSupported(.on) else {
            throw BoumBoumError.torchModeUnsupported
        }
        
        do {
            try camera.lockForConfiguration()
            camera.torchMode = .off
            camera.unlockForConfiguration()
        } catch let error {
            throw BoumBoumError.cameraLockFailed(error as NSError)
        }
        
        //We're good to go
        state = .stopped
    }
    
    ////////////////////////////////////////////////////////////////////////////
    
    
    // MARK: Output creation
    ////////////////////////////////////////////////////////////////////////////
    
    /**
     Configures an `AVCatpureVideoDataOutput`.
     
     - parameter delegate: The delegate to set.
     
     - returns: A configured `AVCatpureVideoDataOutput`.
     */
    private func configuredCameraOutput(delegate: AVCaptureVideoDataOutputSampleBufferDelegate) -> AVCaptureVideoDataOutput {
        let videoOutput = AVCaptureVideoDataOutput()
        let queue = DispatchQueue(label: "be.delannoyk.boumboum")
        videoOutput.setSampleBufferDelegate(delegate, queue: queue)
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String : NSNumber(value: kCVPixelFormatType_32BGRA)
        ]
        return videoOutput
    }
    
    ////////////////////////////////////////////////////////////////////////////
}

extension BoumBoum: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let value = CMSampleBufferGetImageBuffer(sampleBuffer)?.averageRGBHSVValueFromImageBuffer() else {
            return
        }
        
        analyzer.pushValues(hsv: value.hsv)
        
        if let rate = analyzer.averageBoumBoum() {
            DispatchQueue.main.async { [weak self] in
                if let strongSelf = self {
                    strongSelf.delegate?.boumBoum(boumBoum: strongSelf, didFindAverageRate: rate)
                }
            }
        }
    }
}
