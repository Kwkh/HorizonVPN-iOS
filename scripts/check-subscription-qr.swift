import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

@main struct QRCheck {
    static func main() async throws {
        let original = "https://example.invalid/sub?token=FAKE%2B%26%3D&format=clash"
        let direct = try SubscriptionQRCode.link(from: original)
        precondition(direct == original)
        var wrapper = URLComponents(string: "clash://install-config")!
        wrapper.queryItems = [.init(name: "url", value: original), .init(name: "name", value: "not-used")]
        let wrapped = try SubscriptionQRCode.link(from: wrapper.string!)
        precondition(wrapped == original)
        let unique = try SubscriptionQRCode.uniqueLink(in: [original, original, "unrelated"])
        precondition(unique == original)
        for invalid in ["http://example.invalid/sub", "vmess://FAKE", "javascript:alert(1)", "plain text", "https://user:pass@example.invalid", "clash://install-config?url=https://a.invalid&url=https://b.invalid", "clash://install-config?url=vmess%3A%2F%2FFAKE", String(repeating: "x", count: 8193)] {
            do { _ = try SubscriptionQRCode.link(from: invalid); fatalError("unsafe payload accepted") }
            catch SubscriptionQRCode.Failure.unsupported { }
        }
        do { _ = try SubscriptionQRCode.uniqueLink(in: [original, "https://other.invalid/sub"]); fatalError("ambiguous scan accepted") }
        catch SubscriptionQRCode.Failure.multiple { }
        let node = "vless://11111111-1111-4111-8111-111111111111@node.example.invalid:443?security=tls&type=ws&path=%2Fws#EXAMPLE"
        let nodeLink = try SubscriptionQRCode.link(from: node)
        precondition(nodeLink == node)
        let tuic = "tuic://11111111-1111-4111-8111-111111111111:FICTIONAL@node.example.invalid:443?congestion_control=bbr&udp_relay_mode=native&alpn=h3&insecure=0#TUIC"
        let tuicLink = try SubscriptionQRCode.link(from: tuic)
        precondition(tuicLink == tuic)
        let tuicImport = try await SubscriptionImportLoader.load(tuicLink, permitsNetwork: false)
        let tuicPrepared = try PrototypeConfiguration.prepare(tuicImport.data)
        precondition(tuicPrepared.catalog.nodes.count == 1 && tuicPrepared.insecureNodeCount == 0)
        let local = try await SubscriptionImportLoader.load(node, permitsNetwork: false)
        precondition(local.sourceURL == nil && local.data == Data(node.utf8))
        let encoded = Data(node.utf8).base64EncodedString()
        let list = try await SubscriptionImportLoader.load(encoded, permitsNetwork: false)
        let preparedList = try PrototypeConfiguration.prepare(list.data)
        precondition(preparedList.catalog.nodes.count == 1)
        do { _ = try await SubscriptionImportLoader.load(original, permitsNetwork: false); fatalError("offline download accepted") }
        catch SubscriptionDownloader.Failure.transport { }
        do { _ = try SubscriptionQRCode.uniqueLink(in: [node, original]); fatalError("mixed ambiguous scan accepted") }
        catch SubscriptionQRCode.Failure.multiple { }
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue(Data(original.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        let qr = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let canvas = CIImage(color: CIColor.white).cropped(to: qr.extent.insetBy(dx: -50, dy: -50))
        let composite = qr.composited(over: canvas)
        let cg = CIContext(options: [.useSoftwareRenderer: true]).createCGImage(composite, from: composite.extent)!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, cg, nil)
        precondition(CGImageDestinationFinalize(destination))
        let decoded = try QRCodeImageReader.read(data as Data)
        precondition(decoded == original)
        try (data as Data).write(to: URL(fileURLWithPath: "/private/tmp/clash-qr-fixture.png"))
        do { _ = try QRCodeImageReader.read(Data("not an image".utf8)); fatalError("invalid image accepted") }
        catch SubscriptionQRCode.Failure.unreadableImage { }
        filter.setValue(Data(node.utf8), forKey: "inputMessage")
        let nodeQR = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let nodeCanvas = CIImage(color: CIColor.white).cropped(to: nodeQR.extent.insetBy(dx: -50, dy: -50))
        let nodeComposite = nodeQR.composited(over: nodeCanvas)
        let nodeCG = CIContext(options: [.useSoftwareRenderer: true]).createCGImage(nodeComposite, from: nodeComposite.extent)!
        let nodeData = NSMutableData()
        let nodeDestination = CGImageDestinationCreateWithData(nodeData, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(nodeDestination, nodeCG, nil)
        precondition(CGImageDestinationFinalize(nodeDestination))
        let decodedNode = try QRCodeImageReader.read(nodeData as Data)
        precondition(decodedNode == node)
        print("PASS: node URI image decoding and offline import; QR decoding, encoded token preservation, HTTPS-only downloads, duplicate/ambiguous codes and invalid images; synthetic data only")
    }
}
