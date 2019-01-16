//
//  PictureCortex.swift
//  WallerStreet
//
//  Created by Michael Zuccarino on 11/27/18.
//  Copyright © 2018 Shnarf. All rights reserved.
//

import UIKit
import AVKit
import AWSS3

enum DataRecallCode: Int {
    case none
    case started
    case inProgress
    case loaded
    case loadedFromNetwork
    case loadedFromDisk
    case failedFromNetwork
    case failedFromDisk
    case failed
}

enum FileLocation {
    case media
    case document
    case draft
    case feedCache
    case templates
}

typealias ImageCompletion = ((UIImage?, DataRecallCode, CGFloat) -> Void)
typealias VideoCompletion = ((UIImage?, DataRecallCode, CGFloat) -> Void)
typealias UploadActivityObservation = ((Int) -> Void)

class DataNeura: NSObject {

    var image: UIImage?
    var video: AVAsset?
    var imageKey: String?
    var status: DataRecallCode = .none
    var inception: TimeInterval = NSDate.timeIntervalSinceReferenceDate
    var observerImageBlocks: [ImageCompletion] = [ImageCompletion]()
    var observerVideoBlocks: [VideoCompletion] = [VideoCompletion]()

}

class DataCortex: NSObject {

    static var neura = DataCortex()
    static var loggingEnabled = true
    static var identityPoolId: String = ""

    var transferUtility: AWSS3TransferUtility?
    var activityObservers: [UploadActivityObservation] = [UploadActivityObservation]()

    override init() {
        super.init()

        setupS3()
        setupLocalCache()
    }

    var cacheMap: [String: DataNeura] = [String: DataNeura]()

}

extension DataCortex {

    func image(for imageKey: String, completion: ImageCompletion?) -> UIImage? {
        if let obj = cacheMap[imageKey] {
            if let img = obj.image {
                if let c = completion {
                    c(img, .loaded, 0)
                } else {
                    return img
                }
            } else {
                if let c = completion {
                    obj.observerImageBlocks.append(c)
                }
            }
        } else {
            if let fp = getMediaCachePath() {
                let fa = fp.appendingPathComponent("\(imageKey)")
                if FileManager.default.fileExists(atPath: fa.absoluteString),
                    let im = UIImage(contentsOfFile: fa.absoluteString) {
                    let dN = DataNeura()
                    dN.imageKey = imageKey
                    dN.image = im
                    dN.status = .loaded
                    self.cacheMap[imageKey] = dN
                    completion?(im, .loaded, 1)
                    return im
                }
            }
            let dN = DataNeura()
            dN.imageKey = imageKey
            if let c = completion {
                dN.observerImageBlocks.append(c)
            }
            self.cacheMap[imageKey] = dN
            downloadS3(imageKey: imageKey)
        }
        return nil
    }

    func setImage(image: UIImage, for imageKey: String, completion: ImageCompletion? = nil, throwToTheClouds: Bool = true) {
        guard self.cacheMap[imageKey] == nil else {
            return
        }

        let dN = DataNeura()
        dN.image = image
        dN.imageKey = imageKey
        dN.status = throwToTheClouds ? .inProgress : .loaded
        if let c = completion {
            dN.observerImageBlocks.append(c)
        }
        self.cacheMap[imageKey] = dN
        completion?(image, DataRecallCode.inProgress, 1)
        writeDiskCache(fileKey: imageKey, data: image.pngData()!, location: .media)
        if throwToTheClouds {
            uploadS3(imageKey: imageKey)
        }
    }

    func video(for videoKey: String, completion: @escaping  VideoCompletion) {

    }

    func setVideo(video: AVAsset, for videoKey: String, completion: @escaping  VideoCompletion) {

    }

}

extension DataCortex {

    func uploadS3(neura: DataNeura) {
        guard let k = neura.imageKey else {
            return
        }
        self.cacheMap[k] = neura
        self.uploadS3(imageKey: k)
    }

