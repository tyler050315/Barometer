import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = DashboardViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    pressureSection
                    altitudeSection
                    locationSection
                    airportSection
                    statusSection
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Barometer")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isRefreshing)
                    .accessibilityLabel("Refresh")
                }
            }
            .task {
                await viewModel.start()
            }
        }
    }

    private var pressureSection: some View {
        metricPanel(title: "当前气压", value: UnitFormatter.pressure(viewModel.currentPressureHPa), footnote: "来自 iPhone 气压计")
    }

    private var altitudeSection: some View {
        metricPanel(title: "估算海拔", value: UnitFormatter.altitude(viewModel.altitudeMeters), footnote: "由本机气压和机场海平面气压计算")
    }

    private var locationSection: some View {
        panel {
            Text("当前位置")
                .font(.headline)
            Text(viewModel.locationText)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var airportSection: some View {
        panel {
            Text("参考机场")
                .font(.headline)

            if let airport = viewModel.referenceAirport {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(airport.icaoId) / \(airport.name)")
                        .font(.title3.weight(.semibold))
                    Text("距离 \(UnitFormatter.distance(airport.distanceKilometers))")
                        .foregroundStyle(.secondary)
                    Text("海平面气压 \(UnitFormatter.pressure(airport.seaLevelPressureHPa))")
                        .foregroundStyle(.secondary)
                    Text("METAR \(airport.observationText)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let rawText = airport.rawText {
                        Text(rawText)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            } else {
                Text("等待机场气压数据")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusSection: some View {
        panel {
            HStack(spacing: 10) {
                if viewModel.isRefreshing {
                    ProgressView()
                } else {
                    Image(systemName: viewModel.statusSymbol)
                        .foregroundStyle(viewModel.statusColor)
                }
                Text(viewModel.statusText)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metricPanel(title: String, value: String, footnote: String) -> some View {
        panel {
            Text(title)
                .font(.headline)
            Text(value)
                .font(.system(size: 42, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(footnote)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

#Preview {
    ContentView()
}
