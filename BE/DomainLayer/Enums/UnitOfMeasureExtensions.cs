namespace DomainLayer.Enums
{
    /// <summary>
    /// Extension methods for UnitOfMeasure and UnitType.
    /// </summary>
    public static class UnitOfMeasureExtensions
    {
        /// <summary>
        /// Returns the UnitType for the given UnitOfMeasure.
        /// Gram, Kilogram → Weight
        /// Milliliter, Liter → Volume
        /// Piece → Count
        /// </summary>
        public static UnitType GetUnitType(this UnitOfMeasure uom)
        {
            return uom switch
            {
                UnitOfMeasure.Gram or UnitOfMeasure.Kilogram => UnitType.Weight,
                UnitOfMeasure.Milliliter or UnitOfMeasure.Liter => UnitType.Volume,
                UnitOfMeasure.Piece => UnitType.Count,
                _ => throw new ArgumentOutOfRangeException(nameof(uom), uom, "Unknown UnitOfMeasure")
            };
        }

        /// <summary>
        /// Returns short display string for DB/API: Gram→"g", Kilogram→"kg", etc.
        /// </summary>
        public static string ToShortString(this UnitOfMeasure uom)
        {
            return uom switch
            {
                UnitOfMeasure.Gram => "g",
                UnitOfMeasure.Kilogram => "kg",
                UnitOfMeasure.Milliliter => "ml",
                UnitOfMeasure.Liter => "l",
                UnitOfMeasure.Piece => "pcs",
                _ => uom.ToString()
            };
        }

        /// <summary>
        /// Parses a string to UnitOfMeasure.
        /// Accepts common variants: "g", "Gram", "gram", "Kilogram", "kg", etc.
        /// </summary>
        public static UnitOfMeasure ParseUnitOfMeasure(string? value)
        {
            if (string.IsNullOrWhiteSpace(value))
                throw new ArgumentException("Unit of measure cannot be null or empty", nameof(value));

            var normalized = value.Trim();
            return normalized.ToLowerInvariant() switch
            {
                "g" or "gram" or "grams" => UnitOfMeasure.Gram,
                "kg" or "kilogram" or "kilograms" => UnitOfMeasure.Kilogram,
                "ml" or "milliliter" or "milliliters" => UnitOfMeasure.Milliliter,
                "l" or "liter" or "liters" or "litre" or "litres" => UnitOfMeasure.Liter,
                "pcs" or "piece" or "pieces" => UnitOfMeasure.Piece,
                _ => Enum.TryParse<UnitOfMeasure>(normalized, true, out var parsed) ? parsed
                    : throw new ArgumentException($"Unknown unit of measure: '{value}'", nameof(value))
            };
        }

        /// <summary>
        /// Parses a string to UnitType.
        /// </summary>
        public static UnitType ParseUnitType(string? value)
        {
            if (string.IsNullOrWhiteSpace(value))
                throw new ArgumentException("Unit type cannot be null or empty", nameof(value));

            return value.Trim().ToLowerInvariant() switch
            {
                "weight" => UnitType.Weight,
                "volume" => UnitType.Volume,
                "count" => UnitType.Count,
                _ => throw new ArgumentException($"Unknown unit type: '{value}'", nameof(value))
            };
        }
    }
}
