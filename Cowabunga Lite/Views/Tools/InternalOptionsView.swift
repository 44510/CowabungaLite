//
//  InternalOptionsView.swift
//  Cowabunga Lite
//
//  Created by lemin on 5/15/23.
//

import Foundation
import SwiftUI

struct InternalOptionsView: View {
    @StateObject private var logger = Logger.shared
    @StateObject private var dataSingleton = DataSingleton.shared
    @State private var enableTweak: Bool = false
    
    struct SBOption: Identifiable {
        var id = UUID()
        var key: String
        var name: String
        var fileLocation: MainUtils.FileLocation
        var value: Bool = false
        var dividerBelow: Bool = false
    }
    
    @State private var sbOptions: [SBOption] = [
//        .init(key: "DebugConsoleEnabled", name: "Maps App Debug Console", fileLocation: .maps),
//        .init(key: "VKConsoleEnabledKey", name: "Maps App VK Console", fileLocation: .maps, dividerBelow: true),
//        .init(key: "weather.vfx.overrideConditionBackground", name: "Weather App Override Condition Background", fileLocation: .weather)
    ]
    
    var body: some View {
        List {
            Group {
                HStack {
                    Image(systemName: "internaldrive")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 35, height: 35)
                    VStack {
                        HStack {
                            Text("Internal Options")
                                .bold()
                            Spacer()
                        }
                        HStack {
                            Toggle("Modify", isOn: $enableTweak).onChange(of: enableTweak, perform: {nv in
                                DataSingleton.shared.setTweakEnabled(.internalOptions, isEnabled: nv)
                            }).onAppear(perform: {
                                enableTweak = DataSingleton.shared.isTweakEnabled(.internalOptions)
                            })
                            Spacer()
                        }
                    }
                }
                Divider()
                if dataSingleton.deviceAvailable {
                    Group {
                        ForEach($sbOptions) { option in
                            Toggle(isOn: option.value) {
                                Text(option.name.wrappedValue)
                                    .minimumScaleFactor(0.5)
                            }.onChange(of: option.value.wrappedValue) { new in
                                do {
                                    guard let plistURL = DataSingleton.shared.getCurrentWorkspace()?.appendingPathComponent(option.fileLocation.wrappedValue.rawValue) else {
                                        Logger.shared.logMe("Error finding internal plist \(option.fileLocation.wrappedValue.rawValue)")
                                        return
                                    }
                                    try PlistManager.setPlistValues(url: plistURL, values: [
                                        option.key.wrappedValue: option.value.wrappedValue
                                    ])
                                } catch {
                                    Logger.shared.logMe(error.localizedDescription)
                                    return
                                }
                            }
                            .onAppear {
                                do {
                                    guard let plistURL = DataSingleton.shared.getCurrentWorkspace()?.appendingPathComponent(option.fileLocation.wrappedValue.rawValue) else {
                                        Logger.shared.logMe("Error finding internal plist \(option.fileLocation.wrappedValue.rawValue)")
                                        return
                                    }
                                    option.value.wrappedValue =  try PlistManager.getPlistValues(url: plistURL, key: option.key.wrappedValue) as? Bool ?? false
                                } catch {
                                    Logger.shared.logMe("Error finding internal plist \(option.fileLocation.wrappedValue.rawValue)")
                                    return
                                }
                            }
                            if option.dividerBelow.wrappedValue {
                                Divider()
                            }
                        }
                    }.disabled(!enableTweak)
                }
            }.disabled(!dataSingleton.deviceAvailable)
                .hideSeparator()
                .onAppear {
                    if sbOptions.isEmpty {
                        for opt in MainUtils.internalOptions {
                            sbOptions.append(.init(key: opt.key, name: opt.name, fileLocation: opt.fileLocation, dividerBelow: opt.dividerBelow))
                        }
                    }
                }
        }
    }
}

struct InternalOptionsView_Previews: PreviewProvider {
    static var previews: some View {
        InternalOptionsView()
    }
}
