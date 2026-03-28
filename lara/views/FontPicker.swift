//
//  FontPicker.swift
//  lara
//
//  Created by ruter on 28.03.26.
//

import SwiftUI
import CoreText
import UIKit

struct FontPicker: View {
    @ObservedObject var mgr: laramgr

    private func applyfont(_ resource: String, label: String) {
        let success = mgr.kfsoverwrite(target: laramgr.fontpath, withBundledFont: resource)
        success ? mgr.logmsg("font changed to \(label)") : mgr.logmsg("failed to change font")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        applyfont("SFUI", label: "SFUI")
                    } label: {
                        Text("SFUI (Normal Font)")
                            .font(viewfont(resource: "SFUI", size: 17))
                    }
                    
                    Button {
                        applyfont("Comic Sans MS", label: "Comic Sans MS")
                    } label: {
                        Text("Comic Sans MS")
                            .font(viewfont(resource: "Comic Sans MS", size: 17))
                    }

                    Button {
                        applyfont("Chococooky", label: "Chococooky")
                    } label: {
                        Text("Chococooky")
                            .font(viewfont(resource: "Chococooky", size: 17))
                    }

                    Button {
                        applyfont("DejaVuSansMono", label: "DejaVuSansMono")
                    } label: {
                        Text("DejaVu Sans Mono")
                            .font(viewfont(resource: "DejaVuSansMono", size: 17))
                    }

                    Button {
                        applyfont("DejaVuSansCondensed", label: "DejaVuSansCondensed")
                    } label: {
                        Text("DejaVu Sans Condensed")
                            .font(viewfont(resource: "DejaVuSansCondensed", size: 17))
                    }

                    Button {
                        applyfont("DejaVuSerif", label: "DejaVuSerif")
                    } label: {
                        Text("DejaVu Serif")
                            .font(viewfont(resource: "DejaVuSerif", size: 17))
                    }

                    Button {
                        applyfont("FiraSans-Regular", label: "FiraSans")
                    } label: {
                        Text("Fira Sans")
                            .font(viewfont(resource: "FiraSans-Regular", size: 17))
                    }

                    Button {
                        applyfont("Go-Mono", label: "Go-Mono")
                    } label: {
                        Text("Go Mono")
                            .font(viewfont(resource: "Go-Mono", size: 17))
                    }

                    Button {
                        applyfont("Go-Regular", label: "Go-Regular")
                    } label: {
                        Text("Go Regular")
                            .font(viewfont(resource: "Go-Regular", size: 17))
                    }

                    Button {
                        applyfont("segoeui", label: "Segoe UI")
                    } label: {
                        Text("Segoe UI")
                            .font(viewfont(resource: "segoeui", size: 17))
                    }
                } header: {
                    Text("Fonts")
                } footer: {
                    Text("Fira Sans currently broken. If you want to fix it, create a pull request or something.")
                }
                
                Section {
                    Text(globallogger.logs.last ?? "No logs yet")
                        .font(.system(size: 13, design: .monospaced))
                    
                    if #available(iOS 18.2, *) {
                        Button("Respring") {
                            mgr.respring()
                        }
                    }
                }
            }
            .navigationTitle("Font Overwrite")
        }
    }
}

private func viewfont(resource: String, size: CGFloat) -> Font {
    if let url = Bundle.main.url(forResource: resource, withExtension: "ttf", subdirectory: "fonts")
        ?? Bundle.main.url(forResource: resource, withExtension: "ttf", subdirectory: "Fonts")
        ?? Bundle.main.url(forResource: resource, withExtension: "ttf") {
        if let data = try? Data(contentsOf: url) as CFData,
           let provider = CGDataProvider(data: data),
           let cgFont = CGFont(provider) {
            let ctFont = CTFontCreateWithGraphicsFont(cgFont, size, nil, nil)
            let uiFont = ctFont as UIFont
            return Font(uiFont)
        }
    }
    return .system(size: size)
}
