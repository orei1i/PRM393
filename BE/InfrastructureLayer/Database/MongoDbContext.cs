using MongoDB.Driver;
using Microsoft.Extensions.Configuration;
using DomainLayer.Entities;

namespace InfrastructureLayer.Database
{
    public class MongoDbContext
    {
        private readonly IMongoDatabase _database;

        public MongoDbContext(IConfiguration configuration)
        {
            var client = new MongoClient(configuration.GetConnectionString("MongoConnection"));
            _database = client.GetDatabase(configuration["DatabaseName"] ?? "PRM393DB");
        }

        public IMongoDatabase Database => _database;

        public IMongoCollection<User> Users => _database.GetCollection<User>("Users");
    }
}