    func checkUploadStatus(observer: @escaping UploadActivityObservation) {
        activityObservers.append(observer)
        uploadActivityCountModified()
    }

    func uploadActivityCountModified() {
        var count = 0
        cacheMap.map({$0.value}).forEach { (neura) in
            if neura.status == DataRecallCode.inProgress || neura.status == DataRecallCode.started {
                count += 1
            }
        }
        activityObservers.forEach { (observateBoy) in
            observateBoy(count)
        }
        if count == 0 {
            activityObservers = [UploadActivityObservation]()
        }
    }

    func downloadS3(imageKey: String) {
        self.cacheMap[imageKey]?.status = .started

        let expression = AWSS3TransferUtilityDownloadExpression()
        expression.progressBlock = { [weak self] (task, progress) in DispatchQueue.main.async(execute: {
            // Do something e.g. Update a progress bar.
            self?.cacheMap[imageKey]?.status = DataRecallCode.inProgress
            DispatchQueue.main.async(execute: {
                self?.cacheMap[imageKey]?.observerImageBlocks.forEach({ (completion) in
                    completion(nil, DataRecallCode.inProgress, CGFloat(Float(progress.fractionCompleted)))
                })
            })
        })
        }

        var completionHandler: AWSS3TransferUtilityDownloadCompletionHandlerBlock?
        completionHandler = { [weak self] (task, URL, data, error) -> Void in
            guard error == nil,
                let d = data else {
                self?.cacheMap[imageKey]?.status = DataRecallCode.failed
                DispatchQueue.main.async(execute: {
                    self?.cacheMap[imageKey]?.observerImageBlocks.forEach({ (completion) in
                        completion(nil, .failed, 0)
                    })
                    self?.cacheMap[imageKey]?.observerImageBlocks = [ImageCompletion]()
                    self?.uploadActivityCountModified()
                })
                return
            }
            guard let i = UIImage(data: d) else {
                self?.cacheMap[imageKey]?.status = DataRecallCode.failed
                DispatchQueue.main.async(execute: {
                    self?.cacheMap[imageKey]?.observerImageBlocks.forEach({ (completion) in
                        completion(nil, .failed, 0)
                    })
                    self?.cacheMap[imageKey]?.observerImageBlocks = [ImageCompletion]()
                    self?.uploadActivityCountModified()
                })
                return
            }
            self?.cacheMap[imageKey]?.status = .loaded
            self?.cacheMap[imageKey]?.image = i
            DispatchQueue.main.async(execute: {
                self?.cacheMap[imageKey]?.observerImageBlocks.forEach({ (completion) in
                    completion(i, .loaded, 1)
                })
                self?.cacheMap[imageKey]?.observerImageBlocks = [ImageCompletion]()
                self?.uploadActivityCountModified()
            })
            self?.writeDiskCache(fileKey: imageKey, data: i.pngData()!, location: .media)
        }

        uploadActivityCountModified()

        self.transferUtility?.downloadData(
            fromBucket: "wallerbucketgenesis",
            key: imageKey,
            expression: expression,
            completionHandler: completionHandler
            ).continueWith { [weak self] (task) -> AnyObject? in
                if let error = task.error {
                    if DataCortex.loggingEnabled {
                        print("[DATACORTEX] " + error.localizedDescription)
                    }
                    self?.cacheMap[imageKey]?.status = DataRecallCode.failed
                    DispatchQueue.main.async(execute: {
                        self?.cacheMap[imageKey]?.observerImageBlocks.forEach({ (completion) in
                            completion(nil, .failed, 0)
                        })
                        self?.cacheMap[imageKey]?.observerImageBlocks = [ImageCompletion]()
                        self?.uploadActivityCountModified()
                    })
                }

                if let _ = task.result {
                    // do something with task result?
                }
                return nil
        }
    }

