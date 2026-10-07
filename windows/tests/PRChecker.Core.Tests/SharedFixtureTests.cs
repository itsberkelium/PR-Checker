using System.Text.Json;
using System.Text.Json.Nodes;
using PRChecker.Core;

namespace PRChecker.Core.Tests;

/// <summary>Runs the cases in shared/fixtures, which the macOS tests check too.</summary>
public sealed class SharedFixtureTests
{
    private static JsonNode Load(string name) => JsonNode.Parse(File.ReadAllText(Fixtures.Path(name)))!;
    private static T Decode<T>(JsonNode node) => node.Deserialize<T>(Json.Options)!;

    [Fact]
    public void Review_list()
    {
        var data = Load("review-list");
        var server = ServerAddress.Parse((string)data["server"]!);
        var user = (string)data["user"]!;
        var page = Decode<Page<PullRequest>>(data["dashboard"]!);
        var expected = data["expected"]!.AsArray();

        var items = page.Values.Select(pr => PrItem.ForReview(pr, user, server)).OfType<PrItem>().ToList();
        Assert.Equal(expected.Select(e => (string)e!["id"]!), items.Select(i => i.Id));
        foreach (var (item, want) in items.Zip(expected))
        {
            Assert.Equal((string)want!["link"]!, item.Url.AbsoluteUri);
            Assert.Equal((bool)want["newCommits"]!, item.HasNewCommits);
            Assert.Equal((bool)want["conflicts"]!, item.HasConflicts);
            Assert.Equal((int)want["comments"]!, item.CommentCount);
            Assert.Equal((int)want["openTasks"]!, item.OpenTaskCount);
        }
    }

    [Fact]
    public void Comments_by_others()
    {
        var data = Load("activities");
        var page = Decode<Page<Activity>>(data["page"]!);
        var comments = BitbucketClient.CommentsByOthers(page.Values, (string)data["user"]!);
        var expected = data["expected"]!.AsArray()
            .Select(e => new Comment((long)e!["id"]!, (long)e["created"]!, (string)e["author"]!));
        Assert.Equal(expected, comments);
    }

    [Fact]
    public void Build_states()
    {
        foreach (var testCase in Load("build-stats")["cases"]!.AsArray())
        {
            var state = BuildStates.From(Decode<BuildStats>(testCase!["stats"]!));
            Assert.Equal((string)testCase["expected"]!, state.ToString().ToLowerInvariant());
        }
    }

    [Fact]
    public void Server_addresses()
    {
        var data = Load("servers");
        foreach (var testCase in data["parse"]!.AsArray())
        {
            var input = (string)testCase!["input"]!;
            if (testCase["id"] is { } id)
            {
                Assert.Equal((string)id!, ServerAddress.Parse(input).Id);
            }
            else
            {
                var error = Assert.Throws<ServerAddress.InvalidException>(() => ServerAddress.Parse(input));
                Assert.Equal((string)testCase["error"]!, JsonNamingPolicy.CamelCase.ConvertName(error.Problem.ToString()), ignoreCase: true);
            }
        }
        var owns = data["owns"]!;
        var server = ServerAddress.Parse((string)owns["server"]!);
        foreach (var testCase in owns["cases"]!.AsArray())
        {
            var url = (string)testCase!["url"]!;
            Assert.True((bool)testCase["owned"]! == server.Owns(url), url);
        }
    }
}
