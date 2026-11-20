import SwiftUI

struct ChartSeries: Identifiable {
    let id = UUID()
    var values: [Double]
    var color: Color
    var lineWidth: CGFloat = 2
    var showPoints: Bool = false
}

/// A small line chart drawn with plain SwiftUI shapes (x axis = session number).
struct LineChartView: View {
    let series: [ChartSeries]
    let yMin: Double
    let yMax: Double
    var goal: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let leftPad: CGFloat = 40
            let bottomPad: CGFloat = 6
            let w = max(1, geo.size.width - leftPad - 6)
            let h = max(1, geo.size.height - bottomPad - 8)
            let count = series.map { $0.values.count }.max() ?? 0
            let span = max(0.0001, yMax - yMin)
            let yFor: (Double) -> CGFloat = { v in
                let clamped = min(max(v, yMin), yMax)
                return 4 + h * CGFloat(1 - (clamped - yMin) / span)
            }
            let xFor: (Int) -> CGFloat = { i in
                count > 1 ? leftPad + w * CGFloat(i) / CGFloat(count - 1) : leftPad + w / 2
            }
            ZStack(alignment: .topLeading) {
                ForEach(0..<5, id: \.self) { i in
                    let frac = Double(i) / 4.0
                    let value = yMin + (yMax - yMin) * frac
                    let y = yFor(value)
                    Path { p in
                        p.move(to: CGPoint(x: leftPad, y: y))
                        p.addLine(to: CGPoint(x: leftPad + w, y: y))
                    }
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    Text(String(format: "%.0f", value))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .position(x: leftPad - 20, y: y)
                }

                if let g = goal {
                    Path { p in
                        p.move(to: CGPoint(x: leftPad, y: yFor(g)))
                        p.addLine(to: CGPoint(x: leftPad + w, y: yFor(g)))
                    }
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }

                ForEach(series) { s in
                    Path { p in
                        for (i, v) in s.values.enumerated() {
                            let pt = CGPoint(x: xFor(i), y: yFor(v))
                            if i == 0 {
                                p.move(to: pt)
                            } else {
                                p.addLine(to: pt)
                            }
                        }
                    }
                    .stroke(s.color, style: StrokeStyle(lineWidth: s.lineWidth, lineCap: .round, lineJoin: .round))

                    if s.showPoints {
                        ForEach(0..<s.values.count, id: \.self) { i in
                            Circle()
                                .fill(s.color)
                                .frame(width: 6, height: 6)
                                .position(x: xFor(i), y: yFor(s.values[i]))
                        }
                    }
                }
            }
        }
    }
}
