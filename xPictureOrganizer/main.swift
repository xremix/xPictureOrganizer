import Foundation
import CoreLocation
import CoreGraphics // Add this import statement
import ImageIO

func extractCreationDate(from exifData: [String: Any]) -> Date? {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
    
    if let dateString = exifData[kCGImagePropertyExifDateTimeOriginal as String] as? String {
        return dateFormatter.date(from: dateString)
    }
    
    return nil
}

func extractGPSData(from exifData: [String: Any]) -> CLLocationCoordinate2D? {
    guard
//        let gpsInfo = exifData[kCGImagePropertyGPSDictionary as String] as? [String: Any],
        let latitudeRef = exifData[kCGImagePropertyGPSLatitudeRef as String] as? String,
        let longitudeRef = exifData[kCGImagePropertyGPSLongitudeRef as String] as? String,
        var latitude = exifData[kCGImagePropertyGPSLatitude as String] as? Double,
        var longitude = exifData[kCGImagePropertyGPSLongitude as String] as? Double
    else {
        return nil
    }
    
//    var latitude = latitudeArray[0] + latitudeArray[1]/60 + latitudeArray[2]/3600
//    var longitude = longitudeArray[0] + longitudeArray[1]/60 + longitudeArray[2]/3600
//    
    if latitudeRef == "S" {
        latitude = -latitude
    }
    
    if longitudeRef == "W" {
        longitude = -longitude
    }
    
    return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
}

func reverseGeocode(location: CLLocationCoordinate2D) -> String? {
    let geocoder = CLGeocoder()
    let location = CLLocation(latitude: location.latitude, longitude: location.longitude)

    var locationName: String?

    let semaphore = DispatchSemaphore(value: 0)

    DispatchQueue.global().async {
        print("x")
        geocoder.reverseGeocodeLocation(location) { (placemarks, error) in
            print("y")
            defer { semaphore.signal() }

            if let error = error {
                print("Reverse geocoding error: \(error.localizedDescription)")
                return
            }

            if let placemark = placemarks?.first {
                locationName = placemark.name ?? placemark.locality ?? placemark.subLocality ?? placemark.administrativeArea ?? placemark.country
            }
        }
    }

    semaphore.wait()

    return locationName
}


func organizeImages(sourceFolder: String, destinationFolder: String) {
    var previousLocation: CLLocationCoordinate2D?

    let fileManager = FileManager.default
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"

    do {
        let fileURLs = try fileManager.contentsOfDirectory(at: URL(fileURLWithPath: sourceFolder), includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles)

        for fileURL in fileURLs {
            print(fileURL.absoluteString)
            let fileAttributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            if let creationDate = fileAttributes[.creationDate] as? Date {
                let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
                let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, imageSourceOptions)
                let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource!, 0, nil) as? [String: Any]

//                if let exifData = imageProperties?[kCGImagePropertyExifDictionary as String] as? [String: Any] {
                    
                if let exifData = imageProperties?["{GPS}"] as? [String: Any] {
                    let gpsData = extractGPSData(from: exifData)

                    if let gpsData = gpsData {
                        let locationName: String
                        if let previousLocation = previousLocation, gpsData.latitude.isEqual(to: previousLocation.latitude), gpsData.longitude.isEqual(to: previousLocation.longitude) {
                            locationName = "ReusePreviousLocation"
                        } else {
                            if let name = reverseGeocode(location: gpsData) {
                                locationName = name
                            } else {
                                locationName = "UnknownLocation"
                            }
                        }

                        let folderName = "\(dateFormatter.string(from: creationDate)) - \(locationName)"
                        let destinationPath = URL(fileURLWithPath: destinationFolder).appendingPathComponent(folderName)

                        try? fileManager.createDirectory(at: destinationPath, withIntermediateDirectories: true, attributes: nil)
                        try? fileManager.moveItem(at: fileURL, to: destinationPath.appendingPathComponent(fileURL.lastPathComponent))

                        previousLocation = gpsData
                    }
                }
            }
        }
    } catch {
        print("Error reading directory: \(error)")
    }
}

