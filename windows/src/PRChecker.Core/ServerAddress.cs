namespace PRChecker.Core;

/// <summary>
/// A validated Bitbucket server base URL, e.g. <c>https://bitbucket.example.com/context</c>.
/// Tokens and stored PR data are scoped to <see cref="Id"/>; links are only opened and
/// redirects only followed when <see cref="Owns"/> accepts them. See docs/behavior.md.
/// </summary>
public sealed record ServerAddress
{
    public enum Problem { Invalid, NotHttps, HasCredentials, HasQueryOrFragment }

    public sealed class InvalidException(Problem problem) : Exception(Describe(problem))
    {
        public Problem Problem { get; } = problem;
    }

    /// <summary>Normalized: lowercase host, default port dropped, no trailing slash.</summary>
    public Uri BaseUrl { get; }
    public string Host { get; }
    public int Port { get; }
    /// <summary>Percent-encoded context path without trailing slash, "" at the root.</summary>
    public string Path { get; }
    /// <summary>Stable identifier for scoping tokens and stored data.</summary>
    public string Id { get; }

    private ServerAddress(string host, int port, string path)
    {
        Host = host;
        Port = port;
        Path = path;
        Id = "https://" + host + (port == 443 ? "" : ":" + port) + path;
        BaseUrl = new Uri(Id);
    }

    public static ServerAddress Parse(string raw)
    {
        var trimmed = raw.Trim();
        if (!Uri.TryCreate(trimmed, UriKind.Absolute, out var uri) || !trimmed.Contains("://", StringComparison.Ordinal))
            throw new InvalidException(Problem.Invalid);
        if (!string.Equals(uri.Scheme, "https", StringComparison.OrdinalIgnoreCase))
            throw new InvalidException(Problem.NotHttps);
        if (string.IsNullOrEmpty(uri.Host)) throw new InvalidException(Problem.Invalid);
        if (!string.IsNullOrEmpty(uri.UserInfo)) throw new InvalidException(Problem.HasCredentials);
        if (!string.IsNullOrEmpty(uri.Query) || !string.IsNullOrEmpty(uri.Fragment) || trimmed.Contains('?') || trimmed.Contains('#'))
            throw new InvalidException(Problem.HasQueryOrFragment);

        return new ServerAddress(uri.Host.ToLowerInvariant(), uri.Port, uri.AbsolutePath.TrimEnd('/'));
    }

    public static bool TryParse(string raw, out ServerAddress? server)
    {
        try { server = Parse(raw); return true; }
        catch (InvalidException) { server = null; return false; }
    }

    /// <summary>Whether <paramref name="url"/> is an https URL on this server, inside its context path.</summary>
    public bool Owns(Uri? url)
    {
        if (url is null || !url.IsAbsoluteUri) return false;
        if (!string.Equals(url.Scheme, "https", StringComparison.OrdinalIgnoreCase)) return false;
        if (!string.Equals(url.Host, Host, StringComparison.OrdinalIgnoreCase)) return false;
        if (url.Port != Port || !string.IsNullOrEmpty(url.UserInfo)) return false;
        var path = url.AbsolutePath;
        return Path.Length == 0 || path == Path || path.StartsWith(Path + "/", StringComparison.Ordinal);
    }

    public bool Owns(string? url) => Uri.TryCreate(url, UriKind.Absolute, out var uri) && Owns(uri);

    /// <summary>
    /// Web page of a pull request, built from trusted configuration rather than links in
    /// API responses. Each identifier is encoded as a single path component.
    /// </summary>
    public Uri PullRequestUrl(string projectKey, string repoSlug, int number) =>
        new(Id + "/projects/" + Segment(projectKey) + "/repos/" + Segment(repoSlug) + "/pull-requests/" + number);

    /// <summary>Path for API requests relative to the server, e.g. "rest/api/1.0/...".</summary>
    public Uri ApiUrl(string relativePath) => new(Id + "/" + relativePath);

    internal static string Segment(string value)
    {
        var escaped = Uri.EscapeDataString(value);
        // "." and ".." would be collapsed into path navigation; keep them inert.
        return escaped.Trim('.').Length == 0 ? escaped.Replace(".", "%252E", StringComparison.Ordinal) : escaped;
    }

    private static string Describe(Problem problem) => problem switch
    {
        Problem.NotHttps => "The server URL must start with https://.",
        Problem.HasCredentials => "Remove the user name or password from the server URL.",
        Problem.HasQueryOrFragment => "Remove the ?query or #fragment from the server URL.",
        _ => "Enter a server URL like https://bitbucket.example.com.",
    };

    public override string ToString() => Id;
}
