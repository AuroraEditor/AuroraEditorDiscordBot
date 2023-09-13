<?php
// Load the configuration.
$configuration = parse_ini_file("config.ini", true);

// Load the data from GitHub.
$githubData = fetchData($configuration['github']['url']);

// Get the avatar URL.
$avatarURL = $githubData[0]['owner']['avatar_url'] ?? '';

// Walk through the repos.
foreach ($githubData as $repo) {
    // Check if the repo is in the list of repos to check.
    // Otherwise, skip it.
    if (!in_array($repo['name'], $configuration['github']['repos'])) {
        continue;
    }

    // Parse the repo.
    sendToDiscord($repo);
}

function sendToDiscord($repo)
{
    global $configuration, $avatarURL;

    // Get the current timestamp.
    $timestamp = date("c", strtotime("now"));

    // Get the PR count.
    $PRCount = fetchData($repo['pulls_url']);

    // Get the Watchers
    $watchersCount = fetchData($repo['subscribers_url']);

    // Create a new array for the discord message.
    $discordArray = array();

    if ($configuration['discord']['message'] ?? "" != "") {
        $discordArray["content"] = $configuration['discord']['message'];
    }
    if ($configuration['discord']['username'] ?? "" != "") {
        $discordArray["username"] = $configuration['discord']['username'];
    }
    if ($avatarURL != "") {
        $discordArray["avatar_url"] = $avatarURL;
    }

    $discordArray["tts"] = $configuration['discord']['tts'] ?? false;
    $discordArray["file"] = $configuration['discord']['file'] ?? "";

    // Create a new array for the embeds.
    $discordEmbedArray = array();
    $discordEmbedArray["title"] = $configuration['discord']['title'];
    $discordEmbedArray["type"] = $configuration['discord']['type'] ?? 'rich';

    $discordEmbedArray["description"] = sprintf(
        preg_replace(
            array("/\\\\r/", "/\\\\n/"),
            array("\r", "\n"),
            $configuration['discord']['description'] ?? "These are the statistics for [%s](https://github.com/%s),\r\nupdated on %s."
        ),
        $repo['name'],
        $repo['name'],
        date("r")
    );

    $discordEmbedArray["url"] = $configuration['discord']['url'] ?? "https://auroraeditor.com";
    $discordEmbedArray["timestamp"] = $timestamp;
    $discordEmbedArray["color"] = hexdec($configuration['discord']['color'] ?? "3366ff");

    if (!empty($discordEmbedArray["footer"]["text"] ?? "")) {
        $discordEmbedArray["footer"] = array();
        $discordEmbedArray["footer"]["text"] = $configuration['discord']['footer']['text'] ?? "";
        $discordEmbedArray["footer"]["icon_url"] = $configuration['discord']['footer']['icon_url'] ?? "";
    }

    if (!empty($configuration['discord']['image'] ?? "")) {
        $discordEmbedArray["image"]["url"] = $configuration['discord']['image'] ?? "";
    }

    $discordEmbedArray["thumbnail"]["url"] = $avatarURL;

    $discordEmbedArray["fields"] = array();

    // Add the forks.
    $discordEmbedArray["fields"][] = array(
        "name" => "🪓 Forks",
        "value" => sprintf(
            "[%s](%s)",
            $repo['forks_count'] ?? 0,
            ($repo['html_url'] ?? '') . '/forks',
        ),
        "inline" => true
    );

    // Add the watchers.
    $discordEmbedArray["fields"][] = array(
        "name" => "👁️ Watchers",
        "value" => sprintf(
            "[%s](%s)",
            count($watchersCount ?? 0) ?? 0,
            ($repo['html_url'] ?? '') . '/watchers'
        ),
        "inline" => true
    );

    // Add the stargazers.
    $discordEmbedArray["fields"][] = array(
        "name" => "⭐️ Stars",
        "value" => sprintf(
            "[%s](%s)",
            $repo['stargazers_count'] ?? 0,
            ($repo['html_url'] ?? '') . '/stargazers',
        ),
        "inline" => true
    );

    // Check if issues are enabled.
    if ($repo['has_issues'] ?? 0 == 1) {
        // Add the issues.
        $discordEmbedArray["fields"][] = array(
            "name" => "🎯 Issues",
            "value" => sprintf(
                "[%s](%s)",
                $repo['open_issues_count'] ?? 0,
                ($repo['html_url'] ?? '') . '/issues'
            ),
            "inline" => true
        );
    } else {
        // Filler, issues not enabled.
        $discordEmbedArray["fields"][] = array(
            "name" => " ",
            "value" => " ",
            "inline" => true
        );
    }

    $discordEmbedArray["fields"][] = array(
        "name" => "🔨 PRs",
        "value" => sprintf(
            "[%s](%s)",
            count($PRCount ?? 0),
            ($repo['html_url'] ?? '') . '/pulls'
        ),
        "inline" => true
    );

    $discordEmbedArray["fields"][] = array(
        "name" => " ",
        "value" => " ",
        "inline" => true
    );

    // Add the embed array to the discord array.
    $discordArray["embeds"][] = $discordEmbedArray;

    $json_data = json_encode(
        $discordArray,
        JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE
    );

    $ch = curl_init($configuration['discord']['webhook']);
    curl_setopt($ch, CURLOPT_HTTPHEADER, array('Content-type: application/json'));
    curl_setopt($ch, CURLOPT_POST, 1);
    curl_setopt($ch, CURLOPT_POSTFIELDS, $json_data);
    curl_setopt($ch, CURLOPT_FOLLOWLOCATION, 1);
    curl_setopt($ch, CURLOPT_HEADER, 0);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);

    $response = curl_exec($ch);
    curl_close($ch);
}

function fetchData($url)
{
    $url = str_replace('{/number}', '', $url);

    $options = array(
        'http' => array(
            'method' => "GET",
            'header' => "Accept-language: en\r\n" .
                "User-Agent: Mozilla/5.0 (iPad; U; CPU OS 3_2 like Mac OS X; en-us) AppleWebKit/531.21.10 (KHTML, like Gecko) Version/4.0.4 Mobile/7B334b Safari/531.21.102011-10-16 20:23:10\r\n" // i.e. An iPad 
        )
    );

    $context = stream_context_create($options);

    return json_decode(file_get_contents($url, false, $context), true);
}
