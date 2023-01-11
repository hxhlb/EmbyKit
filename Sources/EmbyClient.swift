//
//  EmbyClient.swift
//  
//
//  Created by alexis on 2022/3/18.
//

import Foundation
import Just

/// Common emby items list completion handler.
public typealias EmbyListCompletion = (Result<ListItemResponse, Error>) -> Void

/// Common emby item array completion handler.
public typealias EmbyItemsCompletion = (Result<[EmbyItem], Error>) -> Void

/// EmbyClient
///
/// in your AppDelegate.swift configure EmbyKit using following code
/// `EmbyClient.configure(client: "emby", appVersion: "1.1.0", deviceId: "deviceId", deviceName: "Demo Device")`
///
/// create EmbyClient instance
/// `let client = EmbyClient(baseURL: URL(string: "http://example.com:8096")!)`
///
/// ```
public class EmbyClient {
    
    private static var hasConfigured = false
    private static var client = ""
    private static var appVersion = ""
    private static var deviceId = ""
    private static var deviceName = ""
    
    /// Emby server base url. MUST contains port
    public var baseURL: URL
    
    /// Currtent login user identifier
    public var userId = ""
    
    /// Called when access token is invalid
    public var accessTokenInvalidHandler: (() -> Void)?
    
    /// Access token of current
    public var accessToken: String? = nil
    
    /// HTTP Header to authorize with Emby server
    public var authorizationHeader: String = ""
    
    /// Create EmbyClient instance with server base url. Please call `EmbyClient.configure` before create embyclient.
    /// - Parameters:
    ///   - baseURL: server base url, should contains port info. such as http://example.com:8096 or https://example.com:443 .
    ///   - userId: userId, can be empty.
    ///   - accessToken: accessToken, can be nil.
    public init(baseURL: URL, userId: String = "", accessToken: String? = nil) {
        self.baseURL = baseURL
        self.userId = userId
        self.accessToken = accessToken
        if !EmbyClient.hasConfigured {
            fatalError("Please configure before using EmbyClient")
        }
        configureAuthorizationHeader()
    }
    
    private func configureAuthorizationHeader() {
        let guid = UUID().uuidString
        var list = [String]()
        list.append(String(format: "Emby UserId=%@", userId.isEmpty ? guid : userId))
        list.append("Client=\(EmbyClient.client)")
        list.append(String(format: "Device=%@", EmbyClient.deviceName.urlEncoded))
        list.append(String(format: "DeviceId=%@", EmbyClient.deviceId))
        list.append("Version=\(EmbyClient.appVersion)")
        authorizationHeader = list.joined(separator: ",")
    }
    
    /// Setup EmbyClient.
    /// - Parameters:
    ///   - client: app client name.
    ///   - appVersion: app version.
    ///   - deviceId: current device identifier.
    public static func configure(client: String, appVersion: String, deviceId: String, deviceName: String) {
        assert(!client.isEmpty, "client name can not be empty")
        assert(!appVersion.isEmpty, "appVersion can not be empty")
        assert(!deviceId.isEmpty, "deviceId can not be empty")
        assert(!deviceName.isEmpty, "deviceName can not be empty")
        EmbyClient.hasConfigured = true
        EmbyClient.client = client
        EmbyClient.appVersion = appVersion
        EmbyClient.deviceId = deviceId
        EmbyClient.deviceName = deviceName
    }
    
    /// Get Emby server information.
    /// - Parameter completion: Completion callback.
    public func getServerInfo(completion: @escaping (Result<SystemInfo, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("System/Info")
        request(.get, url: url, completion: completion)
    }
    
    /// Valid current server address is accessible.
    /// - Parameters:
    ///   - serverAddress: server address.
    ///   - completion: Completion callback.
    public func validServerAddress(_ serverAddress: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        let headers = ["Content-Type": "application/text"]
        let url = serverAddress.appending("/emby/web/manifest.json")
        Just.get(url, headers: headers, timeout: 2, asyncCompletionHandler:  { result in
            DispatchQueue.main.async {
                if let error = result.error {
                    completion(.failure(error))
                } else if result.ok {
                    completion(.success(true))
                } else if let code = result.statusCode {
                    let message = HTTPURLResponse.localizedString(forStatusCode: code)
                    let error = NSError(domain: "", code: code, userInfo: [
                        NSLocalizedFailureErrorKey: message
                    ])
                    completion(.failure(error))
                } else {
                    let error = NSError(domain: "", code: -1, userInfo: [
                        NSLocalizedFailureErrorKey: "unknown error"
                    ])
                    completion(.failure(error))
                }
            }
        })
    }
}

// MARK: - Users
extension EmbyClient {
    
