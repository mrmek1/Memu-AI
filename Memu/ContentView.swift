import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var chatViewModel: ChatViewModel
    @State private var messageText = ""
    @FocusState private var isFocused: Bool
    @State private var showingSidebar = false
    @State private var showingSettings = false
    
    var body: some View {
        NavigationView {
            ZStack {
               
                Color(hex: "0D1117")
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    
                    header
                    
                    
                    chatArea
                    
                    
                    inputArea
                }
            }
            .sheet(isPresented: $showingSidebar) {
                ConversationsList()
                    .environmentObject(chatViewModel)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(chatViewModel)
            }
        }
    }
    
    private var header: some View {
        HStack(spacing: 16) {
            Button {
                showingSidebar = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "58A6FF"), Color(hex: "238636")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                )
            
            Text("Memu")
                .font(.title3.weight(.bold))
                .foregroundColor(.white)
            
            Spacer()
            
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gear")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            
            Button {
                chatViewModel.startNewConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.title2)
                    .foregroundColor(.white)
            }
        }
        .padding()
        .background(Color(hex: "161B22"))
    }
    
    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 20) {
                    ForEach(chatViewModel.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    
                    if chatViewModel.isTyping {
                        TypingBubble()
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding()
            }
            .onChange(of: chatViewModel.messages.count, initial: true) { oldValue, newValue in
                withAnimation {
                    proxy.scrollTo(chatViewModel.messages.last?.id, anchor: .bottom)
                }
            }
            .background(Color(hex: "0D1117"))
        }
    }
    
    private var inputArea: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.1))
            
            HStack(spacing: 12) {
                TextField("Mesajınızı yazın...", text: $messageText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(12)
                    .background(Color(hex: "161B22"))
                    .cornerRadius(25)
                    .foregroundColor(.white)
                    .focused($isFocused)
                    .submitLabel(.send)
                    .onSubmit(sendMessage)
                
                Button(action: sendMessage) {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color(hex: chatViewModel.userSettings.accentColor),
                                    Color(hex: chatViewModel.userSettings.accentColor).opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "arrow.up")
                                .foregroundColor(.white)
                                .font(.system(size: 20, weight: .semibold))
                        )
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(hex: "0D1117"))
        }
    }
    
    private func sendMessage() {
        let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        chatViewModel.sendMessage(trimmedText)
        messageText = ""
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    @EnvironmentObject private var chatViewModel: ChatViewModel
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    
    private let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter
    }()
    
    private var shouldShowDate: Bool {
        guard let index = chatViewModel.messages.firstIndex(where: { $0.id == message.id }) else {
            return true
        }
        
        if index > 0 {
            let previousMessage = chatViewModel.messages[index - 1]
            return !Calendar.current.isDate(previousMessage.timestamp, inSameDayAs: message.timestamp)
        }
        
        return true
    }
    
    private func formattedContent(_ content: String) -> AnyView {
        let formatted = chatViewModel.parseResponse(content)
        
        switch formatted.format {
        case .normal:
            return AnyView(
                Text(content)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        Group {
                            if message.role == .user {
                                LinearGradient(
                                    colors: [Color(hex: chatViewModel.userSettings.accentColor),
                                            Color(hex: chatViewModel.userSettings.accentColor).opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            } else {
                                Color(hex: "161B22")
                            }
                        }
                    )
                    .cornerRadius(20)
            )
            
        case .list(let items):
            return AnyView(
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .foregroundColor(.gray)
                            Text(item)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(hex: "161B22"))
                .cornerRadius(20)
            )
            
        case .gameRecommendation(let games):
            return AnyView(
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(games, id: \.name) { game in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(game.name)
                                .font(.headline)
                            
                            if let platform = game.platform {
                                Text("Platform: \(platform)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            
                            if let genre = game.genre {
                                Text("Tür: \(genre)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            
                            if let desc = game.description {
                                Text(desc)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .padding(.top, 2)
                            }
                        }
                        .padding(8)
                        .background(Color(hex: "161B22").opacity(0.5))
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(hex: "161B22"))
                .cornerRadius(20)
            )
            
        case .error:
            return AnyView(
                Text(content)
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(hex: "161B22"))
                    .cornerRadius(20)
            )
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            if shouldShowDate {
                Text(fullDateFormatter.string(from: message.timestamp))
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.vertical, 8)
            }
            
            HStack(alignment: .bottom) {
                if message.role == .user {
                    Spacer(minLength: 60)
                }
                
                VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                    if message.role == .assistant {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [Color(hex: "58A6FF"), Color(hex: "238636")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Image(systemName: "brain.head.profile")
                                        .font(.caption2)
                                        .foregroundColor(.white)
                                )
                            Text("Memu")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding(.leading, 8)
                    } else {
                        Text(chatViewModel.userSettings.userName)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.trailing, 8)
                    }
                    
                    HStack(alignment: .bottom, spacing: 8) {
                        if message.role == .assistant {
                            formattedContent(message.content)
                            
                            Text(dateFormatter.string(from: message.timestamp))
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .padding(.bottom, 4)
                        } else {
                            Text(dateFormatter.string(from: message.timestamp))
                                .font(.caption2)
                                .foregroundColor(.gray.opacity(0.8))
                                .padding(.bottom, 4)
                            
                            formattedContent(message.content)
                        }
                    }
                }
                
                if message.role == .assistant {
                    Spacer(minLength: 60)
                }
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
    }
}

