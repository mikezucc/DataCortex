![neura](https://themindunleashed.com/wp-content/uploads/2015/08/squirrel.jpg)

# DataCortex
AWS S3 is easy! A streamlined class to upload, download, and manage caches for files on AWS S3.

Taken from a project I am working to make your life ez pz.

## Configuring

0. For the following step, please use the identity pool technique, it is confusing AF but it really is better
1. Follow AWS S3 iOS SDK guide on adding the dependencies and configuration files to your project using Pods
2. Set your `DataCortex.identityPoolId = "us-east-1:<a-long-uuid>"`
3. You're done. Begin using!
4. If something is not working, enable logging `DataCortex.loggingEnabled = true`

## PUT Images

```swift
DataCortex.neura.setImage(image: i,
                          for: ident,
                          completion: { (image, code, progress) in
                                          print("image: \(ident) code: \(code) progress: \(progress)")
                                        })
```
A full copy-pasta for using `PHAsset`
```swift
let images: [PHAsset] = .... from an image picker
let manager = PHImageManager.default()
let options = PHImageRequestOptions()
options.isSynchronous = false
options.deliveryMode = .highQualityFormat
options.isNetworkAccessAllowed = true // allow this to pull from shared albums, iCloud, etc.

var finishedItems = [UIImage]()
images.compactMap({$0.asset}).forEach { (asset) in
    let aspectRatio = asset.pixelHeight / asset.pixelWidth
    let width = min(asset.pixelWidth, Int(view.bounds.size.width))
    var height = asset.pixelHeight
    if width != asset.pixelWidth {
        height = width * aspectRatio
    }
    manager.requestImage(for: asset,
                         targetSize: CGSize(width: asset.pixelWidth, height: asset.pixelHeight),
                         contentMode: PHImageContentMode.default,
                         options: options,
                         resultHandler: { [weak self] (image, configs) in
                            var ident = asset.localIdentifier
                            ident = ident.replacingOccurrences(of: "/", with: "")
                            guard let i = image else {
                                return
                            }

                            DataCortex.neura.setImage(image: i,
                                                      for: ident,
                                                      completion: { (image, code, progress) in
                                                      print("image: \(ident) code: \(code) progress: \(progress)")
                            })
    })
}
```

## GET Images

```swift
let _ = DataCortex.neura.image(for: imageKey) { (image, recallCode, progress) in
                                                    if recallCode != .loaded {
                                                        return
                                                    }
                                                    if let i = image {
                                                        cell?.coverImageView?.image = i
                                                    }
                                                }
```

## Check Cache Size

```swift
cacheSizeButton?.setTitle("Clear Cached Media: \(DataCortex.neura.sizeOfMediaCache())MB", for: UIControl.State.normal)
```

## Clear Cache

```swift
DataCortex.neura.purgeAllCache()
```

## Let the DataCortex auto-clean up the cache

```swift
DataCortex.neura.purgeStaleNeura()
```
