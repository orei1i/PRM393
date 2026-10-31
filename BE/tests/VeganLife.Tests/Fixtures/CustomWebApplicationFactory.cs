using System;
using System.IO;
using System.Linq;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

namespace VeganLife.Tests.Fixtures
{
    public class CustomWebApplicationFactory : WebApplicationFactory<Program>
    {
        public string TestDatabaseName { get; } = $"VeganLife_Test_{Guid.NewGuid():N}";

        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.UseEnvironment("Development");

            builder.ConfigureAppConfiguration((context, config) =>
            {
                var testMongoConnection = Environment.GetEnvironmentVariable("TEST_MONGO_CONNECTION") 
                                          ?? "mongodb://localhost:27017/?serverSelectionTimeoutMS=2000";

                config.AddInMemoryCollection(new[]
                {
                    new KeyValuePair<string, string?>("ConnectionStrings:MongoConnection", testMongoConnection),
                    new KeyValuePair<string, string?>("DatabaseName", TestDatabaseName),
                    new KeyValuePair<string, string?>("JwtSettings:SecretKey", "VeganLife_Integration_Test_Secret_Key_At_Least_32_Chars!"),
                    new KeyValuePair<string, string?>("JwtSettings:Issuer", "VeganLifeTestIssuer"),
                    new KeyValuePair<string, string?>("JwtSettings:Audience", "VeganLifeTestAudience")
                });
            });
            builder.ConfigureServices(services =>
            {
                services.PostConfigure<Microsoft.AspNetCore.Authentication.JwtBearer.JwtBearerOptions>(
                    Microsoft.AspNetCore.Authentication.JwtBearer.JwtBearerDefaults.AuthenticationScheme, options =>
                {
                    options.TokenValidationParameters = new Microsoft.IdentityModel.Tokens.TokenValidationParameters
                    {
                        ValidateIssuer = true,
                        ValidateAudience = true,
                        ValidateLifetime = true,
                        ValidateIssuerSigningKey = true,
                        ValidIssuer = "VeganLifeTestIssuer",
                        ValidAudience = "VeganLifeTestAudience",
                        IssuerSigningKey = new Microsoft.IdentityModel.Tokens.SymmetricSecurityKey(
                            System.Text.Encoding.UTF8.GetBytes("VeganLife_Integration_Test_Secret_Key_At_Least_32_Chars!"))
                    };
                });
            });
        }
    }
}
