//
//  ChatView2.swift
//  TimePhotos
//
//  Created for TimePhotos App.
//

import SwiftUI
import Photos

struct ChatView2: View {
    @StateObject private var aiService: OpenAIPhotoService
    @State private var inputText: String = ""
    @State private var showAPIKeySettings: Bool = false
    @FocusState private var isInputFocused: Bool
    
    init(albums: [(year: Int, month: Int?, album: PHAssetCollection)], allAlbums: [ContentView.AlbumInfo], allPhotos: [(year: Int, month: Int?, assets: [PHAsset])], photosNotInAlbums: (photoCount: Int, videoCount: Int)) {
        _aiService = StateObject(wrappedValue: OpenAIPhotoService(albums: albums, allAlbums: allAlbums, allPhotos: allPhotos, photosNotInAlbums: photosNotInAlbums))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with API key settings
            HStack {
                Text("Chat 2 (OpenAI)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: { showAPIKeySettings.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: aiService.apiKey.isEmpty ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 12))
                        Text(aiService.apiKey.isEmpty ? "Set API Key" : "API Key Set")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(aiService.apiKey.isEmpty ? .orange : .green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .popover(isPresented: $showAPIKeySettings, arrowEdge: .bottom) {
                    apiKeySettingsView
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Messages area - selectable
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if aiService.messages.isEmpty {
                            welcomeMessage
                        } else {
                            ForEach(aiService.messages) { message in
                                MessageBubble2(message: message)
                                    .id(message.id)
                            }
                            
                            if aiService.isProcessing {
                                TypingIndicator()
                            }
                        }
                    }
                    .padding()
                }
                .textSelection(.enabled)
                .onChange(of: aiService.messages.count) {
                    if let lastMessage = aiService.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // Input area
            HStack(spacing: 12) {
                TextField("Ask me about your photos...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(20)
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .onSubmit {
                        sendMessage()
                    }
                
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(inputText.isEmpty ? .gray : .blue)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(inputText.isEmpty || aiService.isProcessing)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var welcomeMessage: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Chat with Your Photo Library (OpenAI)")
                .font(.system(size: 24, weight: .bold))
                .textSelection(.enabled)
            
            Text("Ask me anything about your photos using OpenAI's GPT-4")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            
            if aiService.apiKey.isEmpty {
                VStack(spacing: 12) {
                    Text("⚠️ API Key Required")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.orange)
                        .textSelection(.enabled)
                    
                    Text("Please set your OpenAI API key to start chatting")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                    
                    Button(action: { showAPIKeySettings = true }) {
                        Text("Set API Key")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Try asking:")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                    
                    suggestionButton("How many photos do I have?")
                    suggestionButton("What albums do I have from 2023?")
                    suggestionButton("Tell me about my photo library")
                    suggestionButton("What's the breakdown of my media types?")
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
    
    private var apiKeySettingsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("OpenAI API Key")
                .font(.system(size: 16, weight: .semibold))
            
            Text("Enter your OpenAI API key. It will be stored securely on your device.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            SecureField("sk-...", text: $aiService.apiKey)
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            
            HStack {
                Spacer()
                Button("Done") {
                    showAPIKeySettings = false
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.blue)
            }
        }
        .padding(16)
        .frame(width: 400)
    }
    
    private func suggestionButton(_ text: String) -> some View {
        Button(action: {
            inputText = text
            sendMessage()
        }) {
            HStack {
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 12))
                Text(text)
                    .font(.system(size: 12))
            }
            .foregroundColor(.blue)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func sendMessage() {
        guard !inputText.isEmpty && !aiService.isProcessing else { return }
        
        let message = inputText
        inputText = ""
        isInputFocused = false
        
        Task {
            await aiService.sendMessage(message)
        }
    }
}

// Selectable message bubble for Chat 2
struct MessageBubble2: View {
    let message: ChatMessage
    @State private var showCopyButton = false
    @State private var copied = false
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                ZStack(alignment: .bottomTrailing) {
                    MarkdownText(markdown: message.content, isUser: message.isUser)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            message.isUser
                                ? Color.blue
                                : Color(NSColor.controlBackgroundColor)
                        )
                        .cornerRadius(18)
                        .onHover { hovering in
                            if !message.isUser {
                                showCopyButton = hovering
                            }
                        }
                    
                    if !message.isUser && showCopyButton {
                        CopyButton2(text: message.content, copied: $copied)
                            .padding(8)
                    }
                }
                
                Text(message.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            
            if !message.isUser {
                Spacer(minLength: 60)
            }
        }
    }
}


// Copy button component for Chat 2
struct CopyButton2: View {
    let text: String
    @Binding var copied: Bool
    @State private var hovered = false
    
    var body: some View {
        Button(action: {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                copied = false
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                Text(copied ? "Copied!" : "Copy")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(copied ? .green : (hovered ? .blue : .secondary))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            hovered = hovering
        }
    }
}

