import CoreVideo

extension CVPixelBuffer {
    func getTouchPoints(gridSize: Int) -> [CGPoint] {
        let width = CVPixelBufferGetWidth(self)
        let height = CVPixelBufferGetHeight(self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(self)
        
        // Lock buffer
        CVPixelBufferLockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0))
        
        // Unlock buffer upon exiting
        defer {
            CVPixelBufferUnlockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0))
        }
        
        var points: [CGPoint] = []
        
        if let baseAddress = CVPixelBufferGetBaseAddress(self) {
            let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
            
            for y in stride(from: Int(ceil(Float(gridSize) / 2.0)), to: height, by: gridSize) {
                for x in stride(from: Int(ceil(Float(gridSize) / 2.0)), to: width, by: gridSize) {
                    // We look at top groups of 5 non black pixels
                    let pixel = buffer[y * bytesPerRow + x * 4]
                    let abovePixel = buffer[min(y + 1, height) * bytesPerRow + x * 4]
                    let belowPixel = buffer[max(y - 1, 0) * bytesPerRow + x * 4]
                    let rightPixel = buffer[y * bytesPerRow + min(x + 1, width) * 4]
                    let leftPixel = buffer[y * bytesPerRow + max(x - 1, 0) * 4]
                    
                    if pixel > 0 && abovePixel > 0 && belowPixel > 0 && rightPixel > 0 && leftPixel > 0 {
                        let normalizedPoint = CGPoint(x: CGFloat(x) / CGFloat(width), y: CGFloat(y) / CGFloat(height))
                        points.append(normalizedPoint)
                    }
                }
            }
        }
        
        return points
    }
}
