//
//  ShelfSettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Defaults
import Foundation
import SwiftUI

struct Shelf: View {
    
    @Default(.shelfTapToOpen) var shelfTapToOpen: Bool
    @Default(.quickShareProvider) var quickShareProvider
    @Default(.expandedDragDetection) var expandedDragDetection: Bool
    @StateObject private var quickShareService = QuickShareService.shared

    private var selectedProvider: QuickShareProvider? {
        quickShareService.availableProviders.first(where: { $0.id == quickShareProvider })
    }
    
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .boringShelf) {
                    Text("settings.shelf.toggle.enable_shelf")
                }
                Defaults.Toggle(key: .openShelfByDefault) {
                    Text("settings.shelf.toggle.open_shelf_by_default_if_items_are_present")
                }
                Defaults.Toggle(key: .expandedDragDetection) {
                    Text("settings.shelf.toggle.expanded_drag_detection_area")
                }
                .onChange(of: expandedDragDetection) {
                    NotificationCenter.default.post(
                        name: Notification.Name.expandedDragDetectionChanged,
                        object: nil
                    )
                }
                Defaults.Toggle(key: .copyOnDrag) {
                    Text("settings.shelf.toggle.copy_items_on_drag")
                }
                Defaults.Toggle(key: .autoRemoveShelfItems) {
                    Text("settings.shelf.toggle.remove_from_shelf_after_dragging")
                }

            } header: {
                HStack {
                    Text("settings.shelf.section.general")
                }
            }
            
            Section {
                Picker("settings.shelf.picker.quick_share_service", selection: $quickShareProvider) {
                    ForEach(quickShareService.availableProviders, id: \.id) { provider in
                        HStack {
                            Group {
                                if let icon = quickShareService.icon(for: provider.id, size: 16) {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                            .frame(width: 16, height: 16)
                            .foregroundColor(.accentColor)
                            Text(provider.id)
                        }
                        .tag(provider.id)
                    }
                }
                .pickerStyle(.menu)
                
                if let selectedProvider = selectedProvider {
                    HStack {
                        Group {
                            if let icon = quickShareService.icon(for: selectedProvider.id, size: 16) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        .frame(width: 16, height: 16)
                        .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: String(localized: "settings.shelf.label.currently_selected_format"), locale: .current, arguments: [selectedProvider.id]))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("settings.shelf.helper.files_shared_via_this_service")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
            } header: {
                HStack {
                    Text("settings.shelf.section.quick_share")
                }
            } footer: {
                Text("settings.shelf.footer.choose_service")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("settings.sidebar.shelf")
    }
}
