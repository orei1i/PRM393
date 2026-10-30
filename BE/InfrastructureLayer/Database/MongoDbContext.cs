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
        public IMongoCollection<MediaAsset> MediaAssets => _database.GetCollection<MediaAsset>("MediaAssets");
        public IMongoCollection<Post> Posts => _database.GetCollection<Post>("Posts");
        public IMongoCollection<Comment> Comments => _database.GetCollection<Comment>("Comments");
        public IMongoCollection<PostLike> PostLikes => _database.GetCollection<PostLike>("PostLikes");
        public IMongoCollection<PostReport> PostReports => _database.GetCollection<PostReport>("PostReports");
        public IMongoCollection<HealthProfile> HealthProfiles => _database.GetCollection<HealthProfile>("HealthProfiles");
        public IMongoCollection<HealthMetricLog> HealthMetricLogs => _database.GetCollection<HealthMetricLog>("HealthMetricLogs");
        public IMongoCollection<Ingredient> Ingredients => _database.GetCollection<Ingredient>("Ingredients");
        public IMongoCollection<PantryItem> PantryItems => _database.GetCollection<PantryItem>("PantryItems");
        public IMongoCollection<Recipe> Recipes => _database.GetCollection<Recipe>("Recipes");
        public IMongoCollection<MealPlan> MealPlans => _database.GetCollection<MealPlan>("MealPlans");
        public IMongoCollection<AiLog> AiLogs => _database.GetCollection<AiLog>("AiLogs");
    }
}