    /// authenticate using username and password
    /// - Parameters:
    ///   - username: username.
    ///   - password: password.
    ///   - completion: completion callback.
    public func authenticate(username: String, password: String, completion: @escaping (Result<AuthenticationResponse, Error>) -> Void) {
        var json: [String: Any] = [:]
        json["Username"] = username
        json["Password"] = password
        json["Pw"] = password
        let url = baseURL.appendingPathComponent("Users/AuthenticateByName")
        request(.post, url: url, json: json, completion: completion)
    }
    
    /// Update user password.
    /// - Parameters:
    ///   - currentPassword: current password.
    ///   - newPassword: new password.
    ///   - completion: completion block.
    public func updatePassword(currentPassword: String, newPassword: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("Users/\(userId)/Password")
        var json: [String: Any] = [:]
        json["CurrentPw"] = currentPassword
        json["NewPw"] = newPassword
        
        var httpheaders = [String: String]()
        httpheaders["X-Emby-Authorization"] = authorizationHeader
        if let token = accessToken {
            httpheaders["X-Emby-Token"] = token
        }
        
        Just.post(url, json: json, headers: httpheaders, asyncCompletionHandler: { result in
            DispatchQueue.main.async {
                if let error = result.error {
                    completion(.failure(error))
                } else {
                    if let text = result.text, !text.isEmpty {
                        completion(.failure(NSError(domain: "Banana", code: -1, userInfo: [
                            NSLocalizedFailureReasonErrorKey: text,
                            NSLocalizedFailureErrorKey: ""
                        ])))
                    } else {
                        completion(.success(()))
                    }
                }
            }
        })
    }
    
