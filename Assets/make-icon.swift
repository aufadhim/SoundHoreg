import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let rect = CGRect(x: 48, y: 48, width: 928, height: 928)
context.addPath(CGPath(roundedRect: rect, cornerWidth: 210, cornerHeight: 210, transform: nil))
context.setFillColor(CGColor(red: 0.07, green: 0.11, blue: 0.13, alpha: 1)); context.fillPath()
context.setStrokeColor(CGColor(red: 0.47, green: 0.85, blue: 0.70, alpha: 1)); context.setLineWidth(46); context.setLineCap(.round); context.setLineJoin(.round)
let points: [(Double,Double)] = [(200,512),(290,512),(340,620),(400,300),(470,760),(540,250),(605,685),(666,425),(715,512),(824,512)]
context.move(to: CGPoint(x:points[0].0,y:points[0].1)); for p in points.dropFirst(){context.addLine(to:CGPoint(x:p.0,y:p.1))};context.strokePath()
let image=context.makeImage()!
let url=URL(fileURLWithPath:CommandLine.arguments[1]);let destination=CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString,1,nil)!;CGImageDestinationAddImage(destination,image,nil);CGImageDestinationFinalize(destination)
