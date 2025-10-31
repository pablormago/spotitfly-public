# SpotsApp (prepared)

This archive contains the SwiftUI app source files for the SpotsApp described in the conversation.
It does NOT include GoogleService-Info.plist. Add it from your Firebase console.

## What is included
- Models (Spot, Restriccion, GeoJSON)
- ViewModels (SpotViewModel, RestriccionesViewModel, AuthViewModel)
- Helpers (LocationManager, ImagePicker)
- Views (AuthView, ContentView, AddSpotView, SpotDetailView, MapOverlay)
- Info.plist with required usage descriptions (edit as needed)

## Firebase (Swift Package Manager)
To add Firebase via Swift Package Manager in Xcode:
1. In Xcode, open your project.
2. File -> Add Packages...
3. Enter package URL: https://github.com/firebase/firebase-ios-sdk
4. Select the libraries you need: FirebaseAuth, FirebaseFirestore, FirebaseStorage, FirebaseCore
5. Add the package.

After adding the package, open `SpotsApp.swift` and uncomment `FirebaseApp.configure()` after you add `GoogleService-Info.plist` to the project.

## ENAIRE layer
- The RestriccionesViewModel fetches the ZGUAS_Aero layer (FeatureServer index 2).
- Other layers are included commented in the ViewModel; to enable, uncomment and add to fetch list.

## How to install
1. Open this folder in Finder.
2. Drag the files into your Xcode project (or copy them into your Xcode project's folder structure).
3. Add `GoogleService-Info.plist` to the project root (download from Firebase console).
4. Add Firebase via Swift Package Manager as above.
5. Uncomment FirebaseApp.configure() in `SpotsApp.swift`.
6. Build and run on a device (recommended).

## Notes
- Security rules: For development set Firestore rules to allow read and authenticated writes, then tighten before production.
- The project uses MKMapView via MapOverlay for overlay rendering; MapKit SwiftUI Map has limited overlay support in iOS16.
