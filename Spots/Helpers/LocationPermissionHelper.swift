//
//  LocationPermissionHelper.swift
//  Spots
//
//  Created by Pablo Jimenez on 30/9/25.
//


import Foundation
import CoreLocation

final class LocationPermissionHelper: NSObject, CLLocationManagerDelegate {
    static let shared = LocationPermissionHelper()
    private let manager = CLLocationManager()
    private var completion: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    func requestWhenInUse(_ completion: (() -> Void)? = nil) {
        self.completion = completion
        manager.requestWhenInUseAuthorization()
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        completion?()
        completion = nil
    }
}