    func writeDiskCache(fileKey: String, data: Data, location: FileLocation) {
        var cachesFS: URL?
        switch location {
        case .media:
            cachesFS = getMediaCachePath()
            break
        case .document:
            cachesFS = getDocumentsCachePath()
            break
        case .draft:
            cachesFS = getDraftsDirectoryPath()
            break
        case .feedCache:
            cachesFS = getFeedCacheDirectory()
            break
        case .templates:
            cachesFS = getTemplatesDirectoryPath()
            break
        }

        guard let cachesF = cachesFS else {
            return
        }

        let fileC = cachesF.appendingPathComponent(fileKey)

        if FileManager.default.fileExists(atPath: fileC.absoluteString)  {
            do {
                try FileManager.default.removeItem(atPath: fileC.absoluteString)
            } catch let error {
                if DataCortex.loggingEnabled {
                    print("[DATACORTEX] " + error.localizedDescription)
                }
            }
        }

        do {
            try data.write(to: URL(fileURLWithPath: fileC.absoluteString),
                       options: Data.WritingOptions.atomicWrite)
        } catch let error {
            if DataCortex.loggingEnabled {
                print("[DATACORTEX] " + error.localizedDescription)
            }
        }
    }

    func progressBlock(imageKey: String) -> AWSS3TransferUtilityMultiPartProgressBlock {
        return { [weak self] (task, progress) in
            if DataCortex.loggingEnabled {
                print("[DATACORTEX] [upload] uploading \(imageKey): \(progress.fractionCompleted)")
            }
            DispatchQueue.main.async(execute: {
                // Do something e.g. Update a progress bar.
                self?.cacheMap[imageKey]?.status = DataRecallCode.inProgress
                DispatchQueue.main.async(execute: {
                    self?.cacheMap[imageKey]?.observerImageBlocks.forEach({ (completion) in
                        completion(nil, DataRecallCode.inProgress, CGFloat(Float(progress.fractionCompleted)))
                    })
                })
            })
        }
    }

    func multipartUploadCompletionHandler(imageKey: String) -> AWSS3TransferUtilityMultiPartUploadCompletionHandlerBlock? {
        return { [weak self] (task, error) -> Void in
            if DataCortex.loggingEnabled {
                print("[DATACORTEX] [upload] completed \(imageKey): \(error)")
            }
            guard error == nil else {
                self?.cacheMap[imageKey]?.status = DataRecallCode.failed
                DispatchQueue.main.async(execute: {
                    self?.cacheMap[imageKey]?.observerImageBlocks.forEach({ (completion) in
                        completion(nil, .failed, 0)
                    })
                    self?.cacheMap[imageKey]?.observerImageBlocks = [ImageCompletion]()
                    self?.uploadActivityCountModified()
                })
                return
            }
            self?.cacheMap[imageKey]?.status = .loaded
            DispatchQueue.main.async(execute: {
                self?.uploadActivityCountModified()
            })
        }
    }

    func uploadS3(imageKey: String, bucket: String = "wallerbucketgenesis") {
        let expression = AWSS3TransferUtilityMultiPartUploadExpression()
        expression.progressBlock = progressBlock(imageKey: imageKey)

        var completionHandler: AWSS3TransferUtilityMultiPartUploadCompletionHandlerBlock?
        completionHandler = multipartUploadCompletionHandler(imageKey: imageKey)

        guard let img = self.cacheMap[imageKey]?.image else {
            return
        }

        var data = img.pngData()!
        var format = "image/png"
        if img.size.height > 1000 || img.size.width > 1000 {
            data = img.jpegData(compressionQuality: 0.75)!
            format = "image/jpeg"
        }

        self.uploadActivityCountModified()

        self.transferUtility?.uploadUsingMultiPart(
            data: data,
            bucket: bucket,
            key: imageKey,
            contentType: format,
            expression: expression,
            completionHandler: completionHandler
            ).continueWith { [weak self] (task) -> AnyObject? in
                if let error = task.error {
                    if DataCortex.loggingEnabled {
                        print("[DATACORTEX] Error: \(error.localizedDescription)")
                    }
                    self?.cacheMap[imageKey]?.status = DataRecallCode.failed
                    DispatchQueue.main.async(execute: {
                        self?.cacheMap[imageKey]?.observerImageBlocks.forEach({ (completion) in
                            completion(nil, .failed, 0)
                        })
                        self?.cacheMap[imageKey]?.observerImageBlocks = [ImageCompletion]()
                        self?.uploadActivityCountModified()
                    })
                }

                if let _ = task.result {
                    // do something with task result?
                }
                return nil
        }
    }

}

