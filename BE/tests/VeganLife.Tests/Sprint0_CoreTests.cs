using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using FluentAssertions;
using Microsoft.AspNetCore.Mvc.Infrastructure;
using Microsoft.Extensions.DependencyInjection;
using VeganLife.Tests.Fixtures;
using Xunit;

namespace VeganLife.Tests
{
    public class Sprint0_CoreTests : IClassFixture<CustomWebApplicationFactory>
    {
        private readonly CustomWebApplicationFactory _factory;
        private readonly HttpClient _client;

        public Sprint0_CoreTests(CustomWebApplicationFactory factory)
        {
            _factory = factory;
            _client = factory.CreateClient();
        }

        [Fact]
        public void B1_RouteScanner_NoDuplicateRoutesExist()
        {
            // B1: Quét toàn bộ ActionDescriptors xem có endpoint nào trùng HttpMethod + Path không
            using var scope = _factory.Services.CreateScope();
            var actionDescriptorCollectionProvider = scope.ServiceProvider
                .GetRequiredService<IActionDescriptorCollectionProvider>();

            var routes = actionDescriptorCollectionProvider.ActionDescriptors.Items
                .SelectMany(ad =>
                {
                    var httpMethods = ad.EndpointMetadata
                        .OfType<Microsoft.AspNetCore.Routing.IHttpMethodMetadata>()
                        .SelectMany(m => m.HttpMethods)
                        .DefaultIfEmpty("ANY");

                    var routeTemplate = ad.AttributeRouteInfo?.Template ?? "";
                    return httpMethods.Select(m => $"{m}:{routeTemplate.Trim('/').ToLowerInvariant()}");
                })
                .Where(r => !string.IsNullOrEmpty(r))
                .ToList();

            var duplicates = routes
                .GroupBy(r => r)
                .Where(g => g.Count() > 1)
                .Select(g => g.Key)
                .ToList();

            duplicates.Should().BeEmpty("không được có bất kỳ route trùng lặp nào trong hệ thống (gây AmbiguousMatchException 500)");
        }

        [Fact]
        public async Task B25_MalformedJsonPayload_Returns_StandardApiResponse400()
        {
            // Gửi một chuỗi JSON cú pháp sai (không đóng ngoặc nhọn)
            var malformedContent = new StringContent("{ \"email\": \"test@test.com\", ", Encoding.UTF8, "application/json");
            var response = await _client.PostAsync("/api/v1/auth/login", malformedContent);

            response.StatusCode.Should().Be(HttpStatusCode.BadRequest);

            var json = await response.Content.ReadAsStringAsync();
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            root.GetProperty("success").GetBoolean().Should().BeFalse();
            root.GetProperty("statusCode").GetInt32().Should().Be(400);
            root.GetProperty("message").GetString().Should().NotBeNullOrWhiteSpace();
        }

        [Fact]
        public async Task B25_MissingRequiredFields_Returns_StandardApiResponse400_WithErrors()
        {
            // Gửi body JSON rỗng {} thiếu các trường bắt buộc email/password
            var emptyContent = new StringContent("{}", Encoding.UTF8, "application/json");
            var response = await _client.PostAsync("/api/v1/auth/login", emptyContent);

            response.StatusCode.Should().Be(HttpStatusCode.BadRequest);

            var json = await response.Content.ReadAsStringAsync();
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            root.GetProperty("success").GetBoolean().Should().BeFalse();
            root.GetProperty("statusCode").GetInt32().Should().Be(400);
            root.GetProperty("message").GetString().Should().Be("Dữ liệu yêu cầu không hợp lệ.");
            root.TryGetProperty("errors", out var errors).Should().BeTrue();
            errors.ValueKind.Should().Be(JsonValueKind.Object);
        }
    }
}