    /// Get current user information.
    /// - Parameter completion: completion callback.
    public func getUserInfo(completion: @escaping (Result<EmbyUser, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("Users/\(userId)")
        request(.get, url: url, completion: completion)
    }
    
    /// Update user configurations.
    /// - Parameters:
    ///   - configuration: configuration.
    ///   - completion: completion callback.
    public func updateUserConfiguration(_ configuration: EmbyUserConfiguration, completion: @escaping (Result<Void, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("Users/\(userId)/Configuration")
        
        var json = [String: Any]()
        
        if let data = try? JSONEncoder().encode(configuration),
            let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = dict
        }
        
        var httpheaders = [String: String]()
        httpheaders["X-Emby-Authorization"] = authorizationHeader
        if let token = accessToken {
            httpheaders["X-Emby-Token"] = token
        }
        Just.post(url, json: json, headers: httpheaders, asyncCompletionHandler: { result in
            DispatchQueue.main.async {
                if let error = result.error {
                    completion(.failure(error))
                } else {
                    if let text = result.text, !text.isEmpty {
                        completion(.failure(NSError(domain: "Banana", code: -1, userInfo: [
                            NSLocalizedFailureReasonErrorKey: text,
                            NSLocalizedFailureErrorKey: ""
                        ])))
                    } else {
                        completion(.success(()))
                    }
                }
            }
        })
    }
    
    /// Get user home views.
    /// - Parameters:
    ///   - params: additional params.
    ///   - completion: completion callback.
    public func getUserHomeViews(params: [String: Any] = [:], completion: @escaping (Result<ItemsResponse, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("Users/\(userId)/Views")
        var parameters = params
        parameters["IncludeExternalContent"] = false
        request(.get, url: url, params: parameters, completion: completion)
    }
    
    /// Get user resume item with media type.
    /// - Parameters:
    ///   - mediaType: media type.
    ///   - params: additional parameters.
    ///   - completion: completion callback.
    public func getResumeItems(mediaType: MediaType, params: [String: Any], completion: @escaping EmbyListCompletion) {
        let url = baseURL.appendingPathComponent("Users/\(userId)/Items/Resume")
        request(.get, url: url, params: params, completion: completion)
    }
    
    /// Get user latest items.
    /// - Parameters:
    ///   - params: additional parameters.
    ///   - completion: completion callback.
    public func getLatestItems(params: [String: Any], completion: @escaping EmbyItemsCompletion) {
        let url = baseURL.appendingPathComponent("Users/\(userId)/Items/Latest")
        request(.get, url: url, params: params, completion: completion)
    }
    
    /// Get Emby item detail response.
    /// - Parameters:
    ///   - item: Instance of Emby Item.
    ///   - completion: Completion callback.
    public func getItemDetail(item: EmbyItem, completion: @escaping (Result<EmbyItem, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("Users/\(userId)/Items/\(item.id)")
        request(.get, url: url, completion: completion)
    }
    
    public func getAlbumItems(parentId: String, completion: @escaping EmbyListCompletion) {
        let url = baseURL.appendingPathComponent("Users/\(userId)/Items")
        var params: [String: Any] = [:]
        params["ParentId"] = parentId
        request(.get, url: url, params: params, completion: completion)
    }
    
    public func getItems(params: [String: Any], completion: @escaping EmbyListCompletion) {
        let url = baseURL.appendingPathComponent("Users/\(userId)/Items")
        request(.get, url: url, params: params, completion: completion)
    }
    
    public func updateFavoriteStatus(itemId: String, isFavorite: Bool, completion: @escaping (Result<String, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("Users/\(userId)/FavoriteItems/\(itemId)")
        let method: HTTPMethod = isFavorite ? .post: .delete
        request(method, url: url, completion: completion)
    }
    
    /// Mark item as played.
    /// - Parameters:
    ///   - itemId: ItemId.
    ///   - asPlayed: played.
    ///   - completion: Completion callback.
    public func markPlayed(itemId: String, asPlayed: Bool = true, completion: @escaping (Result<MarkPlayedResponse, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("Users/\(userId)/PlayedItems/\(itemId)")
        let method: HTTPMethod = asPlayed ? .post: .delete
        request(method, url: url, completion: completion)
    }
    
    public func getAlbums(parentId: String, startIndex: Int, completion: @escaping (Result<ListItemResponse, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("Users/\(userId)/Items")
        var params: [String: Any] = [:]
        params["IncludeItemTypes"] = "MusicAlbum"
        params["Recursive"] = true
        params["StartIndex"] = startIndex
        params["ParentId"] = parentId
        params["EnableImageTypes"] = "Primary"
        request(.get, url: url, params: params, completion: completion)
    }
    
    public func hideFromResume(itemId: String, completion: @escaping (Result<MarkPlayedResponse, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("Users/\(userId)/Items/\(itemId)/HideFromResume")
        let params = ["Hide": true]
        request(.post, url: url, params: params, completion: completion)
    }
    
    public func getStreamInfo(itemId: String, startTimeTicks: Int64, streamMetadata: EmbyStreamMetadata, completion: @escaping (Result<MediaSourcesResponse, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("Items/\(itemId)/PlaybackInfo")
        var params: [String: Any] = [:]
        params["UserId"] = userId
        params["StartTimeTicks"] = startTimeTicks
        params["IsPlayback"] = true
        params["AutoOpenLiveStream"] = true
        params["MaxStreamingBitrate"] = 42000000
        if let sourceId = streamMetadata.sourceInfo?.id {
            params["MediaSourceId"] = sourceId
        }
        if let audioStreamIndex = streamMetadata.audioStream?.index {
            params["AudioStreamIndex"] = audioStreamIndex
        }
        if let subtitleStreamIndex = streamMetadata.subtitleStream?.index {
            params["SubtitleStreamIndex"] = subtitleStreamIndex
        }
        let builder = DeviceProfileBuilder()
        let profile = DeviceProfileWrapper(deviceProfile: builder.build())
        let jsonString = profile.json
        let headers = ["Content-Type": "application/json"]
        request(.post, url: url, params: params, headers: headers, requestBody: jsonString.data(using: .utf8), completion: completion)
    }
}

// MARK: - Items
extension EmbyClient {
    
    /// Get similar items of some emby item.
    /// - Parameters:
    ///   - itemId: itemId.
    ///   - params: additional parameters.
    ///   - completion: completion callback.
    public func getSimilarItems(itemId: String, params: [String: Any], completion: @escaping EmbyListCompletion) {
        let url = baseURL.appendingPathComponent("Items/\(itemId)/Similar")
        request(.get, url: url, params: params, completion: completion)
    }
    
    public func getItemSpecialFeatures(itemId: String, completion: @escaping EmbyItemsCompletion) {
        let url = baseURL.appendingPathComponent("Users/\(userId)/Items/\(itemId)/SpecialFeatures")
        request(.get, url: url, completion: completion)
    }
    
    public func getRecommendations(params: [String: Any], completion: @escaping (Result<RecommendationsResponse, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("Movies/Recommendations")
        request(.get, url: url, params: params, completion: completion)
    }
    
    public func thumbnailURL(of item: EmbyItem, maxWidth: Int, maxHeight: Int) -> URL? {
        let url = baseURL.appendingPathComponent("Items/\(item.id)/Images")
        let urlString: String
        
        if let imageTags = item.imageTags, !imageTags.isEmpty, let tag = imageTags.first {
            if let thumb = imageTags["Thumb"] {
                urlString = url.absoluteString.appending("/Thumb?maxWidth=800&tag=\(thumb)&quality=90")
            } else if let primary = imageTags["Primary"] {
                urlString = url.absoluteString.appending("/Primary?maxWidth=800&tag=\(primary)&quality=90")
            } else {
                urlString = url.absoluteString.appending("/\(tag.key)?maxWidth=800&tag=\(tag.value)&quality=90")
            }
        } else if let tag = item.backdropImageTags?.first, !tag.isEmpty {
            urlString = url.absoluteString.appending("/Backdrop?maxWidth=800&tag=\(tag)&quality=90")
        } else if let tag = item.parentBackdropImageTags?.first, !tag.isEmpty, let parentBackdropId = item.parentBackdropItemId {
            urlString = baseURL.appendingPathComponent("Items/\(parentBackdropId)/Images").absoluteString.appending("/Backdrop?maxWidth=800&tag=\(tag)&quality=90")
        } else {
            urlString = baseURL.absoluteString.appending("/Items/\(item.id)/Images/Primary?maxHeight=\(maxHeight)&maxWidth=\(maxWidth)&quality=90")
        }
        return URL(string: urlString)
    }
    
    public func backdropURL(of item: EmbyItem, maxWidth: Int = 800) -> URL? {
        if let tag = item.backdropImageTags?.first, !tag.isEmpty {
            let url = baseURL.appendingPathComponent("Items/\(item.id)/Images")
            let urlString = url.absoluteString.appending("/Backdrop?maxWidth=\(maxWidth)&tag=\(tag)&quality=90")
            return URL(string: urlString)
        } else if let tag = item.parentBackdropImageTags?.first, let parentBackdropItemId = item.parentBackdropItemId {
            let url = baseURL.appendingPathComponent("Items/\(parentBackdropItemId)/Images")
            let urlString = url.absoluteString.appending("/0?maxWidth=\(maxWidth)&tag=\(tag)&quality=90")
            return URL(string: urlString)
        }
        return nil
    }
    
    public func getImageUrlString(id: String, type: EmbyImageType, width: Int, tag: String) -> String {
        let url = baseURL.appendingPathComponent("Items/\(id)/Images")
        return url.absoluteString.appending("/\(type.rawValue)?maxWidth=\(width)&tag=\(tag)&quality=90")
    }
    
    public func getItemTypes(params: [String: Any], completion: @escaping (Result<ItemTypeResponse, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("ItemTypes")
        request(.get, url: url, params: params, completion: completion)
    }
    
    public func getPlaybackInfo(item: EmbyItem, startTimeTicks: Int64, completion: @escaping (Result<MediaSourcesResponse, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("Items/\(item.id)/PlaybackInfo")
        var params: [String: Any] = [:]
        params["UserId"] = userId
        params["StartTimeTicks"] = startTimeTicks
        params["IsPlayback"] = true
        params["AutoOpenLiveStream"] = true
        params["MaxStreamingBitrate"] = 40000000
        
        let builder = DeviceProfileBuilder()
        let profile = DeviceProfileWrapper(deviceProfile: builder.build())
        let jsonString = profile.json
        let headers = ["Content-Type": "application/json"]
        request(.post, url: url, params: params, headers: headers, requestBody: jsonString.data(using: .utf8), completion: completion)
    }
}

// MARK: - Audio
extension EmbyClient {
    
    public func getAudioStreamUrl(itemId: String) -> URL? {
        let url = baseURL.appendingPathComponent("Audio/\(itemId)/universal")
        let builder = DeviceProfileBuilder().build()
        var params: [String: Any] = [:]
        params["UserId"] = userId
        params["DeviceId"] = EmbyClient.deviceId
        params["MaxStreamingBitrate"] = 40000000
        params["Container"] = builder.directPlayProfiles?.first?.audioCodec ?? "mp3"
        params["TranscodingContainer"] = builder.transcodingProfiles?.first?.audioCodec ?? "aac"
        params["TranscodingProtocol"] = builder.transcodingProfiles?.first?._protocol ?? "hls"
        params["AudioCodec"] = "aac"
        params["PlaySessionId"] = String(format: "%.0f", Date().timeIntervalSince1970 * 1000)
        params["api_key"] = accessToken ?? ""
        params["EnableRedirection"] = true
        
        var components: [(String, String)] = []
        for (key, value) in params.sorted(by: { $0.key < $1.key }) {
            components += self.queryComponents(key, value)
        }
        let query = (components.map { "\($0)=\($1)" }).joined(separator: "&")
        return URL(string: url.absoluteString.appending("?\(query)"))
    }
    
}

// MARK: - Video
extension EmbyClient {
    
    public func getAdditionalVideoParts(itemId: String, params: [String: Any], completion: @escaping EmbyListCompletion) {
        let url = baseURL.appendingPathComponent("Videos/\(itemId)/AdditionalParts")
        var parameters = params
        parameters["UserId"] = userId
        request(.get, url: url, params: params, completion: completion)
    }
    
}

// MARK: - Genres
extension EmbyClient {
    
    public func getGenreItems(params: [String: Any], completion: @escaping EmbyListCompletion) {
        let url = baseURL.appendingPathComponent("Genres")
        request(.get, url: url, params: params, completion: completion)
    }
}

// MARK: - Shows
extension EmbyClient {
    
    /// Get episodes of show.
    /// - Parameters:
    ///   - showId: showId
    ///   - params: additional parameters.
    ///   - completion: completion callback.
    public func getEpisodes(showId: String, params: [String: Any], completion: @escaping EmbyListCompletion) {
        let url = baseURL.appendingPathComponent("Shows/\(showId)/Episodes")
        request(.get, url: url, params: params, completion: completion)
    }
    
    public func getSeasons(itemId: String, params: [String: Any], completion: @escaping EmbyListCompletion) {
        let url = baseURL.appendingPathComponent("Shows/\(itemId)/Seasons")
        request(.get, url: url, params: params, completion: completion)
    }
    
    /// Get upcoming espisodes.
    /// - Parameters:
    ///   - params: additional parameters.
    ///   - completion: completion callback.
    public func getUpcomingEpisodes(params: [String: Any], completion: @escaping EmbyListCompletion) {
        let url = baseURL.appendingPathComponent("Shows/Upcoming")
        request(.get, url: url, params: params, completion: completion)
    }
    
    /// Get next up shows.
    /// - Parameters:
    ///   - params: parameters.
    ///   - completion: completion block.
    public func getNextUpEpisodes(params: [String: Any], completion: @escaping EmbyListCompletion) {
        let url = baseURL.appendingPathComponent("Shows/NextUp")
        request(.get, url: url, params: params, completion: completion)
    }
}

// MARK: - Persons
extension EmbyClient {
    
    public func getPersons(params: [String: Any], completion: @escaping EmbyListCompletion) {
        let url = baseURL.appendingPathComponent("Persons")
        request(.get, url: url, params: params, completion: completion)
    }
    
    public func getArtists(params: [String: Any], completion: @escaping EmbyListCompletion) {
        let url = baseURL.appendingPathComponent("Artists")
        request(.get, url: url, params: params, completion: completion)
    }
}

// MARK: - Studios
extension EmbyClient {
    
    public func getStudioItems(params: [String: Any], completion: @escaping EmbyListCompletion) {
        let url = baseURL.appendingPathComponent("Studios")
        request(.get, url: url, params: params, completion: completion)
    }
}

// MARK: - Sessions
extension EmbyClient {
    
    public func reportSessionStart(info: PlaybackStartInfo) {
        let url = baseURL.appendingPathComponent("Sessions/Playing")
        report(url: url, body: info.json.data(using: .utf8))
    }
    
    public func reportSessionProgress(info: PlaybackProgressInfo) {
        let url = baseURL.appendingPathComponent("Sessions/Playing/Progress")
        report(url: url, body: info.json.data(using: .utf8))
    }
    
    public func reportSessionStopped(info: PlaybackStopInfo) {
        let url = baseURL.appendingPathComponent("Sessions/Playing/Stopped")
        report(url: url, body: info.json.data(using: .utf8))
    }
    
    private func report(url: URL, body: Data?) {
        var headers = [String: String]()
        headers["X-Emby-Authorization"] = authorizationHeader
        if let token = accessToken {
            headers["X-Emby-Token"] = token
        }
        headers["Content-Type"] = "application/json"
        Just.post(url, headers: headers, requestBody: body)
    }
}

// MARK: - Internal
extension EmbyClient {
        
    func request<T: Codable>(_ method: HTTPMethod,
                 url: URLComponentsConvertible,
                 params: [String: Any] = [:],
                 data: [String: Any] = [:],
                 json: Any? = nil,
                 headers: [String: String] = [:],
                 files: [String: HTTPFile] = [:],
                 requestBody: Data? = nil,
                 progressHandler: ((HTTPProgress) -> Void)? = nil,
                 completion: @escaping (Result<T, Error>) -> Void) {
        
        var httpheaders = headers
        httpheaders["X-Emby-Authorization"] = authorizationHeader
        if let token = accessToken {
            httpheaders["X-Emby-Token"] = token
        }
        
        Just.request(method, url: url, params: params, data: data, json: json,
                     headers: httpheaders, files: files, requestBody: requestBody, asyncProgressHandler: { progress in
            DispatchQueue.main.async {
                progressHandler?(progress)
            }
        }, asyncCompletionHandler: { response in
            DispatchQueue.main.async {
                self.handleResponse(response,
                                    method: method,
                                    url: url,
                                    params: params,
                                    data: data,
                                    json: json,
                                    headers: headers,
                                    requestBody: requestBody,
                                    progressHandler: progressHandler,
                                    completion: completion)
            }
        })
    }
    
    func handleResponse<T: Codable>(_ response: HTTPResult,
                        method: HTTPMethod,
                        url: URLComponentsConvertible,
                        params: [String: Any] = [:],
                        data: [String: Any] = [:],
                        json: Any? = nil,
                        headers: [String: String] = [:],
                        requestBody: Data? = nil,
                        progressHandler: ((HTTPProgress) -> Void)? = nil,
                        completion: @escaping (Result<T, Error>) -> Void) {
        if let err = response.error {
            if response.statusCode == 401 {
                accessTokenInvalidHandler?()
            }
            completion(.failure(err))
        } else {
            if response.json == nil, response.text != nil {
                if response.statusCode == 401 {
                    accessTokenInvalidHandler?()
                }
                completion(.failure(EmbyError.serverError(response)))
            } else {
                if let content = response.content {
                    do {
                        let result = try JSONDecoder().decode(T.self, from: content)
                        completion(.success(result))
                    } catch {
                        print(error)
                        completion(.failure(error))
                    }
                } else {
                    completion(.failure(EmbyError.jsonDecodeError(response)))
                }
            }
        }
    }
    
    func queryComponents(_ key: String, _ value: Any) -> [(String, String)] {
        var components: [(String, String)] = []
        if let dictionary = value as? [String: Any] {
            for (nestedKey, value) in dictionary {
                components += queryComponents("\(key)[\(nestedKey)]", value)
            }
        } else if let array = value as? [Any] {
            for value in array {
                components += queryComponents("\(key)", value)
            }
        } else {
            components.append((
                percentEncodeString(key),
                percentEncodeString("\(value)"))
            )
        }
        return components
    }
    
    func percentEncodeString(_ originalObject: Any) -> String {
        if originalObject is NSNull {
            return "null"
        } else {
            var reserved = CharacterSet.urlQueryAllowed
            reserved.remove(charactersIn: ": #[]@!$&'()*+, ;=")
            return String(describing: originalObject)
                .addingPercentEncoding(withAllowedCharacters: reserved) ?? ""
        }
    }
}

public func secondsFromEmbyTicks(_ ticks: Int64) -> Int64 {
    return ticks / 10_000_000
}
