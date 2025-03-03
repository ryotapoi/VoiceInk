import SwiftUI

struct VisualizerView: View {
    @ObservedObject var recorder: Recorder
    private let barCount = 50
    @State private var levels: [BarLevel] = []
    private let smoothingFactor: Double = 0.3
    
    struct BarLevel: Equatable {
        var average: CGFloat
        var peak: CGFloat
    }
    
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<barCount, id: \.self) { index in
                    VisualizerBar(level: levels.isEmpty ? BarLevel(average: 0, peak: 0) : levels[index])
                        .frame(width: (geometry.size.width - CGFloat(barCount - 1) * 4) / CGFloat(barCount))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.black.opacity(0.1))
            .cornerRadius(10)
            .onAppear {
                levels = Array(repeating: BarLevel(average: 0, peak: 0), count: barCount)
            }
            .onReceive(recorder.$audioMeter) { newMeter in
                updateLevels(with: newMeter)
            }
        }
    }
    
    private func updateLevels(with meter: AudioMeter) {
        // Create new levels with randomization for visual interest
        var newLevels: [BarLevel] = []
        for i in 0..<barCount {
            let randomFactor = Double.random(in: 0.8...1.2)
            let targetAverage = min(max(meter.averagePower * randomFactor, 0), 1)
            let targetPeak = min(max(meter.peakPower * randomFactor, 0), 1)
            
            let currentLevel = levels[i]
            let smoothedAverage = currentLevel.average + (CGFloat(targetAverage) - currentLevel.average) * CGFloat(smoothingFactor)
            let smoothedPeak = currentLevel.peak + (CGFloat(targetPeak) - currentLevel.peak) * CGFloat(smoothingFactor)
            
            newLevels.append(BarLevel(
                average: smoothedAverage,
                peak: smoothedPeak
            ))
        }
        
        withAnimation(.easeInOut(duration: 0.15)) {
            levels = newLevels
        }
    }
}

struct VisualizerBar: View {
    let level: VisualizerView.BarLevel
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Average level bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue.opacity(0.7), .purple.opacity(0.7)]),
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(height: level.average * geometry.size.height)
                
                // Peak level indicator
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue, .purple]),
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(height: 2)
                    .offset(y: -level.peak * geometry.size.height + 1)
                    .opacity(level.peak > 0.01 ? 1 : 0)
            }
            .frame(maxHeight: geometry.size.height, alignment: .bottom)
        }
    }
}
