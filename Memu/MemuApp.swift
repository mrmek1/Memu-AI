//
//  MemuApp.swift
//  Memu
//
//  Created by edex on 26.01.2025.
//

import SwiftUI

@main
struct MemuApp: App {
    @StateObject private var chatViewModel = ChatViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(chatViewModel)
                .preferredColorScheme(.dark)
        }
    }
}

class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isTyping = false
    @Published var conversations: [Conversation] = []
    @Published var selectedConversationId: UUID?
    @Published var userSettings = UserSettings()
    
    private let apiURL = ""
    private let apikey = ""
    private var isProcessing = false
    private var currentTask: Task<Void, Never>?
    
    private let queue = DispatchQueue(label: "com.memu.chatQueue", qos: .userInitiated)
    private let saveQueue = DispatchQueue(label: "com.memu.saveQueue", qos: .background)
    
    private let urlSession = URLSession.shared
    private let jsonDecoder = JSONDecoder()
    private let retryLimit = 3
    private var retryCount = 0
    
    init() {
        loadConversations()
        loadUserSettings()
    }
    
    private func loadUserSettings() {
        if let data = UserDefaults.standard.data(forKey: "userSettings"),
           let settings = try? JSONDecoder().decode(UserSettings.self, from: data) {
            userSettings = settings
        }
    }
    
    func saveUserSettings() {
        if let encoded = try? JSONEncoder().encode(userSettings) {
            UserDefaults.standard.set(encoded, forKey: "userSettings")
        }
    }
    
    func startNewConversation() {
        selectedConversationId = UUID()
        messages = []
        saveCurrentConversation()
    }
    
    func loadConversation(_ id: UUID) {
        selectedConversationId = id
        if let conversation = conversations.first(where: { $0.id == id }) {
            messages = conversation.messages
        }
    }
    
    private func saveCurrentConversation() {
        saveQueue.async { [weak self] in
            guard let self = self,
                  let id = self.selectedConversationId else { return }
            
            DispatchQueue.main.async {
                if let index = self.conversations.firstIndex(where: { $0.id == id }) {
                    self.conversations[index].messages = self.messages
                } else {
                    let newConversation = Conversation(id: id, messages: self.messages)
                    self.conversations.insert(newConversation, at: 0)
                }
                
                self.saveQueue.async {
                    self.saveConversations()
                }
            }
        }
    }
    
    private func loadConversations() {
        if let data = UserDefaults.standard.data(forKey: "conversations"),
           let decoded = try? JSONDecoder().decode([Conversation].self, from: data) {
            conversations = decoded
            if let firstConversation = decoded.first {
                selectedConversationId = firstConversation.id
                messages = firstConversation.messages
            }
        } else {
            startNewConversation()
        }
    }
    
    private func saveConversations() {
        if let encoded = try? JSONEncoder().encode(conversations) {
            UserDefaults.standard.set(encoded, forKey: "conversations")
        }
    }
    
    func parseResponse(_ response: String) -> FormattedMessage {
        // Liste formatını kontrol et
        if response.contains("liste:") || response.contains("Liste:") {
            let items = response
                .components(separatedBy: "\n")
                .filter { $0.contains("- ") }
                .map { $0.replacingOccurrences(of: "- ", with: "") }
            
            if !items.isEmpty {
                return FormattedMessage(content: response, format: .list(items: items))
            }
        }
        
        // Oyun önerisi formatını kontrol et
        if response.contains("oyun önerisi:") || response.contains("Oyun önerisi:") {
            var games: [Game] = []
            let lines = response.components(separatedBy: "\n")
            
            var currentGame: (name: String, desc: String?, platform: String?, genre: String?)?
            
            for line in lines {
                if line.contains("- ") {
                    if let currentGame = currentGame {
                        games.append(Game(
                            name: currentGame.name,
                            description: currentGame.desc,
                            platform: currentGame.platform,
                            genre: currentGame.genre
                        ))
                    }
                    currentGame = (
                        name: line.replacingOccurrences(of: "- ", with: ""),
                        desc: nil,
                        platform: nil,
                        genre: nil
                    )
                } else if let game = currentGame {
                    if line.contains("Platform:") {
                        currentGame?.platform = line.replacingOccurrences(of: "Platform: ", with: "")
                    } else if line.contains("Tür:") {
                        currentGame?.genre = line.replacingOccurrences(of: "Tür: ", with: "")
                    } else if !line.isEmpty {
                        currentGame?.desc = line
                    }
                }
            }
            
            if let lastGame = currentGame {
                games.append(Game(
                    name: lastGame.name,
                    description: lastGame.desc,
                    platform: lastGame.platform,
                    genre: lastGame.genre
                ))
            }
            
            if !games.isEmpty {
                return FormattedMessage(content: response, format: .gameRecommendation(games: games))
            }
        }
        
        return FormattedMessage(content: response, format: .normal)
    }
    
    private func createPrompt(for text: String) -> String {
        let recentMessages = messages.suffix(10).map { message in
            let role = message.role == .user ? "Kullanıcı" : "Memu"
            return "\(role): \(message.content)"
        }.joined(separator: "\n")
        
        return """
        Sistem: Sen Memu'sun. Türkçe konuşan, arkadaş canlısı ve yardımsever bir yapay zeka asistanısın.
        
        Özellikler:
        - Her zaman Memu olarak kendinden bahset
        - Emoji kullanmayı sev
        - Samimi ve arkadaş canlısı ol
        - Türkçe karakterleri doğru kullan
        - Kullanıcının adı: \(userSettings.userName)
        - Önceki mesajları dikkate al ve tutarlı cevaplar ver
        
        Özel formatlar:
        1. Liste formatı:
        Bir liste oluştururken şu formatı kullan:
        liste:
        - öğe 1
        - öğe 2
        - öğe 3
        
        2. Oyun önerisi formatı:
        Oyun önerirken şu formatı kullan:
        oyun önerisi:
        - [Oyun Adı]
        Platform: [Platform]
        Tür: [Tür]
        [Kısa açıklama]
        
        Sohbet Geçmişi:
        \(recentMessages)
        
        Kullanıcı: \(text)
        """
    }
    
    func sendMessage(_ text: String) {
        guard !isProcessing else { return }
        isProcessing = true
        
        currentTask?.cancel()
        
        let userMessage = ChatMessage(id: UUID(), role: .user, content: text)
        
        withAnimation {
            messages.append(userMessage)
            isTyping = true
        }
        
        currentTask = Task { @MainActor in
            do {
                let prompt = createPrompt(for: text)
                
                guard let encodedPrompt = prompt.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let url = URL(string: "\(apiURL)?prompt=\(encodedPrompt)") else {
                    throw APIError.invalidURL
                }
                
                let (data, response) = try await URLSession.shared.data(from: url)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }
                
                guard httpResponse.statusCode == 200 else {
                    throw APIError.serverError(statusCode: httpResponse.statusCode)
                }
                
                guard let jsonString = String(data: data, encoding: .utf8),
                      let messageStart = jsonString.range(of: "\"message\": \""),
                      let messageEnd = jsonString[messageStart.upperBound...].range(of: "\"") else {
                    throw APIError.invalidData
                }
                
                let message = String(jsonString[messageStart.upperBound..<messageEnd.lowerBound])
                    .replacingOccurrences(of: "\\\"", with: "\"")
                    .replacingOccurrences(of: "\\n", with: "\n")
                
                if Task.isCancelled { return }
                
                withAnimation {
                    let formattedMessage = parseResponse(message)
                    let aiMessage = ChatMessage(id: UUID(), role: .assistant, content: formattedMessage.content)
                    messages.append(aiMessage)
                    isTyping = false
                    isProcessing = false
                    saveCurrentConversation()
                }
                
            } catch {
                if Task.isCancelled { return }
                
                withAnimation {
                    let errorMessage = ChatMessage(
                        id: UUID(),
                        role: .assistant,
                        content: "Üzgünüm, bir hata oluştu. Lütfen tekrar dener misin? 😔"
                    )
                    messages.append(errorMessage)
                    isTyping = false
                    isProcessing = false
                    saveCurrentConversation()
                }
            }
        }
    }
    
    func cancelCurrentRequest() {
        currentTask?.cancel()
        currentTask = nil
        
        withAnimation {
            isTyping = false
            isProcessing = false
        }
    }
    
    func deleteConversation(_ id: UUID) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                withAnimation {
                    self.conversations.removeAll(where: { $0.id == id })
                }
                
                if id == self.selectedConversationId {
                    if let firstConversation = self.conversations.first {
                        self.loadConversation(firstConversation.id)
                    } else {
                        self.startNewConversation()
                    }
                }
                
                self.saveQueue.async {
                    self.saveConversations()
                }
            }
        }
    }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date
    
    init(id: UUID = UUID(), role: MessageRole, content: String) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
    
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id &&
        lhs.role == rhs.role &&
        lhs.content == rhs.content &&
        lhs.timestamp == rhs.timestamp
    }
}

enum MessageRole: Codable {
    case user
    case assistant
}

struct Conversation: Identifiable, Codable {
    let id: UUID
    var messages: [ChatMessage]
    var title: String {
        messages.first?.content.prefix(30).description ?? "Yeni Sohbet"
    }
}

struct UserSettings: Codable {
    var userName: String = "Kullanıcı"
    var accentColor: String = "58A6FF"
}

enum APIError: Error {
    case invalidURL
    case invalidResponse
    case invalidData
    case networkError
    case serverError(statusCode: Int)
    case tooManyRequests
}

enum MessageFormat {
    case normal
    case list(items: [String])
    case gameRecommendation(games: [Game])
    case error
}

struct Game: Codable, Equatable {
    let name: String
    let description: String?
    let platform: String?
    let genre: String?
}

struct FormattedMessage {
    let content: String
    let format: MessageFormat
}