struct TypingBubble: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { _ in
                    Circle()
                        .fill(Color(hex: "58A6FF"))
                        .frame(width: 8, height: 8)
                        .scaleEffect(isAnimating ? 0.6 : 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(hex: "161B22"))
            .cornerRadius(20)
            
            Spacer()
        }
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 0.6).repeatForever()) {
                isAnimating = true
            }
        }
    }
}

struct ConversationsList: View {
    @EnvironmentObject private var chatViewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteAlert = false
    @State private var conversationToDelete: UUID?
    
    var body: some View {
        NavigationView {
            List {
                ForEach(chatViewModel.conversations) { conversation in
                    ConversationRow(conversation: conversation) {
                        withAnimation {
                            chatViewModel.loadConversation(conversation.id)
                        }
                        dismiss()
                    } onDelete: {
                        conversationToDelete = conversation.id
                        showingDeleteAlert = true
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Sohbetler")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(hex: "0D1117"))
            .scrollContentBackground(.hidden)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        chatViewModel.startNewConversation()
                        dismiss()
                    } label: {
                        Label("Yeni Sohbet", systemImage: "square.and.pencil")
                            .foregroundColor(Color(hex: "58A6FF"))
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .font(.title3)
                    }
                }
            }
        }
        .interactiveDismissDisabled()
        .alert("Sohbeti Sil", isPresented: $showingDeleteAlert) {
            Button("İptal", role: .cancel) {}
            Button("Sil", role: .destructive) {
                if let id = conversationToDelete {
                    withAnimation {
                        chatViewModel.deleteConversation(id)
                    }
                }
            }
        } message: {
            Text("Bu sohbet kalıcı olarak silinecek. Bu işlem geri alınamaz.")
        }
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    let onTap: () -> Void
    let onDelete: () -> Void
    @EnvironmentObject private var chatViewModel: ChatViewModel
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(hex: "58A6FF"), Color(hex: "238636")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "bubble.left.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 20))
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(conversation.title)
                        .lineLimit(1)
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .medium))
                    
                    Text("\(conversation.messages.count) mesaj")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                if conversation.id == chatViewModel.selectedConversationId {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(hex: "238636"))
                        .font(.title3)
                }
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.8))
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
        }
        .listRowBackground(Color(hex: "161B22"))
        .listRowSeparator(.hidden)
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var chatViewModel: ChatViewModel
    @State private var userName: String = ""
    @State private var selectedColor: String = "58A6FF"
    
    let colorOptions = [
        "58A6FF", // mavi
        "238636", // yeeeşil
        "A371F7", // mor
        "F85149", // kırmız
        "DB61A2", // pembee
        "F0883E"  // turncu
    ]
    
    var body: some View {
        NavigationView {
            Form {
                Section("Profil") {
                    TextField("Adınız", text: $userName)
                }
                
                Section("Tema Rengi") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                        ForEach(colorOptions, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle()
                                        .strokeBorder(.white, lineWidth: selectedColor == color ? 2 : 0)
                                )
                                .onTapGesture {
                                    selectedColor = color
                                }
                        }
                    }
                }
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kaydet") {
                        chatViewModel.userSettings.userName = userName
                        chatViewModel.userSettings.accentColor = selectedColor
                        chatViewModel.saveUserSettings()
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    Button("İptal") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                userName = chatViewModel.userSettings.userName
                selectedColor = chatViewModel.userSettings.accentColor
            }
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

#Preview {
    ContentView()
        .environmentObject(ChatViewModel())
}
