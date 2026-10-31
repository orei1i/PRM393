using System;
using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace DomainLayer.Entities
{
    public class PantryItem : BaseEntity
    {
        [BsonRepresentation(BsonType.ObjectId)]
        public string UserId { get; set; } = string.Empty;

        [BsonRepresentation(BsonType.ObjectId)]
        public string? IngredientId { get; set; }

        public string Ingredient { get; set; } = string.Empty;

        public string? NormalizedName { get; set; }

        public double Quantity { get; set; } = 1.0;

        public string Unit { get; set; } = "phần";

        public DateTime? ExpiryDate { get; set; }

        public DateTime? ScannedAt { get; set; }

        public string? Category { get; set; }

        public int? CaloriesPer100g { get; set; }

        public bool IsVegan { get; set; } = true;

        public System.Collections.Generic.List<string> Allergens { get; set; } = new();

        /// <summary>
        /// "manual" | "vision"
        /// </summary>
        public string Source { get; set; } = "manual";
    }
}

