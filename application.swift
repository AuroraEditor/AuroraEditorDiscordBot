import Foundation

struct Configuration: Codable {
    let settings: Settings
    let github: GitHub
    let discord: Discord

    struct Settings: Codable {
        let stats: [String]
    }

    struct GitHub: Codable {
        let url: String
        let token: String
        let repos: [String]
    }

    struct Discord: Codable {
        let webhook: String
        let tag: Int?
        let tagtreshold: Int
        let username: String
        let title: String
        let description: String?
        let url: String?
        let message: String?
        let tts: Bool?
        let file: String?
        let type: String?
        let color: String?
        let image: String?
        let footer: Footer?

        struct Footer: Codable {
            let text: String
            let icon_url: String
        }
    }
}

struct GitHubRepo: Codable {
    let name: String
    let owner: Owner
    let html_url: String
    let forks_count: Int
    let stargazers_count: Int
    let open_issues_count: Int
    let has_issues: Bool
    let subscribers_url: String
    let pulls_url: String

    // MARK: - License
    struct License: Codable {
        let key, name, spdxID: String
        let url: String
        let nodeID: String
    }

    // MARK: - Owner
    struct Owner: Codable {
        let login: String
        let avatar_url: String
    }
}

struct GitHubPullRequests: Codable {
    var title: String
    var html_url: String
    var user: User
    var draft: Bool? = false
    var createdAt: Date

    struct User: Codable {
        var login: String
        var html_url: String
    }
}

struct GitHubWatchers: Codable {
    var login: String
}

struct Embed {
    var name: String
    var value: String
    var inline: Bool

}
// Fail if the config file doesn't exist.
if !FileManager.default.fileExists(atPath: "config.json") {
    print("Config file not found.")
    exit(1)
}

// Load the configuration.
let configuration = try JSONDecoder().decode(
    Configuration.self,
    from: Data(contentsOf: URL(fileURLWithPath: "config.json"))
)

// Load the data from GitHub.
// let githubData:  =
if let githubData: [GitHubRepo] = fetchData(url: configuration.github.url) {
    // Walk through the repos.
    for repo in githubData {
        // Check if the repo is in the list of repos to check.
        // Otherwise, skip it.
        if !configuration.github.repos.contains(repo.name) {
            continue
        }

        // Parse the repo.
        parseRepo(repo: repo)
    }
} else {
    fatalError("Unable to parse the data from \(configuration.github.url)")
}

