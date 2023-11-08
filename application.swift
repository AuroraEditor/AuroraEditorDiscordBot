import Foundation

#if canImport(FoundationNetworking)
// Support network calls in Linux.
import FoundationNetworking
#endif

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
        let tag: Int
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
    var draft: Bool
    // var createdAt: Date

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
    print("Unable to parse the data from \(configuration.github.url)")
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
        "value": "[\(repo.forks_count)](\(repo.html_url + "/forks")",
        "inline": true
    ])

    // Add the watchers.
    discordEmbedFieldsArray.append([
        "name": "👁️ Watchers",
        "value": "[\(watchersCount?.count ?? 0)](\(repo.html_url + "/watchers"))",
        "inline": true
    ])

    // Add the stargazers.
    discordEmbedFieldsArray.append([
        "name": "⭐️ Stars",
        "value": "[\(repo.stargazers_count)](\(repo.html_url + "/stargazers"))",
        "inline": true
    ])

    // Check if issues are enabled.
    if repo.has_issues {
        // Add the issues.
        discordEmbedFieldsArray.append([
            "name": "🎯 Issues",
            "value": "[\(repo.open_issues_count)](\(repo.html_url + "/issues"))",
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
        "value": "[\(PRCount?.count ?? 0)](\(repo.html_url + "/pulls"))",
        "inline": true
    ])

    discordEmbedFieldsArray.append([
        "name": " ",
        "value": " ",
        "inline": true
    ])

    discordArray["fields"] = discordEmbedFieldsArray

    // Tag the reviewers if there are open PR's.
    var commits = ""

        for commit in PRCount ?? [] {
            let createdHoursAgo = 0.0
            // This has a segfault?, so disabled for now.
            // round(
            //     (timestamp.timeIntervalSince1970 - commit.createdAt.timeIntervalSince1970) / 3600
            // )
            let isDraft = commit.draft ? " _(Draft)_" : ""
            let createdAgo = (createdHoursAgo > 24.0 ? "\(createdHoursAgo / 24.0)" : "\(createdHoursAgo)") + (createdHoursAgo > 24.0 ? "days" : "hours")
            let notify = !commit.draft && createdHoursAgo > (
                    Double(configuration.discord.tagtreshold)
                ) ? " ⚠️ <@&\(configuration.discord.tag)>" : ""
        
            commits += "- [\(commit.title)](\(commit.html_url)) by [\(commit.user.login)](\(commit.user.html_url))\(isDraft), \(createdAgo) ago\(notify)\r\n"
        }

        discordArray["content"] = "The current amount of open PR's is [\(PRCount?.count ?? 0)](\(repo.html_url + "/pulls")), below a list with open PR's.\r\n\(commits) "

    // Add the embed array to the discord array.
    discordArray["embeds"] = [discordEmbedArray]

    do {
        let json_data = try JSONSerialization.data(
           withJSONObject: discordArray,
           options: []
        )

         let url = URL(string: configuration.discord.webhook)!
         var request = URLRequest(url: url)
         request.httpMethod = "POST"
         request.httpBody = json_data
         request.setValue("application/json", forHTTPHeaderField: "Content-Type")
         request.setValue("application/json", forHTTPHeaderField: "Accept")

         var keeprunning = true
         URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let response = response as? HTTPURLResponse,
                  error == nil
             else {
                 print("HTTP ERROR")
                 print(error!.localizedDescription)
                 keeprunning = false
                 return
             }
                                               
             dump([String(decoding: data, as: UTF8.self), response.statusCode, json_data])
             keeprunning = false
         }.resume()

         while (keeprunning) {
             // We can not yet exit.
         }
    } catch {
        print("FAILED TO CREATE JSON")
        print(error)
        print("Dict \(discordArray.self)")
        print(discordArray)
        return
    }
}

// WARNING: BAD PRACTICE, I'M FORCING THE PROGRAM TO WAIT FOR THE DATA.
func fetchData<T: Codable>(url fromURL: String) -> T? {
    guard let url = URL(string: fromURL) else {
        print("Invalid URL")
        return nil
    }

    var wait = true
    var data: Data?

    var request = URLRequest(url: url)
    request.setValue("en", forHTTPHeaderField: "Accept-language")
    request.setValue("Mozilla/5.0 (iPad; U; CPU OS 3_2 like Mac OS X; en-us)", forHTTPHeaderField: "User-Agent")

    if configuration.github.token != "" {
        request.setValue("Bearer \(configuration.github.token)", forHTTPHeaderField: "Authorization")
    }

    request.httpMethod = "GET"

    let task = URLSession.shared.dataTask(with: request) { ddata, response, error in
        guard
            let ddata = ddata,
                let response = response as? HTTPURLResponse,
                error == nil
        else {
            print("HTTP ERROR")
            print(error!.localizedDescription)
            wait = false
            return
        }

        guard (200 ... 299) ~= response.statusCode else {
            print("statusCode should be 2xx, but is \(response.statusCode)")
            print("response = \(response)")
            wait = false
            return
        }

        data = ddata
        wait = false
    }

    task.resume()

    while (wait) { }

    do {
        let json = try JSONDecoder().decode(
            T.self,
            from: data!
        )

        return json
    } catch {
        print(error)
    }

    return nil
}

// Tell the OS that the program exited successfully.
exit(0)