extension DataCortex {
    // a json array of dictionaries of [String: String]
    // for now just contains imageKey, status, inception
    func setupLocalCache() {
        guard let cacheStructURL = getMediaCachePath() else {
            return
        }
        let cacheStructPath = cacheStructURL.appendingPathComponent("cachestructprimary").path
        do {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: cacheStructPath)),
                let json = try? JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions.mutableLeaves) as? [[String: AnyObject]] {
                json?.forEach({ (cacheObjectDescription) in
                    var imagePath = String(cacheStructURL.path)
                    if let imageKey = cacheObjectDescription["imageKey"] as? String,
                        let imageStatus = DataRecallCode(rawValue: (cacheObjectDescription["status"] as? NSNumber)?.intValue ?? 0),
                        let _ = (cacheObjectDescription["Inception"] as? NSNumber)?.intValue {
                        imagePath.append(contentsOf: "/\(imageKey)")
                        if FileManager.default.fileExists(atPath: imagePath),
                            let image = UIImage(contentsOfFile: imagePath) {
                            if self.cacheMap[imageKey] != nil {
                                if DataCortex.loggingEnabled {
                                    fatalError("[DATACORTEX] Somehow you have tried to initialize the uploader cache more than once. Dont be doing that please.")
                                }
                            } else {
                                let dN = DataNeura()
                                dN.image = image
                                dN.imageKey = imageKey
                                dN.status = imageStatus
                                self.cacheMap[imageKey] = dN
                                if imageStatus != DataRecallCode.loaded {
                                    uploadS3(imageKey: imageKey)
                                }
                            }
                        }
                    } else {
                        fatalError("[DATACORTEX] A corrupt uploader cache exists.")
                    }
                })
            }
        }
    }

    func getMediaCachePath() -> URL? {
        let paths = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.cachesDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)
        guard let cachesDir = paths.first,
            let url = URL(string: cachesDir) else {
            return nil
        }
        let dataPath = url.appendingPathComponent("GrainMedia")

        if FileManager.default.fileExists(atPath: dataPath.absoluteString) {
            return dataPath
        }

        do {
            try FileManager.default.createDirectory(atPath: dataPath.absoluteString,
                                                    withIntermediateDirectories: false,
                                                    attributes: nil)
        } catch let error as NSError {
            if DataCortex.loggingEnabled {
                print("[DATACORTEX] " + error.localizedDescription);
            }
        }
        return dataPath
    }

    func getDocumentsCachePath() -> URL? {
        let paths = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.documentDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)
        guard let cachesDir = paths.first as? String,
            let url = URL(string: cachesDir) else {
                return nil
        }
        let dataPath = url.appendingPathComponent("GrainMedia")

        if FileManager.default.fileExists(atPath: dataPath.absoluteString) {
            return dataPath
        }

        do {
            try FileManager.default.createDirectory(atPath: dataPath.absoluteString,
                                                    withIntermediateDirectories: false,
                                                    attributes: nil)
        } catch let error as NSError {
            if DataCortex.loggingEnabled {
                print("[DATACORTEX] " + error.localizedDescription);
            }
        }
        return dataPath
    }

    func getFeedCacheDirectory() -> URL? {
        let paths = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.documentDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)
        guard let cachesDir = paths.first,
            let url = URL(string: cachesDir) else {
                return nil
        }
        let dataPath = url.appendingPathComponent("MarbleFeedCache")

        if FileManager.default.fileExists(atPath: dataPath.absoluteString) {
            return dataPath
        }

        do {
            try FileManager.default.createDirectory(atPath: dataPath.absoluteString,
                                                    withIntermediateDirectories: false,
                                                    attributes: nil)
        } catch let error as NSError {
            if DataCortex.loggingEnabled {
                print("[DATACORTEX] " + error.localizedDescription);
            }
        }
        return dataPath
    }

    func getDraftsDirectoryPath() -> URL? {
        let paths = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.documentDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)
        guard let cachesDir = paths.first,
            let url = URL(string: cachesDir) else {
                return nil
        }
        let dataPath = url.appendingPathComponent("GrainDrafts")

        if FileManager.default.fileExists(atPath: dataPath.absoluteString) {
            return dataPath
        }

        do {
            try FileManager.default.createDirectory(atPath: dataPath.absoluteString,
                                                    withIntermediateDirectories: false,
                                                    attributes: nil)
        } catch let error as NSError {
            if DataCortex.loggingEnabled {
                print("[DATACORTEX] " + error.localizedDescription);
            }
        }
        return dataPath
    }

    func getTemplatesDirectoryPath() -> URL? {
        let paths = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.documentDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)
        guard let templatesDir = paths.first,
            let url = URL(string: templatesDir) else {
                return nil
        }
        let dataPath = url.appendingPathComponent("GrainTemplates")

        if FileManager.default.fileExists(atPath: dataPath.absoluteString) {
            return dataPath
        }

        do {
            try FileManager.default.createDirectory(atPath: dataPath.absoluteString,
                                                    withIntermediateDirectories: false,
                                                    attributes: nil)
        } catch let error as NSError {
            if DataCortex.loggingEnabled {
                print("[DATACORTEX] " + error.localizedDescription);
            }
        }
        return dataPath
    }


    func writeLocalCache() {
        guard let cacheStructPath = getMediaCachePath() else {
            return
        }
        var finalMap: [[String: AnyObject]] = [[String: AnyObject]]()
        do {
            try self.cacheMap.forEach { (entry) in
                if let ik = entry.value.imageKey {
                    if let i = entry.value.image,
                        let d = i.pngData() {
                        let q = URL(fileURLWithPath: cacheStructPath.appendingPathComponent(ik).absoluteString)
                        do {
                            try d.write(to: q)
                        }
                    }
                    var obj: [String: AnyObject] = [String: AnyObject]()
                    obj["imageKey"] = NSString(string: ik)
                    obj["status"] = NSNumber(value: entry.value.status.rawValue)
                    obj["Inception"] = NSNumber(value: entry.value.inception)
                    finalMap.append(obj)
                }
            }
        } catch _ {

        }
        let newP = URL(fileURLWithPath: cacheStructPath.appendingPathComponent("cachestructprimary").path)
        do {
            if let kj = try? JSONSerialization.data(withJSONObject: finalMap,
                                                    options: JSONSerialization.WritingOptions.prettyPrinted) {
                if FileManager.default.fileExists(atPath: newP.absoluteString) {
                    try? FileManager.default.removeItem(at: newP)
                }
                try? kj.write(to: newP)
            }
        }
    }

    func setupS3() {
        //Setup credentials
        let credentialProvider = AWSCognitoCredentialsProvider(regionType: AWSRegionType.USEast1,
                                                               identityPoolId: DataCortex.identityPoolId)

        let configuration = AWSServiceConfiguration(region: .USWest2,
                                                    credentialsProvider: credentialProvider)

        //Setup the transfer utility configuration
        let tuConf = AWSS3TransferUtilityConfiguration()
        //tuConf.isAccelerateModeEnabled = true
        tuConf.retryLimit = 5

        //Register a transfer utility object
        AWSS3TransferUtility.register(
            with: configuration!,
            transferUtilityConfiguration: tuConf,
            forKey: "transfer-utility-with-advanced-options"
        )

        //Look up the transfer utility object from the registry to use for your transfers.
        self.transferUtility = AWSS3TransferUtility.s3TransferUtility(forKey: "transfer-utility-with-advanced-options")
    }
}

