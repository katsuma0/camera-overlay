import AVFoundation
import UIKit

struct CapturedPhoto {
    var data: Data
    var fileExtension: String
    /// The videoRotationAngle the photo was captured at.
    var angle: Double
    var date: Date
}

enum CameraError: LocalizedError {
    case unavailable
    case noPhotoData

    var errorDescription: String? {
        switch self {
        case .unavailable: return "The camera isn't ready yet. Give it a second and try again."
        case .noPhotoData: return "The camera didn't hand back a photo. Try again."
        }
    }
}

/// Owns the capture session. Always the back wide camera at 1x, so every photo in a project
/// comes from the same lens with the same field of view.
final class CameraModel: NSObject, ObservableObject {
    enum Status: Equatable {
        case idle, running, unauthorized, unavailable
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var isCapturing = false

    let session = AVCaptureSession()

    static let isSimulator: Bool = {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }()

    // Everything below is only touched on this queue.
    private let queue = DispatchQueue(label: "SameSpot.camera")
    private let photoOutput = AVCapturePhotoOutput()
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var isConfigured = false
    private var wantsRunning = false
    private var inFlight: [Int64: PhotoCaptureDelegate] = [:]

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRuntimeError),
            name: .AVCaptureSessionRuntimeError,
            object: session
        )
    }

    // MARK: Lifecycle

    func start() {
        if Self.isSimulator {
            status = .running
            return
        }
        queue.async { self.wantsRunning = true }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.startSession()
                    } else {
                        self.status = .unauthorized
                    }
                }
            }
        default:
            status = .unauthorized
        }
    }

    func stop() {
        guard !Self.isSimulator else { return }
        queue.async {
            self.wantsRunning = false
            // Unconditional on purpose. An interrupted session reports not running but restarts itself
            // when the interruption ends, unless it was told to stop.
            self.session.stopRunning()
        }
    }

    private func startSession() {
        queue.async {
            // The tab may have closed while the permission prompt was up.
            guard self.wantsRunning else { return }
            if !self.isConfigured {
                self.configure()
            }
            guard self.isConfigured else {
                DispatchQueue.main.async { self.status = .unavailable }
                return
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            DispatchQueue.main.async { self.status = .running }
        }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        session.beginConfiguration()
        if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo
        }
        guard session.canAddInput(input), session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        session.commitConfiguration()

        // The active format only settles after commit. Cap at 12 MP: plenty for a 4K video,
        // and a year of twice-a-day photos stays a reasonable size.
        let dimensions = device.activeFormat.supportedMaxPhotoDimensions
        let capped = dimensions.filter { $0.width <= 4032 }
        if let best = capped.max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }) ?? dimensions.first {
            photoOutput.maxPhotoDimensions = best
        }

        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        isConfigured = true
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        queue.async {
            guard self.wantsRunning, self.isConfigured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    // MARK: Capture

    /// Takes a photo. Pass the project's angle once it has one so the frame matches the original
    /// no matter how the phone is held. Pass nil for a first original to use the phone's actual orientation.
    func capture(lockedAngle: Double?, completion: @escaping (Result<CapturedPhoto, Error>) -> Void) {
        guard !isCapturing else { return }
        isCapturing = true
        let finish: (Result<CapturedPhoto, Error>) -> Void = { result in
            DispatchQueue.main.async {
                self.isCapturing = false
                completion(result)
            }
        }

        if Self.isSimulator {
            let angle = lockedAngle ?? 90
            DispatchQueue.global(qos: .userInitiated).async {
                finish(SimulatedCamera.capture(angle: angle))
            }
            return
        }

        queue.async {
            guard self.isConfigured, self.session.isRunning,
                  let connection = self.photoOutput.connection(with: .video) else {
                finish(.failure(CameraError.unavailable))
                return
            }

            let liveAngle = Double(self.rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 90)
            let angle = Self.snapped(lockedAngle ?? liveAngle)
            if connection.isVideoRotationAngleSupported(CGFloat(angle)) {
                connection.videoRotationAngle = CGFloat(angle)
            }

            let useHEVC = self.photoOutput.availablePhotoCodecTypes.contains(.hevc)
            let codec: AVVideoCodecType = useHEVC ? .hevc : .jpeg
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: codec])
            settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions

            let id = settings.uniqueID
            let delegate = PhotoCaptureDelegate(angle: angle, fileExtension: useHEVC ? "heic" : "jpg") { result in
                self.queue.async { self.inFlight[id] = nil }
                finish(result)
            }
            self.inFlight[id] = delegate
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    /// Rounds to the nearest quarter turn in 0..<360.
    static func snapped(_ angle: Double) -> Double {
        let value = ((angle / 90).rounded() * 90).truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let angle: Double
    private let fileExtension: String
    private let completion: (Result<CapturedPhoto, Error>) -> Void
    private var data: Data?
    private var processingError: Error?

    init(angle: Double, fileExtension: String, completion: @escaping (Result<CapturedPhoto, Error>) -> Void) {
        self.angle = angle
        self.fileExtension = fileExtension
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            processingError = error
        } else {
            data = photo.fileDataRepresentation()
        }
    }

    // Always the last callback for a capture, so it's the one place that reports back.
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        if let error = error ?? processingError {
            completion(.failure(error))
        } else if let data {
            completion(.success(CapturedPhoto(data: data, fileExtension: fileExtension, angle: angle, date: Date())))
        } else {
            completion(.failure(CameraError.noPhotoData))
        }
    }
}
