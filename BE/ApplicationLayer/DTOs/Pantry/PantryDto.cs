using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;

namespace ApplicationLayer.DTOs.Pantry
{
    public class PantryItemResponse
    {
        public string Id { get; set; } = string.Empty;
        public string Ingredient { get; set; } = string.Empty;
        public DateTime? ScannedAt { get; set; }
        public string? IngredientId { get; set; }
        public string? Category { get; set; }
        public int? CaloriesPer100g { get; set; }
        public double Quantity { get; set; }
        public string Unit { get; set; } = "phần";
        public DateTime? ExpiryDate { get; set; }
        public bool IsVegan { get; set; } = true;
        public string? AllergyWarning { get; set; }
    }

    public class AddPantryItemRequest
    {
        [Required(ErrorMessage = "Tên nguyên liệu không được để trống.")]
        public string Ingredient { get; set; } = string.Empty;

        public double Quantity { get; set; } = 1.0;

        public string Unit { get; set; } = "phần";

        public DateTime? ExpiryDate { get; set; }

        public DateTime? ScannedAt { get; set; }
    }

    public class AddPantryItemsBatchRequest
    {
        public List<AddPantryItemRequest> Items { get; set; } = new();
    }

    public class UpdatePantryItemRequest
    {
        public double Quantity { get; set; }

        public string? Unit { get; set; }

        public DateTime? ExpiryDate { get; set; }
    }
}