extension DataCortex {

    func purgeAllCache() {
        guard let cacheLocation = getMediaCachePath() else {
            return
        }

        let drafts = WallPersist.loadDrafts().compactMap { (zine) -> [Post]? in
            return zine.pages?.first?.posts
            }.reduce([Post]()) { (prev, curr) -> [Post] in
                return curr + prev
            }.filter { (post) -> Bool in
                return post as? PostImage != nil
            }.compactMap { (post) -> String? in
                return (post as? PostImage)?.imageID
        }

        if let urlArray = try? FileManager.default.contentsOfDirectory(at: cacheLocation,
                                                                       includingPropertiesForKeys: [.creationDateKey],
                                                                       options:.skipsHiddenFiles) {

            let orderedByDescending = urlArray.map { url in
                (url.lastPathComponent, (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast)
                }
                .sorted(by: { $0.1 > $1.1 }) // sort descending modification dates
                .map { $0.0 }.filter({ $0.contains("-")}).filter { (path) -> Bool in
                    return drafts.contains(path) == false
            }
            // dont delete paths required by drafts!
            orderedByDescending.forEach { [weak self] (path) in
                do {
                    try FileManager.default.removeItem(at: URL(fileURLWithPath: cacheLocation.appendingPathComponent(path).path))
                    self?.cacheMap.removeValue(forKey: path)
                } catch let error {
                    if DataCortex.loggingEnabled {
                        print("[DATACORTEX] " + error.localizedDescription)
                    }
                }
            }
        }
    }

    func purgeStaleNeura() {
        guard let cacheLocation = getMediaCachePath() else {
            return
        }
        if let urlArray = try? FileManager.default.contentsOfDirectory(at: cacheLocation,
                                                                       includingPropertiesForKeys: [.creationDateKey],
                                                                       options:.skipsHiddenFiles) {

            let orderedByDescending = urlArray.map { url in
                (url.lastPathComponent, (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast)
                }
                .sorted(by: { $0.1 > $1.1 }) // sort descending modification dates
                .map { $0.0 }.filter({ $0.contains("-")})
            var totalSize: Int = 0
            orderedByDescending.forEach { [weak self] (path) in
                if totalSize > 600 {
                    do {
                        try FileManager.default.removeItem(at: URL(fileURLWithPath: cacheLocation.appendingPathComponent(path).path))
                        self?.cacheMap.removeValue(forKey: path)
                    } catch let error {
                        if DataCortex.loggingEnabled {
                            print("[DATACORTEX] " + error.localizedDescription)
                        }
                    }
                }
                totalSize += sizePerMB(url: cacheLocation.appendingPathComponent(path))
            }
        }
    }

    func sizeOfMediaCache() -> Int {
        guard let cacheLocation = getMediaCachePath() else {
            return 0
        }
        if let urlArray = try? FileManager.default.contentsOfDirectory(at: cacheLocation,
                                                                       includingPropertiesForKeys: [.creationDateKey],
                                                                       options:.skipsHiddenFiles) {

            let orderedByDescending = urlArray.map { url in
                (url.lastPathComponent, (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast)
                }
                .sorted(by: { $0.1 > $1.1 }) // sort descending modification dates
                .map { $0.0 }.filter({ $0.contains("-")})
            var totalSize: Int = 0
            orderedByDescending.forEach { (path) in
                totalSize += sizePerMB(url: cacheLocation.appendingPathComponent(path))
            }
            return totalSize
        }
        return 0
    }

    func sizePerMB(url: URL?) -> Int {
        guard let filePath = url?.path else {
            return 0
        }
        do {
            let attribute = try FileManager.default.attributesOfItem(atPath: filePath)
            if let size = attribute[FileAttributeKey.size] as? NSNumber {
                return Int(size.doubleValue / 1000000.0)
            }
        } catch {
            if DataCortex.loggingEnabled {
                print("[DATACORTEX] " + error.localizedDescription)
            }
        }
        return 0
    }

}
