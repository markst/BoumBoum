//
//  ViewController.swift
//  BoumBoumExample
//
//  Created by Kevin DELANNOY on 24/01/16.
//  Copyright © 2016 Kevin Delannoy. All rights reserved.
//

import UIKit
import BoumBoum

class ViewController: UIViewController, BoumBoumDelegate {
    @IBOutlet weak var imageViewHeart: UIImageView?
    @IBOutlet weak var labelPulseRate: UILabel?

    let boum = BoumBoum()

    lazy var animation: CABasicAnimation = {
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.duration = 0.7
        animation.repeatCount = Float.infinity
        animation.autoreverses = true
        animation.fromValue = NSNumber(value: 1)
        animation.toValue = NSNumber(value: 0.7)
        animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeIn)
        return animation
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        boum.delegate = self
    }

    @IBAction func buttonStartPressed(sender: UIButton) {
        if boum.state == .stopped {
            do {
                try boum.startMonitoring()
                sender.setTitle("Stop Monitoring", for: .normal)
                imageViewHeart?.layer.add(animation, forKey: "heart")
            } catch {
            }
        }
        else {
            do {
                try boum.stopMonitoring()
                sender.setTitle("Start Monitoring", for: .normal)
                imageViewHeart?.layer.removeAnimation(forKey: "heart")
            } catch {
            }
        }
    }

    func boumBoum(boumBoum: BoumBoum, didFindAverageRate rate: UInt) {
        labelPulseRate?.text = "\(rate)"
        print(rate)
    }
}