func parseRepo(repo: GitHubRepo) {
    // Get the current timestamp.
    let timestamp = Date()

    // Get the PR count.
    let PRCount: [GitHubPullRequests]? = fetchData(url: repo.pulls_url.replacingOccurrences(of: "{/number}", with: ""))

    // Get the Watchers
    let watchersCount: [GitHubWatchers]? = fetchData(url: repo.subscribers_url)

    // Create a new array for the discord message.
    var discordArray = [String: Any]()

    if configuration.discord.message != "" {
        discordArray["content"] = configuration.discord.message
    }
    
    discordArray["username"] = configuration.discord.username
    discordArray["avatar_url"] = repo.owner.avatar_url
    discordArray["tts"] = configuration.discord.tts ?? false
    discordArray["file"] = configuration.discord.file ?? ""

    // Create a new array for the embeds.
    var discordEmbedArray = [String: Any]()
    discordEmbedArray["title"] = configuration.discord.title
    discordEmbedArray["type"] = configuration.discord.type ?? "rich"

    discordEmbedArray["description"] = String(
        format: configuration.discord.description ?? "These are the statistics for [%s](https://github.com/%s),\r\nupdated on %s.",
        repo.name,
        repo.name,
        timestamp.description(with: .current)
    )

    discordEmbedArray["url"] = configuration.discord.url ?? "https://auroraeditor.com"
    discordEmbedArray["timestamp"] = timestamp
    discordEmbedArray["color"] = Int(configuration.discord.color ?? "3366ff", radix: 16)

    if configuration.discord.footer?.text != "" {
        discordEmbedArray["footer"] = [
            "text": configuration.discord.footer?.text ?? "",
            "icon_url": configuration.discord.footer?.icon_url ?? ""
        ]
    }

    if configuration.discord.image != "" {
        discordEmbedArray["image"] = [
            "url": configuration.discord.image ?? ""
        ]
    }

    discordEmbedArray["thumbnail"] = [
        "url": repo.owner.avatar_url
    ]

    var discordEmbedFieldsArray = [[String: Any]]()

    // Add the forks.
    discordEmbedFieldsArray.append([
        "name": "🪓 Forks",
        "value": String(
            format: "[%s](%s)",
            repo.forks_count,
            repo.html_url + "/forks"
        ),
        "inline": true
    ])

    // Add the watchers.
    discordEmbedFieldsArray.append([
        "name": "👁️ Watchers",
        "value": String(
            format: "[%s](%s)",
            watchersCount?.count ?? 0,
            repo.html_url + "/watchers"
        ),
        "inline": true
    ])

    // Add the stargazers.
    discordEmbedFieldsArray.append([
        "name": "⭐️ Stars",
        "value": String(
            format: "[%s](%s)",
            repo.stargazers_count,
            repo.html_url + "/stargazers"
        ),
        "inline": true
    ])

    // Check if issues are enabled.
    if repo.has_issues {
        // Add the issues.
        discordEmbedFieldsArray.append([
            "name": "🎯 Issues",
            "value": String(
                format: "[%s](%s)",
                repo.open_issues_count,
                repo.html_url + "/issues"
            ),
            "inline": true
        ])
    } else {
        // Filler, issues not enabled.
        discordEmbedFieldsArray.append([
            "name": " ",
            "value": " ",
            "inline": true
        ])
    }

    discordEmbedFieldsArray.append([
        "name": "🔨 PRs",
        "value": String(
            format: "[%s](%s)",
            PRCount?.count ?? 0,
            repo.html_url + "/pulls"
        ),
        "inline": true
    ])

    discordEmbedFieldsArray.append([
        "name": " ",
        "value": " ",
        "inline": true
    ])

    discordArray["fields"] = discordEmbedFieldsArray

    // Tag the reviewers if there are open PR's.
    if configuration.discord.tag != nil {
        var commits = ""

        for commit in PRCount ?? [] {
            let createdHoursAgo = 0.0
            // This has a segfault?, so disabled for now.
            // round(
            //     (timestamp.timeIntervalSince1970 - commit.createdAt.timeIntervalSince1970) / 3600
            // )
            commits += String(
                format: "- [%s](%s) by [%s](%s)%s, %s %s ago%s\r\n",
                commit.title,
                commit.html_url,
                commit.user.login,
                commit.user.html_url,
                commit.draft ?? false ? " _(Draft)_" : "",
                createdHoursAgo > 24.0 ? round(createdHoursAgo / 24.0) : createdHoursAgo,
                createdHoursAgo > 24.0 ? "days" : "hours",
                createdHoursAgo > (
                    Double(configuration.discord.tagtreshold)
                ) ? (commit.draft ?? false) ?
                "" :
                    String(
                        format: " ⚠️ <@&%s>",
                        configuration.discord.tag ?? "reviewers"
                    ) : ""
            )
        }

        discordArray["content"] = String(
            format: "The current amount of open PR's is %s, below a list with open PR's.\r\n%s%s",
            String(
                format: "[%s](%s)",
                PRCount?.count ?? 0,
                repo.html_url + "/pulls"
            ),
            commits,
            "‎ " // Left to right mark, to preserve space.
        )
    }

    // Add the embed array to the discord array.
    discordArray["embeds"] = [discordEmbedArray]

    let json_data = try? JSONSerialization.data(
        withJSONObject: discordArray,
        options: []
    )

    // let url = URL(string: configuration.discord.webhook)!
    // var request = URLRequest(url: url)
    // request.httpMethod = "POST"
    // request.httpBody = json_data
    // request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    // request.setValue("application/json", forHTTPHeaderField: "Accept")

    // TODO: execute the request

    dump(discordArray)
}

func fetchData<T: Codable>(url fromURL: String) -> T? {
    guard let url = URL(string: fromURL) else {
        print("Invalid URL")
        return nil
    }

    do {
        let json = try JSONDecoder().decode(
            T.self,
            from: Data(contentsOf: url)
        )

        return json
    } catch {
        print(error)
    }

    return nil
}
