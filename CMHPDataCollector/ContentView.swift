//
//  ContentView.swift
//  CMHPDataCollector
//
//  Created by Jason on 6/10/24.

import SwiftUI
import UIKit
import SceneKit

struct ContentView: View {
    @StateObject private var viewModel = HeadphonePoseViewModel()
    @State private var label: String = ""
    @State private var showingDocumentPicker = false
    
    var body: some View {
        VStack {
            SceneView(scene: viewModel.scene, pointOfView: viewModel.cameraNode)
                .frame(height: 350)
            
            HStack {
                Spacer()
                Button(action: {
                    viewModel.toggleTracking(label: label)
                    
                }) {
                    Text(viewModel.motionButtonTitle)
                }
                .disabled(!viewModel.isMotionButtonEnabled)
                Spacer()
                Button(action: viewModel.setReferenceFrame) {
                    Text("Reset Frame")
                }
                .disabled(!viewModel.isReferenceButtonVisible)
                Spacer()
            }
        }
        .onAppear {
            viewModel.setupScene()
        }
        
        VStack {
                TextField("Enter Activity Label", text: $label)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            Text("Duration: \(viewModel.duration)")
                .font(.headline)
                .padding(.top)
            
            HStack {
                Spacer()
                Button("Save") {
                    viewModel.saveCSV(label: label)
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
                .disabled(viewModel.isCollecting)
                Spacer()
                Button("Export") {
                    showingDocumentPicker = true
                }
                .padding()
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(8)
                .sheet(isPresented: $showingDocumentPicker) {
                    DocumentPicker(urls: viewModel.exportFiles())
                }
                Spacer()
                Button("Remove All") {
                                viewModel.removeAllFiles()
                            }
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(8)
                Spacer()
                
            }
            List {
                ForEach(viewModel.savedFiles, id: \.self) { file in
                    Text(file)
                }
                .onDelete { indexSet in
                    indexSet.forEach { index in
                        let fileName = viewModel.savedFiles[index]
                        viewModel.deleteFile(named: fileName)
                    }
                }
            }
        }
        .padding()
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    var urls: [URL]
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: urls)
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

#Preview {
    ContentView()
}
