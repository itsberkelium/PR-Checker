using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace PRChecker.Core;

public abstract class ObservableObject : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    protected bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
        return true;
    }

    protected void Raise(string name) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

public sealed class ConnectionException(string message) : Exception(message)
{
    public static ConnectionException TokenRequired() => new(L10n.ErrorTokenRequired);
}

/// <summary>User settings. The server and token change only through <see cref="ApplyConnection"/> and <see cref="SignOut"/>.</summary>
public sealed class AppSettings : ObservableObject
{
    public static readonly int[] RefreshOptions = [1, 2, 5, 10, 15];
    public static readonly int[] RecentlyMergedOptions = [0, 3, 5, 10];

    private readonly ISettingsStore _store;
    private readonly ITokenStore _tokens;
    private SettingsData _data;
    /// <summary>Read from the credential store once per server.</summary>
    private (string ServerId, string? Token)? _cachedToken;
    private string[] _filterPatterns = [];

    public AppSettings(ISettingsStore store, ITokenStore tokens)
    {
        _store = store;
        _tokens = tokens;
        _data = store.Load();
        if (!RefreshOptions.Contains(_data.RefreshMinutes)) _data = _data with { RefreshMinutes = 5 };
        if (!RecentlyMergedOptions.Contains(_data.RecentlyMergedCount)) _data = _data with { RecentlyMergedCount = 3 };
        // A hand-edited file can still say "repoFilter": null.
        if (_data.RepoFilter is null) _data = _data with { RepoFilter = "" };
        Server = _data.ServerUrl is { } url && ServerAddress.TryParse(url, out var server) ? server : null;
        _filterPatterns = ParsePatterns(_data.RepoFilter);
        Localizer.Apply(_data.Language);
    }

    /// <summary>Replaced in tests to talk to a stub server.</summary>
    public HttpMessageHandler? HttpHandler { get; set; }

    public ServerAddress? Server { get; private set; }
    public string SavedServerUrl => _data.ServerUrl ?? "";

    public int RefreshMinutes { get => _data.RefreshMinutes; set => Update(_data with { RefreshMinutes = value }); }
    public bool HideDrafts { get => _data.HideDrafts; set => Update(_data with { HideDrafts = value }); }
    /// <summary>One of <see cref="RecentlyMergedOptions"/>.</summary>
    public int RecentlyMergedCount { get => _data.RecentlyMergedCount; set => Update(_data with { RecentlyMergedCount = value }); }
    /// <summary>Comma-separated project keys or "PROJECT/repo-slug" entries. Empty shows everything.</summary>
    public string RepoFilter
    {
        get => _data.RepoFilter;
        set { _filterPatterns = ParsePatterns(value); Update(_data with { RepoFilter = value }); }
    }
    public bool NotificationsEnabled { get => _data.NotificationsEnabled; set => Update(_data with { NotificationsEnabled = value }); }
    /// <summary>Off: notifications say only that something changed, without titles or names.</summary>
    public bool NotificationDetails { get => _data.NotificationDetails; set => Update(_data with { NotificationDetails = value }); }
    public bool OpenAtLogin { get => _data.OpenAtLogin; set => Update(_data with { OpenAtLogin = value }); }
    public int AcceptedTermsVersion { get => _data.AcceptedTermsVersion; set => Update(_data with { AcceptedTermsVersion = value }); }
    /// <summary>System follows the Windows display language; takes effect immediately.</summary>
    public LanguagePreference Language
    {
        get => _data.Language;
        set
        {
            Update(_data with { Language = value });
            Localizer.Apply(value);
        }
    }

    public const string DevChannel = "dev";

    /// <summary>Updates come from the dev feed, where builds are published before a release; takes effect at the next check.</summary>
    public bool DevUpdates
    {
        get => _data.UpdateChannel == DevChannel;
        set => Update(_data with { UpdateChannel = value ? DevChannel : null });
    }

    private void Update(SettingsData data, [CallerMemberName] string? name = null)
    {
        if (data == _data) return;
        _data = data;
        _store.Save(data);
        if (name is not null) Raise(name);
    }

    public bool HasToken(ServerAddress server) => !string.IsNullOrEmpty(TokenFor(server));

    public IPrProvider? MakeClient() =>
        Server is { } server && TokenFor(server) is { Length: > 0 } token ? MakeProvider(server, token) : null;

    /// <summary>
    /// Client for a connection that hasn't been applied yet. A blank token reuses the saved one
    /// only for the same server, so a token never goes to a new host.
    /// </summary>
    public IPrProvider DraftClient(string serverUrl, string draftToken)
    {
        var candidate = ServerAddress.Parse(serverUrl);
        var trimmed = draftToken.Trim();
        var token = trimmed.Length > 0 ? trimmed : TokenFor(candidate) ?? "";
        if (token.Length == 0) throw ConnectionException.TokenRequired();
        return MakeProvider(candidate, token);
    }

    /// <summary>The provider for a server; Bitbucket Server is the only one so far.</summary>
    private BitbucketClient MakeProvider(ServerAddress server, string token) => new(server, token, HttpHandler);

    /// <summary>
    /// Saves a validated connection. The token is written first; if that fails nothing changes.
    /// A previous server's token is removed when switching.
    /// </summary>
    public void ApplyConnection(IPrProvider client)
    {
        _tokens.Save(client.Token, TokenAccounts.For(client.Server));
        if (Server is { } old && old != client.Server)
        {
            try { _tokens.Delete(TokenAccounts.For(old)); } catch (TokenStoreException) { }
        }
        _cachedToken = (client.Server.Id, client.Token);
        Server = client.Server;
        Update(_data with { ServerUrl = client.Server.Id }, nameof(Server));
    }

    /// <summary>Removes the token for the current server. The server URL stays for convenience.</summary>
    public void SignOut()
    {
        if (Server is not { } server) return;
        _tokens.Delete(TokenAccounts.For(server));
        _cachedToken = (server.Id, null);
        Raise(nameof(Server));
    }

    private string? TokenFor(ServerAddress server)
    {
        if (_cachedToken is { } cached && cached.ServerId == server.Id) return cached.Token;
        var token = _tokens.Read(TokenAccounts.For(server));
        _cachedToken = (server.Id, token);
        return token;
    }

    public bool Includes(PrItem item)
    {
        if (HideDrafts && item.IsDraft) return false;
        if (_filterPatterns.Length == 0) return true;
        var project = item.ProjectKey.ToLowerInvariant();
        var repo = $"{project}/{item.RepoSlug.ToLowerInvariant()}";
        return _filterPatterns.Any(p => p == project || p == repo);
    }

    private static string[] ParsePatterns(string filter) =>
        filter.Split(',').Select(p => p.Trim().ToLowerInvariant()).Where(p => p.Length > 0).ToArray();
}
