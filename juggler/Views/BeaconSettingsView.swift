import SwiftUI

struct BeaconSettingsView: View {
    @AppStorage(AppStorageKeys.beaconEnabled) private var beaconEnabled = true
    @AppStorage(AppStorageKeys.beaconPosition) private var beaconPosition: String = BeaconPosition.default.rawValue
    @AppStorage(AppStorageKeys.beaconAnchor) private var beaconAnchor: String = BeaconAnchor.default.rawValue
    @AppStorage(AppStorageKeys.beaconSize) private var beaconSize: String = BeaconSize.default.rawValue
    @AppStorage(AppStorageKeys.beaconDuration) private var beaconDuration: Double = 1.5

    var body: some View {
        Form {
            Section("Beacon HUD") {
                Picker("Position", selection: $beaconPosition) {
                    ForEach(BeaconPosition.allCases, id: \.rawValue) { position in
                        Text(position.displayName).tag(position.rawValue)
                    }
                }
                .disabled(!beaconEnabled)

                Picker("Relative to", selection: $beaconAnchor) {
                    ForEach(BeaconAnchor.allCases, id: \.rawValue) { anchor in
                        Text(anchor.displayName).tag(anchor.rawValue)
                    }
                }
                .disabled(!beaconEnabled)

                Picker("Size", selection: $beaconSize) {
                    ForEach(BeaconSize.allCases, id: \.rawValue) { size in
                        Text(size.displayName).tag(size.rawValue)
                    }
                }
                .disabled(!beaconEnabled)

                Picker("Duration", selection: $beaconDuration) {
                    Text("0.5 seconds").tag(0.5)
                    Text("1 second").tag(1.0)
                    Text("1.5 seconds").tag(1.5)
                    Text("2 seconds").tag(2.0)
                    Text("3 seconds").tag(3.0)
                }
                .disabled(!beaconEnabled)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
