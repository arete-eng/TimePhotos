//
//  ChatView.swift
//  TimePhotos
//
//  Created for TimePhotos App.
//

import SwiftUI
import Photos

struct ChatView: View {
    @StateObject private var aiService: PhotoLibraryAI
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    
    init(albums: [(year: Int, month: Int?, album: PHAssetCollection)], allAlbums: [ContentView.AlbumInfo], allPhotos: [(year: Int, month: Int?, assets: [PHAsset])], photosNotInAlbums: (photoCount: Int, videoCount: Int)) {
        _aiService = StateObject(wrappedValue: PhotoLibraryAI(albums: albums, allAlbums: allAlbums, allPhotos: allPhotos, photosNotInAlbums: photosNotInAlbums))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if aiService.messages.isEmpty {
                            welcomeMessage
                        } else {
                            ForEach(aiService.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                            
                            if aiService.isProcessing {
                                TypingIndicator()
                            }
                        }
                    }
                    .padding()
                }
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
            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Chat with Your Photo Library")
                .font(.system(size: 24, weight: .bold))
            
            Text("Ask me anything about your photos using Apple Intelligence")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Try asking:")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                
                suggestionButton("How many photos do I have?")
                suggestionButton("What albums do I have from 2023?")
                suggestionButton("Show me photos from January 2024")
                suggestionButton("Tell me about my photo library")
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
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

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.system(size: 14))
                    .foregroundColor(message.isUser ? .white : .primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        message.isUser
                            ? Color.blue
                            : Color(NSColor.controlBackgroundColor)
                    )
                    .cornerRadius(18)
                
                Text(message.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            if !message.isUser {
                Spacer(minLength: 60)
            }
        }
    }
}

struct TypingIndicator: View {
    @State private var animationPhase = 0
    
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                        .opacity(animationPhase == index ? 0.3 : 1.0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(18)
            
            Spacer(minLength: 60)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever()) {
                animationPhase = (animationPhase + 1) % 3
            }
        }
    }
}

